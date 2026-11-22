import time
import mysql.connector

MASTER_HOST = 'mysql-master'
SLAVE1_HOST = 'mysql-slave1'
SLAVE2_HOST = 'mysql-slave2'
DB_PASS = 'rootpassword'


def check_master_alive():
    conn = None
    try:
        conn = mysql.connector.connect(
            host=MASTER_HOST,
            user='root',
            password=DB_PASS,
            connection_timeout=2,
        )
        return conn.is_connected()
    except Exception:
        return False
    finally:
        if conn and conn.is_connected():
            conn.close()


def promote_slave1():
    print(">>> CẢNH BÁO: Master bị sập! Bắt đầu kích hoạt Auto-Failover...", flush=True)

    # 1. Thăng cấp Slave 1 làm Master mới
    conn1 = None
    cursor1 = None
    try:
        conn1 = mysql.connector.connect(
            host=SLAVE1_HOST, user='root', password=DB_PASS, connection_timeout=5
        )
        cursor1 = conn1.cursor()
        cursor1.execute("STOP REPLICA;")
        cursor1.execute("RESET REPLICA ALL;")
        cursor1.execute("SET GLOBAL super_read_only = 0;")
        cursor1.execute("SET GLOBAL read_only = 0;")
        print(">>> [THÀNH CÔNG] mysql-slave1 đã được thăng cấp thành MASTER MỚI!", flush=True)
    except Exception as e:
        print(f">>> [LỖI] Không thể thăng cấp mysql-slave1: {e}", flush=True)
        return
    finally:
        if cursor1:
            cursor1.close()
        if conn1 and conn1.is_connected():
            conn1.close()

    # 2. Điều hướng Slave 2 trỏ sang Slave 1
    conn2 = None
    cursor2 = None
    try:
        conn2 = mysql.connector.connect(
            host=SLAVE2_HOST, user='root', password=DB_PASS, connection_timeout=5
        )
        cursor2 = conn2.cursor()
        cursor2.execute("STOP REPLICA;")
        cursor2.execute("RESET REPLICA ALL;")
        cursor2.execute("""
            CHANGE REPLICATION SOURCE TO
              SOURCE_HOST = 'mysql-slave1',
              SOURCE_PORT = 3306,
              SOURCE_USER = 'replica_user',
              SOURCE_PASSWORD = 'Replica@123',
              SOURCE_AUTO_POSITION = 1,
              GET_SOURCE_PUBLIC_KEY = 1;
        """)
        cursor2.execute("START REPLICA;")
        print(">>> [THÀNH CÔNG] mysql-slave2 đã chuyển sang đồng bộ từ mysql-slave1!", flush=True)
    except Exception as e:
        print(f">>> [LỖI] Không thể điều hướng mysql-slave2: {e}", flush=True)
    finally:
        if cursor2:
            cursor2.close()
        if conn2 and conn2.is_connected():
            conn2.close()


if __name__ == "__main__":
    print(">>> Failover Watchdog đang chạy và giám sát hệ thống...", flush=True)
    time.sleep(15)  # Đợi các container khởi động ổn định

    fail_count = 0
    while True:
        if check_master_alive():
            if fail_count > 0:
                print(">>> Master đã kết nối lại bình thường.", flush=True)
            fail_count = 0
        else:
            fail_count += 1
            print(f">>> Master không phản hồi (Lần {fail_count}/3)...", flush=True)
            if fail_count >= 3:
                promote_slave1()
                print(">>> Hoàn tất Auto-Failover. Watchdog kết thúc giám sát.", flush=True)
                break
        time.sleep(3)