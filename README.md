# Hệ thống MySQL High Availability (Replication & Auto-Failover) - `sieuthi-ha`

Dự án triển khai mô hình **MySQL 8.0 Replication** (1 Master - 2 Slaves) sử dụng **GTID**, tích hợp **ProxySQL** và **Failover Watchdog** (tự động chuyển đổi dự phòng khi Master gặp sự cố) trên Docker Compose cho cơ sở dữ liệu `ql_sieuthi`.

---

## 1. Tổng quan kiến trúc & Cấu trúc thư mục

```text
sieuthi-ha/
├── docker-compose.yml        # Định nghĩa 5 services (healthcheck + service_healthy) và mạng db-network
├── master/
│   ├── my.cnf                # Cấu hình MySQL Master (server-id=1, binlog ROW, GTID ON)
│   └── set_up.sql            # Tự động chạy qua initdb.d: tạo DB ql_sieuthi và user replica_user
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
| `mysql-master` | `mysql-master` | `3305 → 3306` | Node chính nhận ghi/đọc, tự động chạy `master/set_up.sql` khi khởi tạo |
| `mysql-slave1` | `mysql-slave1` | `3307 → 3306` | Node phụ 1 (`read_only = 1`), ứng viên thăng cấp Master khi failover |
| `mysql-slave2` | `mysql-slave2` | `3308 → 3306` | Node phụ 2 (`read_only = 1`), tự động trỏ sang `mysql-slave1` khi failover |
| `proxysql` | `proxysql` | `6033 → 6033`<br>`6032 → 6032` | Cổng `6033` cho ứng dụng/Workbench (tách Đọc/Ghi), cổng `6032` cho Admin |
| `watchdog` | `failover-watchdog` | - | Chạy `failover.py` giám sát `mysql-master` mỗi 3 giây (`restart: "no"`) |

> **Thông tin xác thực mặc định:**
> - Root password các node MySQL: `rootpassword`
> - Replication user: `replica_user` / `Replica@123`

---

## 2. Hướng dẫn cài đặt và khởi chạy Replica

### Yêu cầu trước khi cài đặt
- Đã cài đặt **Docker** và **Docker Compose**.

### Bước 1: Khởi động các container
Tại thư mục gốc `sieuthi-ha`, chạy lệnh:

```bash
docker compose up -d --build
```

Vì `docker-compose.yml` đã cấu hình `healthcheck` và `condition: service_healthy`, các service phụ (`mysql-slave1`, `mysql-slave2`, `proxysql`, `watchdog`) sẽ tự động đợi `mysql-master` khởi tạo xong mới chạy.

Kiểm tra trạng thái các container (đảm bảo các node MySQL đều `healthy`):

```bash
docker compose ps
```

> **Ghi chú:** Khi khởi tạo mới hoàn toàn, `mysql-master` đã tự động thực thi `master/set_up.sql` thông qua `/docker-entrypoint-initdb.d/`. Nếu bạn khởi động lại trên volume cũ mà chưa có `replica_user`, có thể chạy thủ công:
> ```bash
> docker exec -i mysql-master mysql -uroot -prootpassword < master/set_up.sql
> ```

### Bước 2: Kích hoạt Replication trên Slave 1 và Slave 2
Chạy lần lượt script thiết lập cho `mysql-slave1` và `mysql-slave2`:

```bash
docker exec -i mysql-slave1 mysql -uroot -prootpassword < slave1/set_up.sql
docker exec -i mysql-slave2 mysql -uroot -prootpassword < slave2/set_up.sql
```

Kiểm tra nhanh trạng thái cả 2 Slave:

```bash
docker exec mysql-slave1 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Replica_IO_Running|Replica_SQL_Running|Last_.*_Error"
docker exec mysql-slave2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Replica_IO_Running|Replica_SQL_Running|Last_.*_Error"
```

> **Kết quả đạt yêu cầu:** Cả 2 Slave đều hiển thị:
> - `Source_Host: mysql-master`
> - `Replica_IO_Running: Yes`
> - `Replica_SQL_Running: Yes`

### Bước 3: Kiểm thử đồng bộ dữ liệu (Replication)
1. Ghi dữ liệu mẫu trên `mysql-master` (cổng `3305`):
   ```bash
   docker exec -i mysql-master mysql -uroot -prootpassword -e "
   USE ql_sieuthi;
   CREATE TABLE IF NOT EXISTS test_sync (id INT PRIMARY KEY AUTO_INCREMENT, note VARCHAR(100));
   INSERT INTO test_sync (note) VALUES ('Du lieu tu Master');
   "
   ```
2. Kiểm tra trên `mysql-slave1` và `mysql-slave2` xem dữ liệu đã được đồng bộ sang chưa:
   ```bash
   docker exec -i mysql-slave1 mysql -uroot -prootpassword -e "SELECT * FROM ql_sieuthi.test_sync;"
   docker exec -i mysql-slave2 mysql -uroot -prootpassword -e "SELECT * FROM ql_sieuthi.test_sync;"
   ```

---

## 3. Cơ chế Auto-Failover & Kiểm thử

Dịch vụ `failover-watchdog` (`failover/failover.py`) hoạt động theo cơ chế:
1. Đợi 15 giây sau khi container khởi động ổn định.
2. Kiểm tra kết nối tới `mysql-master` mỗi **3 giây** (`connection_timeout=2`).
3. Nếu `mysql-master` không phản hồi **3 lần liên tiếp**:
   - Trên `mysql-slave1`: Chạy `STOP REPLICA;`, `RESET REPLICA ALL;`, `SET GLOBAL super_read_only = 0;`, `SET GLOBAL read_only = 0;` để thăng cấp thành Master mới.
   - Trên `mysql-slave2`: Chạy `STOP REPLICA;`, `RESET REPLICA ALL;`, trỏ `SOURCE_HOST = 'mysql-slave1'` (GTID + `GET_SOURCE_PUBLIC_KEY = 1`) và `START REPLICA;`.
   - Sau khi hoàn tất, watchdog thoát (`break`) và không tự restart nhờ cấu hình `restart: "no"`.

### Cách kiểm thử Failover
1. Mở terminal theo dõi log của Watchdog:
   ```bash
   docker logs -f failover-watchdog
   ```
2. Ở terminal khác, giả lập sự cố sập Master:
   ```bash
   docker stop mysql-master
   ```
3. Quan sát log `failover-watchdog` thông báo mất kết nối 3/3 lần, thăng cấp `mysql-slave1` và chuyển `mysql-slave2` sang đồng bộ từ `mysql-slave1`.
4. Kiểm tra lại trạng thái `mysql-slave2`:
   ```bash
   docker exec mysql-slave2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" | grep -E "Source_Host|Replica_IO_Running|Replica_SQL_Running"
   ```
   *(Kết quả cần hiển thị `Source_Host: mysql-slave1` và cả 2 dòng `Running: Yes`)*

---

## 4. Hoàn nguyên (Failback) sau khi kiểm thử Failover

Sau khi test sập Master, `mysql-master` đang dừng và `failover-watchdog` đã hoàn tất nhiệm vụ (trạng thái `Exited`).

### Cách 1: Hoàn nguyên giữ nguyên dữ liệu
1. Bật lại `mysql-master` và đợi sẵn sàng:
   ```bash
   docker start mysql-master
   docker exec mysql-master mysqladmin ping -h 127.0.0.1 -uroot -prootpassword
   ```
2. Đưa `mysql-slave1` về lại chế độ chỉ đọc và trỏ lại về `mysql-master`:
   ```bash
   docker exec -i mysql-slave1 mysql -uroot -prootpassword -e "SET GLOBAL read_only = 1;"
   docker exec -i mysql-slave1 mysql -uroot -prootpassword < slave1/set_up.sql
   ```
3. Trỏ `mysql-slave2` về lại `mysql-master`:
   ```bash
   docker exec -i mysql-slave2 mysql -uroot -prootpassword < slave2/set_up.sql
   ```
4. Khởi động lại Watchdog để tiếp tục giám sát:
   ```bash
   docker restart failover-watchdog
   ```

### Cách 2: Reset sạch toàn bộ hệ thống (nhanh nhất khi test lại từ đầu)
> **Lưu ý:** Tham số `-v` sẽ xóa toàn bộ volume/dữ liệu test cũ.
```bash
docker compose down -v
docker compose up -d --build
```
Sau đó chạy lại **Bước 2** để kích hoạt Replication cho 2 Slave.

---

## 5. Khắc phục lỗi thường gặp & Lưu ý vận hành

1. **Lỗi `Replica_IO_Running: Connecting` hoặc `No`**
   - **Nguyên nhân:** `mysql-master` chưa có `replica_user`, sai mật khẩu, hoặc thiếu `GET_SOURCE_PUBLIC_KEY = 1`.
   - **Cách sửa:** Xem chi tiết ở dòng `Last_IO_Error` khi chạy `SHOW REPLICA STATUS\G`, thử chạy lại `master/set_up.sql` rồi chạy lại `slave1/set_up.sql`, `slave2/set_up.sql`.

2. **Lỗi `ERROR 1290 (HY000): The MySQL server is running with the --read-only option`**
   - **Nguyên nhân:** Thực hiện lệnh ghi (`INSERT/UPDATE/CREATE`) trực tiếp vào Slave.
   - **Cách sửa:** Chỉ ghi dữ liệu vào `mysql-master` (cổng `3305`), hoặc vào `mysql-slave1` nếu đã failover lên làm Master.

3. **Lỗi lệch GTID sau nhiều lần test**
   - **Nguyên nhân:** Dữ liệu/GTID giữa các container bị lệch từ lần chạy trước.
   - **Cách sửa:** Chạy `docker compose down -v && docker compose up -d --build` để dựng lại từ đầu.

4. **Lưu ý về ProxySQL**
   - Container `proxysql` đã mở cổng `6032` (Admin) và `6033` (MySQL traffic), nhưng chưa gắn file cấu hình sẵn. Nếu sử dụng ProxySQL để tách Đọc/Ghi cho ứng dụng, bạn cần kết nối vào cổng `6032` để khai báo `mysql_servers`, `mysql_users` và `mysql_query_rules`.