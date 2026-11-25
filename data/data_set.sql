-- =========================================================================
-- CƠ SỞ DỮ LIỆU: QUẢN LÝ BÁN HÀNG SIÊU THỊ (ql_sieuthi)
-- Gồm: 10 bảng chuẩn hóa + 101.140 dòng dữ liệu thật (tên thật, hàng thật)
-- Tương thích: MySQL 5.7, MySQL 8.0 (GTID / Replication / ProxySQL), MariaDB
-- =========================================================================

DROP DATABASE IF EXISTS ql_sieuthi;
CREATE DATABASE ql_sieuthi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ql_sieuthi;

SET SQL_SAFE_UPDATES = 0;

-- =========================================================================
-- PHẦN 1: TẠO CẤU TRÚC 10 BẢNG
-- =========================================================================

-- 1. Loại sản phẩm
CREATE TABLE LoaiSanPham (
    MaLoai INT AUTO_INCREMENT PRIMARY KEY,
    TenLoai VARCHAR(100) NOT NULL,
    KhuVucKeHang VARCHAR(50)
) ENGINE=InnoDB;

-- 2. Nhà cung cấp
CREATE TABLE NhaCungCap (
    MaNCC INT AUTO_INCREMENT PRIMARY KEY,
    TenNCC VARCHAR(150) NOT NULL,
    MaSoThue VARCHAR(20) UNIQUE,
    DienThoai VARCHAR(20),
    DiaChi VARCHAR(255)
) ENGINE=InnoDB;

-- 3. Sản phẩm
CREATE TABLE SanPham (
    MaSP INT AUTO_INCREMENT PRIMARY KEY,
    MaVach VARCHAR(20) UNIQUE NOT NULL,
    TenSP VARCHAR(150) NOT NULL,
    MaLoai INT NOT NULL,
    MaNCC INT NOT NULL,
    DonViTinh VARCHAR(30) DEFAULT 'Cái',
    GiaNhap DECIMAL(12,2) NOT NULL,
    GiaBan DECIMAL(12,2) NOT NULL,
    SoLuongTon INT NOT NULL DEFAULT 0,
    HanSuDungMacDinh INT,
    TrangThai ENUM('DangKinhDoanh', 'NgungKinhDoanh') DEFAULT 'DangKinhDoanh',
    CONSTRAINT fk_sp_loai FOREIGN KEY (MaLoai) REFERENCES LoaiSanPham(MaLoai),
    CONSTRAINT fk_sp_ncc FOREIGN KEY (MaNCC) REFERENCES NhaCungCap(MaNCC)
) ENGINE=InnoDB;

-- 4. Nhân viên
CREATE TABLE NhanVien (
    MaNV INT AUTO_INCREMENT PRIMARY KEY,
    HoTen VARCHAR(100) NOT NULL,
    DienThoai VARCHAR(15) UNIQUE,
    ChucVu ENUM('Thu ngân', 'Thủ kho', 'Quản lý siêu thị') DEFAULT 'Thu ngân',
    QuayLamViec VARCHAR(30)
) ENGINE=InnoDB;

