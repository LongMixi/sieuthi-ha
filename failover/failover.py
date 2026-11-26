from contextlib import contextmanager
import logging
import os
import time
import mysql.connector

# Đọc cấu hình từ biến môi trường (tránh hardcode mật khẩu khi triển khai thực tế)
MASTER_HOST = os.getenv('MASTER_HOST', 'mysql-master')
SLAVE1_HOST = os.getenv('SLAVE1_HOST', 'mysql-slave1')
SLAVE2_HOST = os.getenv('SLAVE2_HOST', 'mysql-slave2')
DB_USER = os.getenv('DB_USER', 'root')
DB_PASS = os.getenv('DB_PASS', 'rootpassword')
REPL_USER = os.getenv('REPL_USER', 'replica_user')
REPL_PASS = os.getenv('REPL_PASS', 'Replica@123')

PROXYSQL_HOST = os.getenv('PROXYSQL_HOST', 'proxysql')
PROXYSQL_PORT = int(os.getenv('PROXYSQL_PORT', '6032'))
PROXYSQL_ADMIN_USER = os.getenv('PROXYSQL_ADMIN_USER', 'admin')
PROXYSQL_ADMIN_PASS = os.getenv('PROXYSQL_ADMIN_PASS', 'admin')

CHECK_INTERVAL = int(os.getenv('CHECK_INTERVAL', '3'))
FAIL_THRESHOLD = int(os.getenv('FAIL_THRESHOLD', '3'))
ALLOWED_HOSTS = {MASTER_HOST, SLAVE1_HOST, SLAVE2_HOST}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("watchdog")


@contextmanager
def db_cursor(host, port=3306, user=DB_USER, password=DB_PASS, timeout=5, dictionary=False):
    """Context manager đảm bảo luôn đóng cả cursor và connection, tránh rò rỉ tài nguyên."""
    conn = None
    cur = None
    try:
        conn = mysql.connector.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            connection_timeout=timeout,
            autocommit=True,
        )
        cur = conn.cursor(dictionary=dictionary)
        yield cur
    finally:
        if cur is not None:
            try:
                cur.close()
            except Exception:
                pass
        if conn is not None and conn.is_connected():
            try:
                conn.close()
            except Exception:
                pass


def validate_host(host):
    if host not in ALLOWED_HOSTS:
        raise ValueError(f"Host không nằm trong danh sách cho phép: {host}")


def check_node_alive(host, port=3306, user=DB_USER, password=DB_PASS):
    try:
        with db_cursor(host, port=port, user=user, password=password, timeout=2) as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
            return True
    except Exception:
        return False


def get_read_only(host):
    with db_cursor(host, timeout=3) as cur:
        cur.execute("SELECT @@global.read_only;")
        return int(cur.fetchone()[0])


def set_read_only(host, read_only, super_read_only=None):
    validate_host(host)
    with db_cursor(host) as cur:
        if read_only:
            cur.execute("SET GLOBAL read_only = 1;")
            if super_read_only is True:
                cur.execute("SET GLOBAL super_read_only = 1;")
            elif super_read_only is False:
                cur.execute("SET GLOBAL super_read_only = 0;")
        else:
            cur.execute("SET GLOBAL super_read_only = 0;")
            cur.execute("SET GLOBAL read_only = 0;")


def get_gtid_executed(host):
    with db_cursor(host) as cur:
        cur.execute("SELECT @@global.gtid_executed;")
        return (cur.fetchone()[0] or "").strip()


def gtid_diff(host, gtid_a, gtid_b):
    with db_cursor(host) as cur:
        cur.execute("SELECT GTID_SUBTRACT(%s, %s);", (gtid_a, gtid_b))
        return (cur.fetchone()[0] or "").strip()


def get_replica_status(host):
    with db_cursor(host, dictionary=True) as cur:
        cur.execute("SHOW REPLICA STATUS;")
        return cur.fetchone()


def stop_and_reset_replica(host):
    validate_host(host)
    with db_cursor(host) as cur:
        cur.execute("STOP REPLICA;")
        cur.execute("RESET REPLICA ALL;")


def wait_relay_log_applied(host, timeout=30):
    """Dừng I/O thread rồi chờ SQL thread áp dụng hết Relay Log đã tải về."""
    validate_host(host)
    with db_cursor(host) as cur:
        cur.execute("STOP REPLICA IO_THREAD;")

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = get_replica_status(host)
        if not status:
            return True
        retrieved = (status.get("Retrieved_Gtid_Set") or "").strip()
        executed = (status.get("Executed_Gtid_Set") or "").strip()
        sql_running = status.get("Replica_SQL_Running")
        if sql_running != "Yes":
            err = status.get("Last_SQL_Error") or "SQL thread đã dừng"
            raise RuntimeError(f"{host}: Replica_SQL_Running={sql_running} ({err})")
        if not retrieved or not gtid_diff(host, retrieved, executed):
            return True
        time.sleep(0.5)

    raise RuntimeError(f"{host}: Hết {timeout}s chờ SQL thread áp dụng hết Relay Log.")


