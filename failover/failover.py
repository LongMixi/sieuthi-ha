import time
import mysql.connector

MASTER_HOST = 'mysql-master'
SLAVE1_HOST = 'mysql-slave1'
SLAVE2_HOST = 'mysql-slave2'
DB_PASS = 'rootpassword'

def check_master_alive():
    try:
        conn = mysql.connector.connect(
            host=MASTER_HOST, user='root', password=DB_PASS, connection_timeout=2
        )
        conn.close()
        return True
    except Exception:
        return False

def promote_slave1():
    print(">>> CẢNH BÁO: Master bị sập! Bắt đầu kích hoạt Auto-Failover...", flush=True)
    try:
        # 1. Thăng cấp Slave 1 làm Master mới
        conn1 = mysql.connector.connect(host=SLAVE1_HOST, user='root', password=DB_PASS)
        cursor1 = conn1.cursor()
        cursor1.execute("STOP REPLICA;")
        cursor1.execute("SET GLOBAL read_only = 0;")
        conn1.close()
        print(">>> [THÀNH CÔNG] mysql-slave1 đã được thăng cấp thành MASTER MỚI!", flush=True)

        # 2. Điều hướng Slave 2 trỏ sang Slave 1
        conn2 = mysql.connector.connect(host=SLAVE2_HOST, user='root', password=DB_PASS)
        cursor2 = conn2.cursor()
        cursor2.execute("STOP REPLICA;")
        cursor2.execute("""
            CHANGE REPLICATION SOURCE TO
              SOURCE_HOST = 'mysql-slave1',
              SOURCE_PORT = 3306,
              SOURCE_USER = 'replica_user',
              SOURCE_PASSWORD = 'Replica@123',
              SOURCE_AUTO_POSITION = 1;
        """)
        cursor2.execute("START REPLICA;")
        conn2.close()
        print(">>> [THÀNH CÔNG] mysql-slave2 đã chuyển sang đồng bộ từ mysql-slave1!", flush=True)
    except Exception as e:
        print(f">>> LỖI FAILOVER: {e}", flush=True)

print(">>> Failover Watchdog đang chạy và giám sát hệ thống...", flush=True)
time.sleep(15) # Đợi các container khởi động ổn định

fail_count = 0
while True:
    if check_master_alive():
        fail_count = 0
    else:
        fail_count += 1
        print(f">>> Master không phản hồi (Lần {fail_count}/3)...", flush=True)
        if fail_count >= 3:
            promote_slave1()
            break # Sau khi failover xong thì dừng giám sát
    time.sleep(3)