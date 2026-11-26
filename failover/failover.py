import time
import mysql.connector

MASTER_HOST = 'mysql-master'
SLAVE1_HOST = 'mysql-slave1'
SLAVE2_HOST = 'mysql-slave2'
DB_PASS = 'rootpassword'
REPL_USER = 'replica_user'
REPL_PASS = 'Replica@123'

PROXYSQL_HOST = 'proxysql'
PROXYSQL_PORT = 6032
PROXYSQL_ADMIN_USER = 'radmin'
PROXYSQL_ADMIN_PASS = 'radmin'


def connect_db(host, port=3306, user='root', password=DB_PASS, timeout=5):
    return mysql.connector.connect(
        host=host, port=port, user=user, password=password, connection_timeout=timeout
    )


def check_master_alive():
    conn = None
    try:
        conn = connect_db(MASTER_HOST, timeout=2)
        return conn.is_connected()
    except Exception:
        return False
    finally:
        if conn and conn.is_connected():
            conn.close()


def get_gtid_executed(host):
    conn = connect_db(host)
    try:
        cur = conn.cursor()
        cur.execute("SELECT @@global.gtid_executed;")
        val = cur.fetchone()[0] or ""
        cur.close()
        return val
    finally:
        conn.close()


def gtid_diff(host, gtid_a, gtid_b):
    conn = connect_db(host)
    try:
        cur = conn.cursor()
        cur.execute("SELECT GTID_SUBTRACT(%s, %s);", (gtid_a, gtid_b))
        val = cur.fetchone()[0] or ""
        cur.close()
        return val.strip()
    finally:
        conn.close()


def point_replica(target_host, source_host):
    conn = connect_db(target_host)
    try:
        cur = conn.cursor()
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
        cur.close()
    finally:
        conn.close()


def update_proxysql(servers):
    """servers: list of (hostgroup_id, hostname)"""
    conn = connect_db(
        PROXYSQL_HOST, port=PROXYSQL_PORT,
        user=PROXYSQL_ADMIN_USER, password=PROXYSQL_ADMIN_PASS
    )
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM mysql_servers;")
        for hg, host in servers:
            cur.execute(
                "INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES (%s, %s, 3306, 1000);",
                (hg, host),
            )
        cur.execute("LOAD MYSQL SERVERS TO RUNTIME;")
        cur.execute("SAVE MYSQL SERVERS TO DISK;")
        cur.close()
    finally:
        conn.close()


def promote_slave1():
    print(">>> CẢNH BÁO: Master bị sập! Kích hoạt Auto-Failover...", flush=True)
    try:
        # 1. Thăng cấp Slave 1 làm Master mới
        conn1 = connect_db(SLAVE1_HOST)
        cur1 = conn1.cursor()
        cur1.execute("STOP REPLICA;")
        cur1.execute("RESET REPLICA ALL;")
        cur1.execute("SET GLOBAL super_read_only = 0;")
        cur1.execute("SET GLOBAL read_only = 0;")
        cur1.close()
        conn1.close()
        print(">>> [OK] mysql-slave1 đã thăng cấp thành MASTER MỚI.", flush=True)

        # 2. Chuyển Slave 2 đồng bộ từ Slave 1
        point_replica(SLAVE2_HOST, SLAVE1_HOST)
        print(">>> [OK] mysql-slave2 đã chuyển nguồn sang mysql-slave1.", flush=True)

        # 3. Cập nhật ProxySQL: Ghi (10) -> Slave 1, Đọc (20) -> Slave 2
        update_proxysql([(10, SLAVE1_HOST), (20, SLAVE2_HOST)])
        print(">>> [OK] ProxySQL đã chuyển Ghi -> mysql-slave1, Đọc -> mysql-slave2.", flush=True)
        return True
    except Exception as e:
        print(f">>> [LỖI FAILOVER] {e}", flush=True)
        return False


