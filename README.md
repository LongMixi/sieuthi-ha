# Hệ thống MySQL High Availability (Replication, ProxySQL & Auto-Failover/Failback) - `sieuthi-ha`

Dự án triển khai mô hình **MySQL 8.0 Semi-Sync Replication** (1 Master - 2 Slaves) sử dụng **GTID**, tích hợp **ProxySQL** (tách Đọc/Ghi và cân bằng tải) và **Failover Watchdog** (tự động chuyển đổi dự phòng khi Master sập và tự động hoàn nguyên khi Master sống lại) trên Docker Compose cho cơ sở dữ liệu quản lý bán hàng siêu thị `ql_sieuthi`.

---

## 1. Tổng quan kiến trúc & Cấu trúc thư mục

```text
sieuthi-ha/
├── docker-compose.yml        # Định nghĩa 5 services (healthcheck + service_healthy) và mạng db-network
├── master/
│   ├── my.cnf                # Cấu hình MySQL Master (server-id=1, binlog ROW, GTID ON)
│   └── set_up.sql            # Tự chạy qua initdb.d: tạo DB ql_sieuthi, replica_user, monitor và đổi chuẩn mật khẩu root
├── slave1/
│   ├── my.cnf                # Cấu hình MySQL Slave 1 (server-id=2, relay_log, read_only=1)
│   └── set_up.sql            # Trỏ replication source về mysql-master (GTID auto-position)
├── slave2/
│   ├── my.cnf                # Cấu hình MySQL Slave 2 (server-id=3, relay_log, read_only=1)
│   └── set_up.sql            # Trỏ replication source về mysql-master (GTID auto-position)
├── failover/
│   ├── Dockerfile            # Build image Python 3.9-slim cho dịch vụ watchdog
│   ├── requirements.txt      # Thư viện mysql-connector-python
│   └── failover.py           # Giám sát Master, Auto-Failover, Auto-Failback và tự cập nhật ProxySQL
└── data/
    ├── data_set.sql          # Script tạo 10 bảng chuẩn hóa + 101.140 dòng dữ liệu siêu thị
    └── dataset_diagram.jpg   # Sơ đồ EER của CSDL ql_sieuthi
```

### Chi tiết các Service trong `docker-compose.yml`

| Service | Container Name | Port (Host → Container) | Vai trò |
| :--- | :--- | :--- | :--- |
| `mysql-master` | `mysql-master` | `3305 → 3306` | Node chính nhận ghi, tự chạy `master/set_up.sql` khi khởi tạo |
| `mysql-slave1` | `mysql-slave1` | `3307 → 3306` | Node phụ 1 (`read_only = 1`), ứng viên thăng cấp Master khi failover |
| `mysql-slave2` | `mysql-slave2` | `3308 → 3306` | Node phụ 2 (`read_only = 1`), tự chuyển nguồn sang `mysql-slave1` khi failover |
| `proxysql` | `proxysql` | `6033 → 6033`<br>`6032 → 6032` | Cổng `6033` cho ứng dụng/Workbench (tách Đọc/Ghi), cổng `6032` cho Admin |
| `watchdog` | `failover-watchdog` | - | Chạy `failover.py` giám sát liên tục mỗi 3 giây (`restart: "always"`) |

> **Thông tin xác thực mặc định:**
> - MySQL root: `root` / `rootpassword` (`mysql_native_password`)
> - Replication user: `replica_user` / `Replica@123`
> - ProxySQL monitor user: `monitor` / `monitor`
> - ProxySQL Admin (cổng `6032`): `admin` / `admin`

---

## 2. Hướng dẫn cài đặt từ đầu

### Yêu cầu
- Đã cài đặt **Docker** và **Docker Compose**.

### Bước 1: Khởi động các container
Tại thư mục gốc `sieuthi-ha` (nếu muốn reset sạch dữ liệu cũ, chạy `docker compose down -v` trước):

```bash
docker compose up -d --build
docker compose ps
```

Đợi đến khi cả 3 node MySQL (`mysql-master`, `mysql-slave1`, `mysql-slave2`) đều ở trạng thái `(healthy)`.