def wait_gtid_caught_up(target_host, source_host, timeout=60, interval=1.0):
    """Chờ target_host bắt kịp toàn bộ GTID của source_host; quá hạn sẽ raise lỗi."""
    deadline = time.monotonic() + timeout
    last_missing = ""
    while time.monotonic() < deadline:
        src_gtid = get_gtid_executed(source_host)
        tgt_gtid = get_gtid_executed(target_host)
        last_missing = gtid_diff(target_host, src_gtid, tgt_gtid)
        if not last_missing:
            return True
        time.sleep(interval)

    raise RuntimeError(
        f"{target_host} chưa bắt kịp GTID của {source_host} sau {timeout}s (thiếu: {last_missing})"
    )


def point_replica(target_host, source_host):
    validate_host(target_host)
    validate_host(source_host)
    with db_cursor(target_host) as cur:
        cur.execute("STOP REPLICA;")
        cur.execute("RESET REPLICA ALL;")
        cur.execute(
            """
            CHANGE REPLICATION SOURCE TO
              SOURCE_HOST = %s,
              SOURCE_PORT = 3306,
              SOURCE_USER = %s,
              SOURCE_PASSWORD = %s,
              SOURCE_AUTO_POSITION = 1,
              GET_SOURCE_PUBLIC_KEY = 1;
            """,
            (source_host, REPL_USER, REPL_PASS),
        )
        cur.execute("START REPLICA;")


def verify_replica(target_host, expected_source, timeout=15):
    """Xác minh replica trỏ đúng source, IO=Yes, SQL=Yes và không có lỗi."""
    deadline = time.monotonic() + timeout
    last_info = "Không có trạng thái replica"
    while time.monotonic() < deadline:
        status = get_replica_status(target_host)
        if status:
            src = status.get("Source_Host")
            io_run = status.get("Replica_IO_Running")
            sql_run = status.get("Replica_SQL_Running")
            io_err = status.get("Last_IO_Errno", 0)
            sql_err = status.get("Last_SQL_Errno", 0)
            last_info = (
                f"Source={src}, IO={io_run} (err={io_err}: {status.get('Last_IO_Error')}), "
                f"SQL={sql_run} (err={sql_err}: {status.get('Last_SQL_Error')})"
            )
            if src == expected_source and io_run == "Yes" and sql_run == "Yes" and io_err == 0 and sql_err == 0:
                return True
        time.sleep(0.5)

    raise RuntimeError(f"Xác minh replication thất bại trên {target_host}: {last_info}")


def update_proxysql(servers):
    """Upsert backend mới trước, chỉ xóa backend cũ không dùng nữa rồi LOAD TO RUNTIME nguyên tử."""
    for _, host in servers:
        validate_host(host)

    with db_cursor(
        PROXYSQL_HOST, port=PROXYSQL_PORT,
        user=PROXYSQL_ADMIN_USER, password=PROXYSQL_ADMIN_PASS
    ) as cur:
        for hg, host in servers:
            cur.execute(
                """
                INSERT OR REPLACE INTO mysql_servers
                  (hostgroup_id, hostname, port, status, max_connections)
                VALUES (%s, %s, 3306, 'ONLINE', 1000);
                """,
                (hg, host),
            )

        cur.execute("SELECT hostgroup_id, hostname FROM mysql_servers;")
        desired = set(servers)
        for hg, host in cur.fetchall():
            if (int(hg), host) not in desired:
                cur.execute(
                    "DELETE FROM mysql_servers WHERE hostgroup_id = %s AND hostname = %s;",
                    (hg, host),
                )

        cur.execute("LOAD MYSQL SERVERS TO RUNTIME;")
        cur.execute("SAVE MYSQL SERVERS TO DISK;")


def detect_cluster_state():
    """Đọc trạng thái thực tế từ cụm MySQL (không phụ thuộc RAM khi container restart)."""
    if check_node_alive(SLAVE1_HOST):
        try:
            if get_read_only(SLAVE1_HOST) == 0:
                return "FAILED_OVER"
        except Exception:
            pass
    return "NORMAL"


