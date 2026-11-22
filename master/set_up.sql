CREATE DATABASE IF NOT EXISTS ql_sieuthi;

CREATE USER IF NOT EXISTS 'replica_user'@'%' IDENTIFIED WITH mysql_native_password BY 'Replica@123';
GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'%';
FLUSH PRIVILEGES;