> **Ghi chú:** Khi khởi tạo volume mới, `mysql-master` tự chạy `master/set_up.sql` qua `/docker-entrypoint-initdb.d/`. Nếu chạy trên volume cũ, bạn có thể nạp thủ công:
> ```bash
> docker exec -i mysql-master mysql -uroot -prootpassword < master/set_up.sql
> ```

### Bước 2: Kích hoạt Replication trên Slave 1 và Slave 2

```bash
docker exec -i mysql-slave1 mysql -uroot -prootpassword < slave1/set_up.sql
docker exec -i mysql-slave2 mysql -uroot -prootpassword < slave2/set_up.sql
```

Kiểm tra trạng thái đồng bộ của cả 2 Slave:

```bash
for s in mysql-slave1 mysql-slave2; do
  echo "== $s =="
  docker exec $s mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_.*_Error"
done
```

> **Đạt yêu cầu:** Cả 2 Slave hiển thị `Source_Host: mysql-master`, `Replica_IO_Running: Yes`, `Replica_SQL_Running: Yes` và `Seconds_Behind_Source: 0`.

Kiểm tra **Semi-Sync Replication** đã hoạt động trên Master (plugin `semisync_source.so` và `semisync_replica.so` đã được nạp sẵn trong `my.cnf` của cả 3 node để giữ cấu hình sau khi restart và duy trì Semi-Sync cả khi Failover/Failback):

```bash
docker exec mysql-master mysql -uroot -prootpassword -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_%';"
```

> **Đạt yêu cầu:** `Rpl_semi_sync_source_status = ON` và `Rpl_semi_sync_source_clients = 2`.

### Bước 3: Nạp CSDL `ql_sieuthi` (10 bảng, 101.140 dòng)

```bash
time docker exec -i mysql-master mysql -uroot -prootpassword --default-character-set=utf8mb4 < data/data_set.sql
```

Kiểm tra nhanh dữ liệu đã đồng bộ sang Slave 2:

```bash
docker exec mysql-slave2 mysql -uroot -prootpassword -D ql_sieuthi -e "SELECT COUNT(*) AS TongHoaDon FROM HoaDon;"
```

### Bước 4: Cấu hình ProxySQL (Tách Đọc/Ghi & Cân bằng tải)

Nạp cấu hình vào cổng quản trị `6032` của ProxySQL (`hostgroup 10` nhận ghi trên Master, `hostgroup 20` nhận đọc chia tải sang 2 Slave):

```bash
docker exec -i proxysql mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "
SET mysql-monitor_username='monitor';
SET mysql-monitor_password='monitor';
LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;

DELETE FROM mysql_replication_hostgroups;

DELETE FROM mysql_servers;
INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES
(10, 'mysql-master', 3306, 1000),
(20, 'mysql-slave1', 3306, 1000),
(20, 'mysql-slave2', 3306, 1000);
LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;

INSERT OR REPLACE INTO mysql_users (username, password, default_hostgroup, active)
VALUES ('root', 'rootpassword', 10, 1);
LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;

DELETE FROM mysql_query_rules;
INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
(1, 1, '^SELECT.*FOR UPDATE', 10, 1),
(2, 1, '^SELECT', 20, 1);
LOAD MYSQL QUERY RULES TO RUNTIME; SAVE MYSQL QUERY RULES TO DISK;
"
```

*(Không khai báo `mysql_replication_hostgroups` để tránh xung đột với `failover.py`, vì `failover.py` trực tiếp cập nhật bảng `mysql_servers` khi failover/failback).*

Kiểm tra trạng thái ProxySQL:

```bash
docker exec proxysql mysql -uadmin -padmin -h 127.0.0.1 -P 6032 -e "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;"
docker exec proxysql mysql -uroot -prootpassword -h 127.0.0.1 -P 6033 -e "SELECT @@server_id, @@hostname;"
```

---

## 3. Cơ chế Auto-Failover & Auto-Failback

Dịch vụ `failover-watchdog` (`failover/failover.py`) chạy liên tục với hai trạng thái `NORMAL` và `FAILED_OVER`:

### Khi Master gặp sự cố (Auto-Failover)
1. Kiểm tra kết nối `mysql-master` mỗi **3 giây** (`connection_timeout=2`).
2. Nếu không phản hồi **3 lần liên tiếp**:
   - Thăng cấp `mysql-slave1` làm Master mới (`STOP REPLICA`, `RESET REPLICA ALL`, `super_read_only = 0`, `read_only = 0`).
   - Điều hướng `mysql-slave2` đồng bộ từ `mysql-slave1` bằng GTID (`SOURCE_AUTO_POSITION = 1`).
   - Cập nhật ProxySQL: chuyển `hostgroup 10` (Ghi) sang `mysql-slave1`, giữ `hostgroup 20` (Đọc) ở `mysql-slave2`.
   - Chuyển sang trạng thái `FAILED_OVER`.

### Khi Master cũ sống lại (Auto-Failback)
1. Ở trạng thái `FAILED_OVER`, khi `mysql-master` phản hồi lại **3 lần liên tiếp**:
   - Khóa ghi ngay trên `mysql-master` (`super_read_only = 1`, `read_only = 1`) để tránh split-brain.
   - Kiểm tra errant transaction bằng `GTID_SUBTRACT(gtid_master, gtid_slave1)`. Nếu có errant GTID thì dừng failback tự động và in cảnh báo để xử lý thủ công.
   - Đưa `mysql-master` làm Slave tạm của `mysql-slave1` cho đến khi đồng bộ bù xong 100% giao dịch mới.
   - Khóa ghi tạm trên `mysql-slave1`, đợi giao dịch cuối sang hết `mysql-master`, rồi trả quyền Master cho `mysql-master`.
   - Trỏ cả `mysql-slave1` và `mysql-slave2` quay lại đồng bộ từ `mysql-master`.
   - Khôi phục ProxySQL về 1 Master (`10`) và 2 Slave (`20`), quay về trạng thái `NORMAL`.

### Cách kiểm thử nhanh
1. Mở terminal theo dõi log Watchdog:
   ```bash
   docker logs -f failover-watchdog
   ```
2. Giả lập sập Master:
   ```bash
   docker stop mysql-master
   ```
   Quan sát Watchdog thăng cấp `mysql-slave1`, chuyển `mysql-slave2` và cập nhật ProxySQL (Ghi → `mysql-slave1`, Đọc → `mysql-slave2`).
3. Bật lại Master để test Auto-Failback:
   ```bash
   docker start mysql-master
   ```
   Quan sát Watchdog khóa ghi `mysql-master`, đồng bộ bù dữ liệu từ `mysql-slave1`, trả lại mô hình 1 Master - 2 Slave và khôi phục ProxySQL.

---

## 4. Reset sạch toàn bộ hệ thống

Khi muốn xóa toàn bộ volume/dữ liệu test cũ để dựng lại từ đầu:

```bash
docker compose down -v
docker compose up -d --build
```
Sau đó thực hiện lại từ **Bước 2** ở Mục 2.

---

## 5. Khắc phục lỗi thường gặp

1. **Lỗi `Replica_IO_Running: Connecting` hoặc `Access denied for user 'replica_user'`**
   - Kiểm tra `Last_IO_Error` trong `SHOW REPLICA STATUS\G`. Chạy lại `master/set_up.sql`, rồi chạy lại `slave1/set_up.sql` và `slave2/set_up.sql`.
2. **Lỗi `ERROR 1290 (HY000): The MySQL server is running with the --read-only option`**
   - Do ghi trực tiếp vào Slave. Hãy ghi qua **ProxySQL (cổng `6033`)** hoặc vào node đang làm Master.
3. **Lỗi `Access denied` hoặc `Max connect timeout` khi kết nối ProxySQL (cổng `6033`)**
   - Chưa chạy **Bước 4** (cấu hình ProxySQL) hoặc `master/set_up.sql` chưa tạo user `monitor` và đổi mật khẩu `root` sang `mysql_native_password`.
4. **Lỗi lệch GTID sau nhiều lần test**
   - Chạy `docker compose down -v && docker compose up -d --build` để làm sạch volume và dựng lại.