def promote_slave1():
    log.warning("Master bị sập! Bắt đầu quy trình Auto-Failover an toàn...")
    slave1_mutated = False
    try:
        # Bước 0: Pre-flight kiểm tra Slave 1 & ProxySQL sẵn sàng trước khi sửa topology
        if not check_node_alive(SLAVE1_HOST):
            raise RuntimeError("mysql-slave1 không phản hồi, không thể failover.")
        if not check_node_alive(
            PROXYSQL_HOST, port=PROXYSQL_PORT,
            user=PROXYSQL_ADMIN_USER, password=PROXYSQL_ADMIN_PASS
        ):
            raise RuntimeError("ProxySQL admin không phản hồi, tạm hoãn failover.")

        # Bước 1: Chờ Slave 1 áp dụng hết Relay Log và kiểm tra không bị trễ hơn Slave 2
        log.info("[1/5] Đợi mysql-slave1 áp dụng hết Relay Log...")
        wait_relay_log_applied(SLAVE1_HOST, timeout=30)

        slave2_up = check_node_alive(SLAVE2_HOST)
        if slave2_up:
            wait_relay_log_applied(SLAVE2_HOST, timeout=15)
            ahead_on_s2 = gtid_diff(
                SLAVE1_HOST, get_gtid_executed(SLAVE2_HOST), get_gtid_executed(SLAVE1_HOST)
            )
            if ahead_on_s2:
                raise RuntimeError(
                    f"mysql-slave1 đang trễ hơn mysql-slave2 (thiếu GTID: {ahead_on_s2}), hủy thăng cấp!"
                )

        # Bước 2: Ngắt replica trên Slave 1 (vẫn giữ read_only=1 cho đến khi xác minh xong Slave 2)
        log.info("[2/5] Ngắt replica trên mysql-slave1 (tạm giữ read_only=1)...")
        stop_and_reset_replica(SLAVE1_HOST)
        slave1_mutated = True

        # Bước 3: Điều hướng Slave 2 sang Slave 1 và xác minh replication chạy OK
        if slave2_up:
            log.info("[3/5] Điều hướng mysql-slave2 sang mysql-slave1 và xác minh...")
            point_replica(SLAVE2_HOST, SLAVE1_HOST)
            verify_replica(SLAVE2_HOST, SLAVE1_HOST, timeout=15)
            log.info("[OK] mysql-slave2 đã đồng bộ ổn định từ mysql-slave1.")
        else:
            log.warning("mysql-slave2 đang tắt, bỏ qua bước nối Slave 2.")

        # Bước 4: Mở quyền ghi cho Slave 1 (chính thức làm Master mới)
        log.info("[4/5] Mở quyền ghi cho mysql-slave1...")
        set_read_only(SLAVE1_HOST, read_only=False)

        # Bước 5: Cập nhật ProxySQL nguyên tử (Ghi -> Slave 1, Đọc -> Slave 2)
        log.info("[5/5] Cập nhật ProxySQL (Ghi -> mysql-slave1, Đọc -> mysql-slave2)...")
        backends = [(10, SLAVE1_HOST)]
        if slave2_up:
            backends.append((20, SLAVE2_HOST))
        update_proxysql(backends)

        log.info("[THÀNH CÔNG] Auto-Failover hoàn tất an toàn!")
        return True

    except Exception as e:
        log.error("[LỖI FAILOVER] %s", e)
        if slave1_mutated:
            try:
                set_read_only(SLAVE1_HOST, read_only=True, super_read_only=False)
                log.warning("[ROLLBACK] Đã giữ mysql-slave1 ở chế độ read_only=1.")
            except Exception as rb_err:
                log.error("[LỖI ROLLBACK] Không thể đặt lại read_only trên Slave 1: %s", rb_err)
        return False


