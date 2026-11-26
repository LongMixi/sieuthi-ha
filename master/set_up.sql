CREATE DATABASE IF NOT EXISTS ql_sieuthi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 1. Tài khoản dùng cho MySQL Replication (Slave 1, Slave 2 và Failback)
CREATE USER IF NOT EXISTS 'replica_user'@'%' IDENTIFIED WITH mysql_native_password BY 'Replica@123';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replica_user'@'%';

-- 2. Tài khoản dùng cho ProxySQL giám sát trạng thái các node MySQL
CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitor';
GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';

-- 3. Đổi chuẩn xác thực mật khẩu của root để ProxySQL kết nối thông suốt
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'rootpassword';

FLUSH PRIVILEGES;