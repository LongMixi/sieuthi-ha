# Hệ thống MySQL High Availability (Replication & Auto-Failover) - `sieuthi-ha`

Dự án triển khai mô hình **MySQL 8.0 Replication** (1 Master - 2 Slaves) sử dụng **GTID**, tích hợp **ProxySQL** và **Failover Watchdog** (tự động chuyển đổi dự phòng khi Master gặp sự cố) trên Docker Compose cho cơ sở dữ liệu `ql_sieuthi`.

---

## 1. Tổng quan kiến trúc & Cấu trúc thư mục

```text
sieuthi-ha/
├── docker-compose.yml        # Định nghĩa 5 services và mạng bridge db-network
├── master/
│   ├── my.cnf                # Cấu hình MySQL Master (server-id=1, binlog ROW, GTID ON)
│   └── set_up.sql            # Tạo user replica_user cho quá trình đồng bộ
├── slave1/
│   ├── my.cnf                # Cấu hình MySQL Slave 1 (server-id=2, relay_log, read_only=1)
│   └── set_up.sql            # Trỏ replication source về mysql-master (GTID auto-position)
├── slave2/
│   ├── my.cnf                # Cấu hình MySQL Slave 2 (server-id=3, relay_log, read_only=1)
│   └── set_up.sql            # Trỏ replication source về mysql-master (GTID auto-position)
└── failover/
    ├── Dockerfile            # Build image Python 3.9-slim cho dịch vụ watchdog
    ├── requirements.txt      # Thư viện mysql-connector-python
    └── failover.py           # Script giám sát Master và tự động thăng cấp Slave 1
```

### Chi tiết các Service trong `docker-compose.yml`

| Service | Container Name | Port (Host → Container) | Vai trò |
| :--- | :--- | :--- | :--- |
| `mysql-master` | `mysql-master` | `3305 → 3306` | Node chính nhận ghi/đọc, khởi tạo sẵn database `ql_sieuthi` |
| `mysql-slave1` | `mysql-slave1` | `3307 → 3306` | Node phụ 1 (`read_only = 1`), ứng viên thăng cấp Master khi failover |
| `mysql-slave2` | `mysql-slave2` | `3308 → 3306` | Node phụ 2 (`read_only = 1`), tự động trỏ sang `mysql-slave1` khi failover |
| `proxysql` | `proxysql` | `6033 → 6033`<br>`6032 → 6032` | Cổng `6033` cho ứng dụng/Workbench (tách Đọc/Ghi), cổng `6032` cho Admin |
| `watchdog` | `failover-watchdog` | - | Chạy `failover.py` kiểm tra sức khỏe `mysql-master` mỗi 3 giây |

> **Thông tin xác thực mặc định:**
> - Root password của các node MySQL: `rootpassword`
> - Replication user: `replica_user` / `Replica@123` (sử dụng `mysql_native_password`)

---

## 2. Hướng dẫn cài đặt và khởi chạy Replica

### Yêu cầu trước khi cài đặt
- Đã cài đặt **Docker** và **Docker Compose**.

### Bước 1: Khởi động các container
Tại thư mục gốc `sieuthi-ha`, chạy lệnh:

```bash
docker compose up -d --build
```

Đợi khoảng 15–20 giây để các container MySQL khởi tạo hoàn tất. Bạn có thể kiểm tra trạng thái bằng:

```bash
docker compose ps
```

### Bước 2: Tạo Replication User trên Master
Vì `docker-compose.yml` chỉ mount file cấu hình `my.cnf` (chưa tự động chạy `set_up.sql`), hãy thực thi script trên `mysql-master`:

```bash
docker exec -i mysql-master mysql -uroot -prootpassword < master/set_up.sql
```

### Bước 3: Kích hoạt Replication trên Slave 1 và Slave 2
Chạy lần lượt script thiết lập cho `mysql-slave1` và `mysql-slave2`:

```bash
docker exec -i mysql-slave1 mysql -uroot -prootpassword < slave1/set_up.sql
docker exec -i mysql-slave2 mysql -uroot -prootpassword < slave2/set_up.sql
```

> **Kiểm tra trạng thái:** Kết quả lệnh `SHOW REPLICA STATUS\G` ở cuối mỗi file SQL cần hiển thị:
> - `Replica_IO_Running: Yes`
> - `Replica_SQL_Running: Yes`

### Bước 4: Kiểm thử đồng bộ dữ liệu (Replication)
1. Kết nối vào `mysql-master` (cổng `3305`) và tạo dữ liệu mẫu trong database `ql_sieuthi`:
   ```bash
   docker exec -it mysql-master mysql -uroot -prootpassword -e "
   USE ql_sieuthi;
   CREATE TABLE IF NOT EXISTS test_sync (id INT PRIMARY KEY AUTO_INCREMENT, note VARCHAR(100));
   INSERT INTO test_sync (note) VALUES ('Du lieu tu Master');
   "
   ```
2. Kiểm tra trên `mysql-slave1` và `mysql-slave2` xem dữ liệu đã được đồng bộ chưa:
   ```bash
   docker exec -it mysql-slave1 mysql -uroot -prootpassword -e "SELECT * FROM ql_sieuthi.test_sync;"
   docker exec -it mysql-slave2 mysql -uroot -prootpassword -e "SELECT * FROM ql_sieuthi.test_sync;"
   ```

---

## 3. Cơ chế Auto-Failover & Kiểm thử

Dịch vụ `failover-watchdog` (`failover/failover.py`) hoạt động theo cơ chế:
1. Chờ 15 giây sau khi khởi động để các container ổn định.
2. Ping kết nối tới `mysql-master` mỗi **3 giây** (timeout 2 giây).
3. Nếu `mysql-master` không phản hồi **3 lần liên tiếp**:
   - Thực thi `STOP REPLICA;` và `SET GLOBAL read_only = 0;` trên `mysql-slave1` để thăng cấp làm Master mới.
   - Thực thi `STOP REPLICA;`, `CHANGE REPLICATION SOURCE TO SOURCE_HOST = 'mysql-slave1' ...` và `START REPLICA;` trên `mysql-slave2` để đồng bộ từ Master mới.

### Cách kiểm thử Failover
1. Mở terminal theo dõi log của Watchdog:
   ```bash
   docker logs -f failover-watchdog
   ```
2. Giả lập sự cố sập Master:
   ```bash
   docker stop mysql-master
   ```
3. Quan sát log `failover-watchdog` thông báo mất kết nối 3/3 lần và tự động thăng cấp `mysql-slave1`, đồng thời điều hướng `mysql-slave2`.

---

## 4. Lưu ý vận hành
- **Watchdog chạy 1 lần:** Trong `failover/failover.py`, sau khi hoàn tất failover, vòng lặp sẽ `break` và kết thúc quá trình giám sát.
- **Cấu hình ProxySQL:** Container `proxysql` đã được mở cổng `6032` (Admin) và `6033` (MySQL traffic), nhưng chưa gắn file cấu hình sẵn. Nếu sử dụng ProxySQL để tách Đọc/Ghi cho ứng dụng, bạn cần kết nối vào cổng Admin `6032` để khai báo `mysql_servers`, `mysql_users` và `mysql_query_rules`.
- **Dọn dẹp hệ thống:** Để dừng và xóa các container:
  ```bash
  docker compose down
  ```