def failback_to_master():
    print(">>> PHÁT HIỆN: mysql-master đã sống lại! Bắt đầu Auto-Failback...", flush=True)
    try:
        # 1. Khóa ghi ngay trên Master cũ để chống split-brain
        conn_m = connect_db(MASTER_HOST)
        cur_m = conn_m.cursor()
        cur_m.execute("SET GLOBAL super_read_only = 1;")
        cur_m.execute("SET GLOBAL read_only = 1;")
        cur_m.close()
        conn_m.close()

        # 2. Kiểm tra errant transaction trên Master cũ
        gtid_m = get_gtid_executed(MASTER_HOST)
        gtid_s1 = get_gtid_executed(SLAVE1_HOST)
        errant = gtid_diff(SLAVE1_HOST, gtid_m, gtid_s1)
        if errant:
            print(f">>> [DỪNG FAILBACK] Master cũ có errant GTID ({errant}), cần xử lý thủ công!", flush=True)
            return False

        # 3. Cho Master cũ làm Slave tạm của Slave 1 để đồng bộ bù dữ liệu
        point_replica(MASTER_HOST, SLAVE1_HOST)
        print(">>> Đang đồng bộ bù dữ liệu từ mysql-slave1 về mysql-master...", flush=True)

        # Chờ Master cũ bắt kịp Slave 1 (tối đa 60 giây)
        for _ in range(60):
            missing = gtid_diff(MASTER_HOST, get_gtid_executed(SLAVE1_HOST), get_gtid_executed(MASTER_HOST))
            if not missing:
                break
            time.sleep(1)

        # 4. Khóa ghi tạm trên Slave 1 và chờ giao dịch cuối sang hết Master
        conn_s1 = connect_db(SLAVE1_HOST)
        cur_s1 = conn_s1.cursor()
        cur_s1.execute("SET GLOBAL super_read_only = 1;")
        cur_s1.execute("SET GLOBAL read_only = 1;")
        cur_s1.close()
        conn_s1.close()

        for _ in range(30):
            missing = gtid_diff(MASTER_HOST, get_gtid_executed(SLAVE1_HOST), get_gtid_executed(MASTER_HOST))
            if not missing:
                break
            time.sleep(0.5)

        # 5. Trả quyền Master chính cho mysql-master
        conn_m = connect_db(MASTER_HOST)
        cur_m = conn_m.cursor()
        cur_m.execute("STOP REPLICA;")
        cur_m.execute("RESET REPLICA ALL;")
        cur_m.execute("SET GLOBAL super_read_only = 0;")
        cur_m.execute("SET GLOBAL read_only = 0;")
        cur_m.close()
        conn_m.close()

        # 6. Đưa Slave 1 và Slave 2 quay lại làm Slave của mysql-master
        conn_s1 = connect_db(SLAVE1_HOST)
        cur_s1 = conn_s1.cursor()
        cur_s1.execute("SET GLOBAL super_read_only = 0;")
        cur_s1.execute("SET GLOBAL read_only = 1;")
        cur_s1.close()
        conn_s1.close()

        point_replica(SLAVE1_HOST, MASTER_HOST)
        point_replica(SLAVE2_HOST, MASTER_HOST)

        # 7. Khôi phục ProxySQL: Ghi (10) -> Master, Đọc (20) -> Slave 1 & Slave 2
        update_proxysql([(10, MASTER_HOST), (20, SLAVE1_HOST), (20, SLAVE2_HOST)])
        print(">>> [THÀNH CÔNG] Auto-Failback hoàn tất! Hệ thống đã về trạng thái 1 Master - 2 Slave.", flush=True)
        return True
    except Exception as e:
        print(f">>> [LỖI FAILBACK] {e}", flush=True)
        return False


if __name__ == "__main__":
    print(">>> Watchdog (Auto-Failover & Auto-Failback) đang khởi động (chờ 15 giây ổn định)...", flush=True)
    time.sleep(15)
    print(">>> [SẴN SÀNG] Watchdog đã khởi động xong! Đang giám sát mysql-master (mỗi 3 giây)...", flush=True)

    state = "NORMAL"  # NORMAL | FAILED_OVER
    fail_count = 0
    recover_count = 0

    while True:
        alive = check_master_alive()

        if state == "NORMAL":
            if alive:
                if fail_count > 0:
                    print(">>> Master đã kết nối lại bình thường.", flush=True)
                fail_count = 0
            else:
                fail_count += 1
                print(f">>> Master không phản hồi (Lần {fail_count}/3)...", flush=True)
                if fail_count >= 3:
                    if promote_slave1():
                        state = "FAILED_OVER"
                        fail_count = 0
                        recover_count = 0
                        print(">>> [TRẠNG THÁI: FAILED_OVER] Đang chờ mysql-master sống lại để Auto-Failback...", flush=True)

        elif state == "FAILED_OVER":
            if alive:
                recover_count += 1
                print(f">>> Master cũ phản hồi lại (Lần {recover_count}/3)...", flush=True)
                if recover_count >= 3:
                    if failback_to_master():
                        state = "NORMAL"
                        recover_count = 0
                        print(">>> [TRẠNG THÁI: NORMAL] Đang tiếp tục giám sát mysql-master...", flush=True)
                    else:
                        # Nếu có errant GTID thì dừng thử tự động để người vận hành kiểm tra
                        time.sleep(30)
            else:
                recover_count = 0

        time.sleep(3)