def failback_to_master():
    log.info("Phát hiện mysql-master đã sống lại! Bắt đầu Auto-Failback an toàn...")
    slave1_locked = False
    slave1_pointed_to_master = False
    try:
        # Bước 1: Khóa ghi ngay trên Master cũ để chống split-brain
        set_read_only(MASTER_HOST, read_only=True, super_read_only=True)

        # Bước 2: Kiểm tra errant transaction trên Master cũ
        errant = gtid_diff(
            SLAVE1_HOST, get_gtid_executed(MASTER_HOST), get_gtid_executed(SLAVE1_HOST)
        )
        if errant:
            raise RuntimeError(f"Master cũ có errant GTID ({errant}), dừng failback để tránh mất dữ liệu!")

        # Bước 3: Cho Master cũ làm Slave tạm của Slave 1, xác minh và đợi bắt kịp GTID (bắt buộc)
        log.info("[1/5] Cho mysql-master đồng bộ bù từ mysql-slave1...")
        point_replica(MASTER_HOST, SLAVE1_HOST)
        verify_replica(MASTER_HOST, SLAVE1_HOST, timeout=15)
        wait_gtid_caught_up(MASTER_HOST, SLAVE1_HOST, timeout=60, interval=1.0)
        log.info("[OK] mysql-master đã bắt kịp GTID của mysql-slave1.")

        # Bước 4: Khóa ghi tạm trên Slave 1 và chốt giao dịch cuối sang Master (bắt buộc)
        log.info("[2/5] Khóa ghi tạm trên mysql-slave1 và chốt giao dịch cuối...")
        set_read_only(SLAVE1_HOST, read_only=True, super_read_only=True)
        slave1_locked = True
        wait_gtid_caught_up(MASTER_HOST, SLAVE1_HOST, timeout=15, interval=0.5)

        # Bước 5: Dựng lại topology (Master vẫn giữ read_only=1) và xác minh trước khi mở ghi
        log.info("[3/5] Dựng lại topology (Slave 1 & Slave 2 -> Master) và xác minh...")
        stop_and_reset_replica(MASTER_HOST)

        set_read_only(SLAVE1_HOST, read_only=True, super_read_only=False)
        point_replica(SLAVE1_HOST, MASTER_HOST)
        slave1_pointed_to_master = True
        verify_replica(SLAVE1_HOST, MASTER_HOST, timeout=15)

        slave2_up = check_node_alive(SLAVE2_HOST)
        if slave2_up:
            point_replica(SLAVE2_HOST, MASTER_HOST)
            verify_replica(SLAVE2_HOST, MASTER_HOST, timeout=15)

        # Bước 6: Topology mới đã xác minh OK -> mở quyền ghi trên Master
        log.info("[4/5] Topology mới đã xác minh OK. Mở quyền ghi trên mysql-master...")
        set_read_only(MASTER_HOST, read_only=False)
        slave1_locked = False
        slave1_pointed_to_master = False

        # Bước 7: Khôi phục ProxySQL nguyên tử (Ghi -> Master, Đọc -> Slave 1 & Slave 2)
        log.info("[5/5] Khôi phục ProxySQL (1 Master - 2 Slave)...")
        backends = [(10, MASTER_HOST), (20, SLAVE1_HOST)]
        if slave2_up:
            backends.append((20, SLAVE2_HOST))
        update_proxysql(backends)

        log.info("[THÀNH CÔNG] Auto-Failback hoàn tất an toàn!")
        return True

    except Exception as e:
        log.error("[LỖI FAILBACK] %s", e)
        if slave1_locked:
            try:
                set_read_only(MASTER_HOST, read_only=True, super_read_only=True)
                if slave1_pointed_to_master:
                    stop_and_reset_replica(SLAVE1_HOST)
                set_read_only(SLAVE1_HOST, read_only=False)
                log.warning("[ROLLBACK] Đã khôi phục quyền ghi cho mysql-slave1 để cụm không bị treo.")
            except Exception as rb_err:
                log.error("[LỖI ROLLBACK] Không thể khôi phục quyền ghi cho Slave 1: %s", rb_err)
        return False


if __name__ == "__main__":
    log.info("Watchdog (Auto-Failover & Auto-Failback) đang khởi động...")
    time.sleep(15)

    state = detect_cluster_state()
    log.info("Trạng thái cụm phát hiện lúc khởi động: %s", state)

    fail_count = 0
    recover_count = 0

    while True:
        alive = check_node_alive(MASTER_HOST)

        if state == "NORMAL":
            if alive:
                if fail_count > 0:
                    log.info("Master đã kết nối lại bình thường.")
                fail_count = 0
            else:
                fail_count += 1
                log.warning("Master không phản hồi (Lần %d/%d)...", fail_count, FAIL_THRESHOLD)
                if fail_count >= FAIL_THRESHOLD:
                    if promote_slave1():
                        state = "FAILED_OVER"
                        fail_count = 0
                        recover_count = 0
                    else:
                        state = detect_cluster_state()
                        fail_count = 0
                        time.sleep(15)

        elif state == "FAILED_OVER":
            if alive:
                recover_count += 1
                log.info("Master cũ phản hồi lại (Lần %d/%d)...", recover_count, FAIL_THRESHOLD)
                if recover_count >= FAIL_THRESHOLD:
                    if failback_to_master():
                        state = "NORMAL"
                        recover_count = 0
                    else:
                        state = detect_cluster_state()
                        recover_count = 0
                        time.sleep(30)
            else:
                recover_count = 0

        time.sleep(CHECK_INTERVAL)