-- 5. Khách hàng thành viên
CREATE TABLE KhachHang (
    MaKH INT AUTO_INCREMENT PRIMARY KEY,
    HoTen VARCHAR(100) NOT NULL,
    SoDienThoai VARCHAR(15) UNIQUE NOT NULL,
    DiemTichLuy INT DEFAULT 0,
    HangThanhVien ENUM('Đồng', 'Bạc', 'Vàng', 'Kim Cương') DEFAULT 'Đồng',
    NgayDangKy DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 6. Chương trình khuyến mãi
CREATE TABLE ChuongTrinhKhuyenMai (
    MaKM INT AUTO_INCREMENT PRIMARY KEY,
    MaCode VARCHAR(30) UNIQUE NOT NULL,
    TenChuongTrinh VARCHAR(150) NOT NULL,
    PhanTramGiam DECIMAL(5,2) DEFAULT 0,
    NgayBatDau DATE NOT NULL,
    NgayKetThuc DATE NOT NULL,
    TrangThai ENUM('DangApDung', 'HetHan') DEFAULT 'DangApDung'
) ENGINE=InnoDB;

-- 7. Phiếu nhập kho
CREATE TABLE PhieuNhapKho (
    MaPN INT AUTO_INCREMENT PRIMARY KEY,
    NgayNhap DATETIME DEFAULT CURRENT_TIMESTAMP,
    MaNCC INT NOT NULL,
    MaNV INT NOT NULL,
    TongTienNhap DECIMAL(15,2) DEFAULT 0,
    GhiChu VARCHAR(255),
    CONSTRAINT fk_pn_ncc FOREIGN KEY (MaNCC) REFERENCES NhaCungCap(MaNCC),
    CONSTRAINT fk_pn_nv FOREIGN KEY (MaNV) REFERENCES NhanVien(MaNV)
) ENGINE=InnoDB;

-- 8. Chi tiết phiếu nhập kho
CREATE TABLE ChiTietPhieuNhap (
    MaPN INT NOT NULL,
    MaSP INT NOT NULL,
    SoLuongNhap INT NOT NULL,
    DonGiaNhap DECIMAL(12,2) NOT NULL,
    ThanhTienNhap DECIMAL(15,2) GENERATED ALWAYS AS (SoLuongNhap * DonGiaNhap) STORED,
    PRIMARY KEY (MaPN, MaSP),
    CONSTRAINT fk_ctpn_pn FOREIGN KEY (MaPN) REFERENCES PhieuNhapKho(MaPN) ON DELETE CASCADE,
    CONSTRAINT fk_ctpn_sp FOREIGN KEY (MaSP) REFERENCES SanPham(MaSP)
) ENGINE=InnoDB;

-- 9. Hóa đơn
CREATE TABLE HoaDon (
    MaHD INT AUTO_INCREMENT PRIMARY KEY,
    NgayLap DATETIME DEFAULT CURRENT_TIMESTAMP,
    CaLamViec ENUM('Ca sáng', 'Ca chiều', 'Ca tối') DEFAULT 'Ca sáng',
    MaNV INT NOT NULL,
    MaKH INT NULL,
    MaKM INT NULL,
    PhuongThucTT ENUM('Tiền mặt', 'Chuyển khoản QR', 'Thẻ ngân hàng') DEFAULT 'Tiền mặt',
    TongTien DECIMAL(15,2) DEFAULT 0,
    CONSTRAINT fk_hd_nv FOREIGN KEY (MaNV) REFERENCES NhanVien(MaNV),
    CONSTRAINT fk_hd_kh FOREIGN KEY (MaKH) REFERENCES KhachHang(MaKH),
    CONSTRAINT fk_hd_km FOREIGN KEY (MaKM) REFERENCES ChuongTrinhKhuyenMai(MaKM)
) ENGINE=InnoDB;

-- 10. Chi tiết hóa đơn
CREATE TABLE ChiTietHoaDon (
    MaHD INT NOT NULL,
    MaSP INT NOT NULL,
    SoLuong INT NOT NULL,
    DonGiaBan DECIMAL(12,2) NOT NULL,
    GiamGia DECIMAL(12,2) DEFAULT 0,
    ThanhTien DECIMAL(15,2) GENERATED ALWAYS AS ((SoLuong * DonGiaBan) - GiamGia) STORED,
    PRIMARY KEY (MaHD, MaSP),
    CONSTRAINT fk_cthd_hd FOREIGN KEY (MaHD) REFERENCES HoaDon(MaHD) ON DELETE CASCADE,
    CONSTRAINT fk_cthd_sp FOREIGN KEY (MaSP) REFERENCES SanPham(MaSP)
) ENGINE=InnoDB;

-- =========================================================================
-- PHẦN 2: SINH 101.140 DÒNG DỮ LIỆU THẬT (TÊN THẬT, HÀNG THẬT)
-- =========================================================================

-- Bảng số tạm (0..99,999)
DROP TABLE IF EXISTS tmp_seq;
CREATE TABLE tmp_seq (n INT PRIMARY KEY) ENGINE=InnoDB;

INSERT INTO tmp_seq (n)
SELECT d1.n + d2.n*10 + d3.n*100 + d4.n*1000 + d5.n*10000
FROM (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1
CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d4
CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d5;

-- 1. 20 Ngành hàng siêu thị
INSERT INTO LoaiSanPham (TenLoai, KhuVucKeHang) VALUES
('Sữa & Chế phẩm từ sữa', 'Kệ A1'),
('Nước giải khát & Nước ngọt', 'Kệ A2'),
('Bia & Đồ uống có cồn', 'Kệ A3'),
('Trà & Cà phê', 'Kệ A4'),
('Mì, Phở & Thực phẩm khô', 'Kệ B1'),
('Gạo, Bột & Ngũ cốc', 'Kệ B2'),
('Dầu ăn, Nước mắm & Gia vị', 'Kệ B3'),
('Bánh kẹo & Snack', 'Kệ B4'),
('Đồ hộp & Thực phẩm chế biến', 'Kệ C1'),
('Thịt tươi & Thủy hải sản', 'Kệ Tủ Mát C2'),
('Rau củ & Trái cây tươi', 'Kệ Tủ Mát C3'),
('Kem & Thực phẩm đông lạnh', 'Kệ Tủ Đông C4'),
('Bột giặt & Nước xả vải', 'Kệ D1'),
('Nước rửa chén & Vệ sinh nhà cửa', 'Kệ D2'),
('Dầu gội, Sữa tắm & Chăm sóc cá nhân', 'Kệ D3'),
('Mỹ phẩm & Chăm sóc da', 'Kệ D4'),
('Tã bỉm & Sản phẩm Mẹ và Bé', 'Kệ E1'),
('Đồ dùng nhà bếp & Gia dụng', 'Kệ E2'),
('Văn phòng phẩm & Đồ dùng học tập', 'Kệ E3'),
('Thức ăn thú cưng & Khác', 'Kệ E4');

-- 2. 50 Nhà cung cấp thật
INSERT INTO NhaCungCap (TenNCC, MaSoThue, DienThoai, DiaChi) VALUES
('Công ty CP Sữa Việt Nam (Vinamilk)', '0300588569', '02854155555', 'Quận 7, TP.HCM'),
('Công ty CP Thực phẩm Sữa TH (TH True Milk)', '2901270911', '02437959999', 'Nghĩa Đàn, Nghệ An'),
('Công ty TNHH FrieslandCampina Việt Nam (Cô Gái Hà Lan)', '3700232735', '02838231100', 'Thuận An, Bình Dương'),
('Công ty TNHH Nước Giải Khát Suntory PepsiCo VN', '0300816663', '02838219437', 'Quận 1, TP.HCM'),
('Công ty TNHH Nước Giải Khát Coca-Cola Việt Nam', '0300816744', '02838961000', 'TP. Thủ Đức, TP.HCM'),
('Công ty TNHH Thương Mại Dịch Vụ Tân Hiệp Phát', '3700586237', '02743755161', 'Thuận An, Bình Dương'),
('Tổng Công ty CP Bia - Rượu - NGK Sài Gòn (Sabeco)', '0300583659', '02838294081', 'Quận 1, TP.HCM'),
('Công ty TNHH Nhà máy Bia Heineken Việt Nam', '0300831132', '02838222755', 'Quận 1, TP.HCM'),
('Công ty CP Tập đoàn Trung Nguyên Legend', '0303305941', '02839251845', 'Quận 3, TP.HCM'),
('Công ty TNHH Nestlé Việt Nam', '3600235305', '02839113737', 'Biên Hòa, Đồng Nai'),
('Công ty CP Acecook Việt Nam', '0300808687', '02838154064', 'Tân Phú, TP.HCM'),
('Công ty CP Hàng Tiêu Dùng Masan (Masan Consumer)', '0302017440', '02862555660', 'Quận 1, TP.HCM'),
('Công ty CP Thực phẩm Á Châu (Asia Foods)', '3700368899', '02743741234', 'Dĩ An, Bình Dương'),
('Công ty CP Tập đoàn Lộc Trời (Gạo Hạt Ngọc Trời)', '1600192619', '02963856188', 'Long Xuyên, An Giang'),
('Công ty TNHH Thực phẩm Quaker & Ngũ cốc Việt', '0311223344', '02838112233', 'Quận 7, TP.HCM'),
('Công ty CP Dầu Thực Vật Tường An', '0303498754', '02838153972', 'Tân Bình, TP.HCM'),
('Công ty TNHH Dầu thực vật Cái Lân (Calofic - Simply)', '5700101641', '02839100999', 'Quận 1, TP.HCM'),
('Công ty Ajinomoto Việt Nam', '3600242473', '02839308784', 'Quận 3, TP.HCM'),
('Công ty CP Mondelez Kinh Đô Việt Nam', '0313283651', '02838270838', 'TP. Thủ Đức, TP.HCM'),
('Công ty TNHH Thực phẩm Orion Vina', '3700682510', '02835123420', 'Bến Cát, Bình Dương'),
('Công ty CP Bánh kẹo Bibica', '3600363970', '02839717920', 'Tân Bình, TP.HCM'),
('Công ty TNHH Liwayway Việt Nam (Snack Oishi)', '3700229231', '02743743118', 'VSIP 1, Bình Dương'),
('Công ty CP Việt Nam Kỹ Nghệ Súc Sản (Vissan)', '0300105356', '02835533999', 'Bình Thạnh, TP.HCM'),
('Công ty CP Chăn Nuôi C.P. Việt Nam', '3600224423', '02513836251', 'Biên Hòa, Đồng Nai'),
('Công ty CP Ba Huân', '0304825120', '02838909100', 'Bình Chánh, TP.HCM'),
('Công ty TNHH Nông Sản Đà Lạt GAP', '5800456789', '02633822111', 'Đà Lạt, Lâm Đồng'),
('Công ty CP Rau Quả Tiền Giang (Vegetigi)', '1200100234', '02733855444', 'Châu Thành, Tiền Giang'),
('Công ty CP Thực Phẩm Đông Lạnh Kido (Kido Foods)', '0302705302', '02838270468', 'Củ Chi, TP.HCM'),
('Công ty TNHH Quốc Tế Unilever Việt Nam', '0300762150', '02854135686', 'Củ Chi, TP.HCM'),
('Công ty TNHH Procter & Gamble Việt Nam (P&G)', '3700232100', '02838221122', 'Bến Cát, Bình Dương'),
('Công ty CP Bột Giặt LIX', '0301444263', '02838966803', 'TP. Thủ Đức, TP.HCM'),
('Công ty CP Hàng Gia Dụng Quốc Tế (ICP - X-Men)', '0302422111', '02837505555', 'Bình Chánh, TP.HCM'),
('Công ty TNHH Beiersdorf Việt Nam (Nivea)', '0304112233', '02838234567', 'Quận 1, TP.HCM'),
('Công ty TNHH L''Oréal Việt Nam', '0305123456', '02839106789', 'Quận 1, TP.HCM'),
('Công ty TNHH Diana Unicharm', '0100507058', '02436445758', 'Hoàng Mai, Hà Nội'),
('Công ty TNHH Kimberly-Clark Việt Nam (Huggies/Kotex)', '3700223344', '02743740111', 'Thuận An, Bình Dương'),
('Công ty CP Nhựa Duy Tân', '0302944555', '02838762222', 'Bình Tân, TP.HCM'),
('Công ty TNHH Lock&Lock HCM', '0309112244', '02854135750', 'Quận 7, TP.HCM'),
('Công ty CP Tập đoàn Thiên Long', '0301464830', '02837505555', 'Bình Tân, TP.HCM'),
('Công ty TNHH Mars Việt Nam (Whiskas/Pedigree)', '0312345678', '02838218899', 'Quận 1, TP.HCM'),
('Công ty TNHH Yakult Việt Nam', '3700801122', '02835129988', 'VSIP 1, Bình Dương'),
('Công ty CP Thực phẩm Dinh dưỡng Nutifood', '0302204200', '02838439135', 'Quận 3, TP.HCM'),
('Công ty TNHH La Vie Việt Nam', '1100100555', '02723823111', 'Tân An, Long An'),
('Công ty CP Thủy Hải Sản Minh Phú', '2000393273', '02903838262', 'TP. Cà Mau, Cà Mau'),
('Công ty TNHH Thực phẩm Cầu Tre (CJ Cầu Tre)', '0300422444', '02838750000', 'Tân Phú, TP.HCM'),
('Công ty CP Đường Biên Hòa (TTC Sugar)', '3900244389', '02763836111', 'Tây Ninh'),
('Công ty TNHH Colgate-Palmolive Việt Nam', '0300755444', '02838239999', 'Quận 1, TP.HCM'),
('Công ty TNHH Johnson & Johnson Việt Nam', '0305556677', '02839103333', 'Quận 1, TP.HCM'),
('Công ty CP Gốm Sứ Minh Long I', '3700145678', '02743668899', 'Thuận An, Bình Dương'),
('Công ty TNHH Thực phẩm Orion & Đối tác Phân phối', '0314567890', '02838990011', 'Quận 10, TP.HCM');

-- 3. 50 Nhân viên (Tên đa dạng ngay từ dòng đầu tiên)
INSERT INTO NhanVien (HoTen, DienThoai, ChucVu, QuayLamViec)
SELECT 
    CONCAT(
        ELT(1 + (n % 10), 'Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Huỳnh', 'Phan', 'Vũ', 'Đặng', 'Bùi'), ' ',
        ELT(1 + (((n * 3) + (n DIV 10)) % 10), 'Thị', 'Văn', 'Minh', 'Ngọc', 'Thu', 'Hoàng', 'Thanh', 'Đức', 'Phương', 'Quốc'), ' ',
        ELT(1 + (((n * 7) + ((n DIV 10) * 2)) % 15), 'An', 'Bình', 'Châu', 'Dũng', 'Hà', 'Hải', 'Hùng', 'Hương', 'Linh', 'Long', 'Mai', 'Nam', 'Phong', 'Trang', 'Tuấn')
    ),
    CONCAT('091', LPAD(n + 1001, 7, '0')),
    ELT(1 + (n % 3), 'Thu ngân', 'Thủ kho', 'Quản lý siêu thị'),
    IF(n % 3 = 0, CONCAT('Quầy 0', 1 + (n % 2), ' (Slave ', 1 + (n % 2), ')'), 'Kho & Điều hành (Master)')
FROM tmp_seq WHERE n < 50;

-- 4. 20 Chương trình khuyến mãi
INSERT INTO ChuongTrinhKhuyenMai (MaCode, TenChuongTrinh, PhanTramGiam, NgayBatDau, NgayKetThuc, TrangThai) VALUES
('CUOITUAN10', 'Siêu sale cuối tuần giảm 10%', 10.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('VIP_GOLD15', 'Ưu đãi khách hàng hạng Vàng 15%', 15.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('VIP_KC20', 'Đặc quyền khách hàng Kim Cương 20%', 20.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('GIOVANG08', 'Khung giờ vàng 17h-19h giảm 8%', 8.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('NGAYDOI12', 'Khuyến mãi ngày đôi hàng tháng 12%', 12.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('MUAHE_MAT', 'Giải nhiệt mùa hè - Đồ uống giảm 10%', 10.00, '2026-04-01', '2026-08-31', 'DangApDung'),
('BACK2SCHOOL', 'Mùa tựu trường - Văn phòng phẩm giảm 15%', 15.00, '2026-08-01', '2026-09-30', 'DangApDung'),
('QUOCKHANH', 'Mừng đại lễ Quốc Khánh 2/9 giảm 18%', 18.00, '2026-08-25', '2026-09-05', 'HetHan'),
('PHUNUVN2010', 'Tôn vinh Phụ nữ Việt Nam 20/10', 15.00, '2026-10-15', '2026-10-22', 'HetHan'),
('BLACKFRIDAY', 'Siêu hội Black Friday giảm sốc 25%', 25.00, '2026-11-20', '2026-11-30', 'DangApDung'),
('NOEL_ANLANH', 'Giáng sinh an lành - Bánh kẹo giảm 12%', 12.00, '2026-12-15', '2026-12-26', 'DangApDung'),
('TET_SUMVAY', 'Tết sum vầy - Quà biếu giảm 15%', 15.00, '2026-01-15', '2026-02-15', 'HetHan'),
('MEVABE10', 'Ngày hội Mẹ và Bé giảm 10%', 10.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('GIADINH05', 'Combo gia đình cuối tháng giảm 5%', 5.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('THANHVIENMOI', 'Chào bạn mới - Giảm 10% đơn đầu tiên', 10.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('TRIANKH07', 'Tri ân khách hàng thân thiết giảm 7%', 7.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('SUAKHOE10', 'Tuần lễ Sữa dinh dưỡng giảm 10%', 10.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('SACHNHA12', 'Nhà sạch bếp thơm - Hóa mỹ phẩm giảm 12%', 12.00, '2026-01-01', '2026-12-31', 'DangApDung'),
('SINHNHATST', 'Mừng sinh nhật Siêu thị giảm 20%', 20.00, '2026-11-01', '2026-11-30', 'DangApDung'),
('QR_PAY05', 'Thanh toán QR VNPAY giảm thêm 5%', 5.00, '2026-01-01', '2026-12-31', 'DangApDung');

-- 5. 1.000 Sản phẩm thật (50 sản phẩm gốc × 20 quy cách/hương vị)
DROP TABLE IF EXISTS tmp_sp_goc;
CREATE TABLE tmp_sp_goc (
    id INT PRIMARY KEY,
    ten_goc VARCHAR(100),
    ma_loai INT,
    ma_ncc INT,
    dvt VARCHAR(20),
    gia_nhap DECIMAL(12,2),
    gia_ban DECIMAL(12,2),
    hsd INT
) ENGINE=InnoDB;

INSERT INTO tmp_sp_goc VALUES
(1, 'Sữa tươi tiệt trùng Vinamilk 100%', 1, 1, 'Lốc', 26000, 32000, 180),
(2, 'Sữa tươi sạch TH True Milk', 1, 2, 'Lốc', 28000, 35000, 180),
(3, 'Sữa tiệt trùng Cô Gái Hà Lan', 1, 3, 'Lốc', 24000, 30000, 180),
(4, 'Sữa chua uống men sống Yakult', 1, 41, 'Lốc', 21000, 26000, 40),
(5, 'Sữa đậu nành Fami / Nutifood', 1, 42, 'Lốc', 19000, 24000, 180),
(6, 'Nước ngọt Pepsi Cola', 2, 4, 'Lốc', 42000, 54000, 365),
(7, 'Nước ngọt Coca-Cola', 2, 5, 'Lốc', 43000, 55000, 365),
(8, 'Trà Xanh Không Độ', 2, 6, 'Lốc', 40000, 50000, 270),
(9, 'Nước khoáng thiên nhiên La Vie', 2, 43, 'Lốc', 20000, 26000, 365),
(10, 'Bia Saigon Lager / Special', 3, 7, 'Thùng', 235000, 275000, 365),
(11, 'Bia Heineken Silver', 3, 8, 'Thùng', 385000, 445000, 365),
(12, 'Cà phê hòa tan Trung Nguyên G7', 4, 9, 'Hộp', 48000, 62000, 730),
(13, 'Cà phê sữa Nescafé', 4, 10, 'Hộp', 45000, 58000, 540),
(14, 'Mì ăn liền Hảo Hảo Tôm Chua Cay', 5, 11, 'Thùng', 98000, 118000, 180),
(15, 'Mì khoai tây Omachi Xốt Bò Hầm', 5, 12, 'Thùng', 195000, 235000, 180),
(16, 'Mì Gấu Đỏ Tôm Gà', 5, 13, 'Thùng', 82000, 99000, 180),
(17, 'Gạo thơm Hạt Ngọc Trời Tiên Nữ', 6, 14, 'Túi', 125000, 155000, 365),
(18, 'Yến mạch nguyên chất Quaker Oats', 6, 15, 'Hộp', 65000, 85000, 365),
(19, 'Dầu thực vật Tường An Cooking Oil', 7, 16, 'Chai', 42000, 52000, 730),
(20, 'Dầu đậu nành nguyên chất Simply', 7, 17, 'Chai', 52000, 64000, 730),
(21, 'Nước mắm Nam Ngư Đệ Nhị', 7, 12, 'Chai', 19000, 25000, 365),
(22, 'Bột ngọt Ajinomoto Umami', 7, 18, 'Gói', 26000, 33000, 730),
(23, 'Đường tinh luyện Biên Hòa Pure', 7, 46, 'Túi', 24000, 30000, 730),
(24, 'Bánh bông lan Solite Kinh Đô', 8, 19, 'Hộp', 42000, 52000, 270),
(25, 'Bánh Choco-Pie Orion', 8, 20, 'Hộp', 48000, 60000, 365),
(26, 'Bánh quy Goody Bibica', 8, 21, 'Hộp', 55000, 72000, 365),
(27, 'Snack khoai tây / bắp Oishi', 8, 22, 'Gói', 7000, 10000, 180),
(28, 'Xúc xích tiệt trùng Vissan', 9, 23, 'Gói', 18000, 24000, 120),
(29, 'Chả giò rế thịt Cầu Tre', 9, 45, 'Gói', 46000, 59000, 365),
(30, 'Thịt heo sạch C.P PorkShop', 10, 24, 'Khay', 68000, 85000, 5),
(31, 'Trứng gà tươi sạch Ba Huân', 10, 25, 'Vỉ', 27000, 34000, 14),
(32, 'Tôm sú đông lạnh Minh Phú', 10, 44, 'Hộp', 145000, 185000, 365),
(33, 'Rau củ hữu cơ Đà Lạt GAP', 11, 26, 'Túi', 18000, 25000, 5),
(34, 'Trái cây tươi đóng khay Vegetigi', 11, 27, 'Khay', 35000, 48000, 7),
(35, 'Kem Merino / Celano Kido', 12, 28, 'Hộp', 38000, 49000, 365),
(36, 'Nước giặt OMO Matic Cửa Trước', 13, 29, 'Túi', 145000, 185000, 730),
(37, 'Bột giặt Tide / Nước xả Downy', 13, 30, 'Túi', 125000, 160000, 730),
(38, 'Nước rửa chén LIX Siêu Sạch', 14, 31, 'Can', 45000, 58000, 730),
(39, 'Nước rửa chén Sunlight Chanh', 14, 29, 'Túi', 21000, 28000, 730),
(40, 'Dầu gội Clear Mát Lạnh Bạc Hà', 15, 29, 'Chai', 135000, 169000, 730),
(41, 'Dầu gội & Sữa tắm nam X-Men', 15, 32, 'Chai', 120000, 155000, 730),
(42, 'Kem đánh răng Colgate Total', 15, 47, 'Tuýp', 32000, 42000, 730),
(43, 'Sữa rửa mặt Nivea Men / Women', 16, 33, 'Tuýp', 58000, 75000, 730),
(44, 'Nước tẩy trang L''Oréal Paris', 16, 34, 'Chai', 135000, 179000, 730),
(45, 'Tã quần em bé Bobby', 17, 35, 'Bịch', 245000, 299000, 1095),
(46, 'Tã dán Huggies Dry / Sữa tắm Johnson', 17, 36, 'Bịch', 230000, 285000, 1095),
(47, 'Hộp đựng thực phẩm Duy Tân', 18, 37, 'Bộ', 65000, 89000, 1825),
(48, 'Bình giữ nhiệt Lock&Lock', 18, 38, 'Chiếc', 220000, 299000, 1825),
(49, 'Bút bi & Tập vở Thiên Long', 19, 39, 'Lốc', 35000, 48000, 1825),
(50, 'Thức ăn hạt cho mèo Whiskas', 20, 40, 'Túi', 85000, 112000, 540);

DROP TABLE IF EXISTS tmp_bienthe;
CREATE TABLE tmp_bienthe (
    id INT PRIMARY KEY,
    ten_bt VARCHAR(60),
    he_so DECIMAL(4,2)
) ENGINE=InnoDB;

INSERT INTO tmp_bienthe VALUES
(1, 'Bản Tiêu Chuẩn', 1.00),
(2, 'Ít Đường', 1.00),
(3, 'Không Đường', 1.05),
(4, 'Có Đường Truyền Thống', 1.00),
(5, 'Hương Dâu Tự Nhiên', 1.05),
(6, 'Hương Socola', 1.05),
(7, 'Hương Cam Tươi', 1.05),
(8, 'Hương Trà Xanh Matcha', 1.10),
(9, 'Gói Nhỏ Tiện Lợi', 0.60),
(10, 'Cỡ Vừa Gia Đình', 1.30),
(11, 'Cỡ Lớn Siêu Tiết Kiệm', 1.80),
(12, 'Combo 2 Tặng 1', 1.90),
(13, 'Lốc 4 Tiết Kiệm', 1.15),
(14, 'Lốc 6 Tiện Dụng', 1.45),
(15, 'Thùng Tiêu Chuẩn', 3.50),
(16, 'Hộp Quà Tặng Đặc Biệt', 1.50),
(17, 'Phiên Bản Mới 2026', 1.10),
(18, 'Công Thức Đậm Đặc', 1.20),
(19, 'Hữu Cơ (Organic)', 1.35),
(20, 'Túi Refill Thay Thế', 0.90);

INSERT INTO SanPham (MaVach, TenSP, MaLoai, MaNCC, DonViTinh, GiaNhap, GiaBan, SoLuongTon, HanSuDungMacDinh)
SELECT 
    CONCAT('893', LPAD(((sp.id - 1) * 20 + bt.id), 10, '0')),
    CONCAT(sp.ten_goc, ' - ', bt.ten_bt),
    sp.ma_loai,
    sp.ma_ncc,
    sp.dvt,
    ROUND(sp.gia_nhap * bt.he_so, -2),
    ROUND(sp.gia_ban * bt.he_so, -2),
    80 + (((sp.id * 7 + bt.id * 11) % 300)),
    sp.hsd
FROM tmp_sp_goc sp
CROSS JOIN tmp_bienthe bt;

-- 6. 10.000 Khách hàng (Trộn đều Họ + Đệm + Tên từng dòng, không trùng lặp)
INSERT INTO KhachHang (HoTen, SoDienThoai, DiemTichLuy, HangThanhVien, NgayDangKy)
SELECT 
    CONCAT(
        ELT(1 + (n % 20), 
            'Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Huỳnh', 'Phan', 'Vũ', 'Võ', 'Đặng',
            'Bùi', 'Đỗ', 'Hồ', 'Ngô', 'Dương', 'Lý', 'Đinh', 'Đoàn', 'Trương', 'Mai'), ' ',
        ELT(1 + (((n DIV 20) + (n * 3)) % 20), 
            'Văn', 'Thị', 'Minh', 'Hoàng', 'Ngọc', 'Thu', 'Anh', 'Đức', 'Quốc', 'Thanh',
            'Phương', 'Hồng', 'Gia', 'Bảo', 'Hải', 'Tuấn', 'Khánh', 'Thùy', 'Kim', 'Xuân'), ' ',
        ELT(1 + (((n DIV 400) + (n * 7)) % 25), 
            'An', 'Bình', 'Châu', 'Dũng', 'Hà', 'Hải', 'Hân', 'Hùng', 'Hương', 'Khoa',
            'Linh', 'Long', 'Mai', 'Nam', 'Nga', 'Nhi', 'Phong', 'Phúc', 'Quân', 'Quỳnh',
            'Tâm', 'Thảo', 'Trang', 'Trung', 'Vy')
    ),
    CONCAT('098', LPAD(n + 1, 7, '0')),
    (n * 17) % 2500,
    ELT(1 + (n % 4), 'Đồng', 'Bạc', 'Vàng', 'Kim Cương'),
    DATE_ADD('2024-01-01 08:00:00', INTERVAL (n % 700) DAY)
FROM tmp_seq WHERE n < 10000;

-- 7. 2.000 Phiếu nhập kho
INSERT INTO PhieuNhapKho (NgayNhap, MaNCC, MaNV, TongTienNhap, GhiChu)
SELECT 
    DATE_ADD('2025-01-01 06:00:00', INTERVAL (n * 4) HOUR),
    1 + (n % 50),
    1 + (n % 50),
    0,
    CONCAT('Nhập lô hàng chính hãng từ nhà cung cấp #', 1 + (n % 50))
FROM tmp_seq WHERE n < 2000;

-- 8. 10.000 Chi tiết phiếu nhập
INSERT INTO ChiTietPhieuNhap (MaPN, MaSP, SoLuongNhap, DonGiaNhap)
SELECT 
    t.MaPN,
    t.MaSP,
    t.SoLuongNhap,
    sp.GiaNhap
FROM (
    SELECT 
        pn.n + 1 AS MaPN,
        1 + (((pn.n + 1) * 7 + slot.n * 13) % 1000) AS MaSP,
        20 + ((pn.n + slot.n) % 80) AS SoLuongNhap
    FROM tmp_seq pn
    CROSS JOIN tmp_seq slot
    WHERE pn.n < 2000 AND slot.n < 5
) t
JOIN SanPham sp ON t.MaSP = sp.MaSP;

-- 9. 26.000 Hóa đơn
INSERT INTO HoaDon (NgayLap, CaLamViec, MaNV, MaKH, MaKM, PhuongThucTT, TongTien)
SELECT 
    DATE_ADD('2025-01-01 07:30:00', INTERVAL (n * 20) MINUTE),
    ELT(1 + (n % 3), 'Ca sáng', 'Ca chiều', 'Ca tối'),
    1 + (n % 50),
    IF(n % 5 = 0, NULL, 1 + (n % 10000)),
    IF(n % 4 = 0, 1 + (n % 20), NULL),
    ELT(1 + (n % 3), 'Tiền mặt', 'Chuyển khoản QR', 'Thẻ ngân hàng'),
    0
FROM tmp_seq WHERE n < 26000;

-- 10. 52.000 Chi tiết hóa đơn
INSERT INTO ChiTietHoaDon (MaHD, MaSP, SoLuong, DonGiaBan, GiamGia)
SELECT 
    t.MaHD,
    t.MaSP,
    t.SoLuong,
    sp.GiaBan,
    IF((t.MaHD + t.slot) % 5 = 0, ROUND(sp.GiaBan * 0.1, -2), 0)
FROM (
    SELECT 
        hd.n + 1 AS MaHD,
        1 + (((hd.n + 1) * 3 + slot.n * 17) % 1000) AS MaSP,
        1 + ((hd.n + slot.n) % 4) AS SoLuong,
        slot.n AS slot
    FROM tmp_seq hd
    CROSS JOIN tmp_seq slot
    WHERE hd.n < 26000 AND slot.n < 2
) t
JOIN SanPham sp ON t.MaSP = sp.MaSP;

-- Cập nhật TongTienNhap & TongTien khớp với bảng chi tiết
UPDATE PhieuNhapKho pn
JOIN (SELECT MaPN, SUM(ThanhTienNhap) AS Tong FROM ChiTietPhieuNhap GROUP BY MaPN) ct ON pn.MaPN = ct.MaPN
SET pn.TongTienNhap = ct.Tong;

UPDATE HoaDon hd
JOIN (SELECT MaHD, SUM(ThanhTien) AS Tong FROM ChiTietHoaDon GROUP BY MaHD) ct ON hd.MaHD = ct.MaHD
SET hd.TongTien = ct.Tong;

-- Dọn bảng tạm
DROP TABLE IF EXISTS tmp_seq;
DROP TABLE IF EXISTS tmp_sp_goc;
DROP TABLE IF EXISTS tmp_bienthe;

-- Kiểm tra tổng số dòng của 10 bảng (101.140 dòng)
SELECT 'LoaiSanPham' AS TenBang, COUNT(*) AS SoDong FROM LoaiSanPham
UNION ALL SELECT 'NhaCungCap', COUNT(*) FROM NhaCungCap
UNION ALL SELECT 'NhanVien', COUNT(*) FROM NhanVien
UNION ALL SELECT 'ChuongTrinhKhuyenMai', COUNT(*) FROM ChuongTrinhKhuyenMai
UNION ALL SELECT 'SanPham', COUNT(*) FROM SanPham
UNION ALL SELECT 'KhachHang', COUNT(*) FROM KhachHang
UNION ALL SELECT 'PhieuNhapKho', COUNT(*) FROM PhieuNhapKho
UNION ALL SELECT 'ChiTietPhieuNhap', COUNT(*) FROM ChiTietPhieuNhap
UNION ALL SELECT 'HoaDon', COUNT(*) FROM HoaDon
UNION ALL SELECT 'ChiTietHoaDon', COUNT(*) FROM ChiTietHoaDon;
