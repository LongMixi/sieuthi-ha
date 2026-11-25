-- =====================================================
-- Spatial Retail DB (PostgreSQL + PostGIS)
-- Chay lan luot tu tren xuong duoi
-- =====================================================
CREATE EXTENSION IF NOT EXISTS postgis;

-- ---------- 1. HANH CHINH / BAN DO ----------
CREATE TABLE tinh_tp (
  ma_tinh   SERIAL PRIMARY KEY,
  ten_tinh  VARCHAR(100) NOT NULL,
  ranh_gioi geometry(MultiPolygon, 4326)
);

CREATE TABLE quan_huyen (
  ma_quan   SERIAL PRIMARY KEY,
  ma_tinh   INT NOT NULL REFERENCES tinh_tp(ma_tinh),
  ten_quan  VARCHAR(100) NOT NULL,
  dan_so    INT,
  ranh_gioi geometry(MultiPolygon, 4326)
);

CREATE TABLE duong (
  ma_duong  SERIAL PRIMARY KEY,
  ten_duong VARCHAR(150) NOT NULL,
  loai_duong VARCHAR(50),
  so_lan    INT,
  tuyen     geometry(LineString, 4326)
);

CREATE TABLE quan_duong (
  ma_quan  INT REFERENCES quan_huyen(ma_quan),
  ma_duong INT REFERENCES duong(ma_duong),
  PRIMARY KEY (ma_quan, ma_duong)
);

-- ---------- 2. DANH MUC / KHO / CUA HANG ----------
CREATE TABLE danhmucsanpham (
  ma_danh_muc  SERIAL PRIMARY KEY,
  ten_danh_muc VARCHAR(100) NOT NULL,
  mo_ta        TEXT,
  trang_thai   VARCHAR(20)
);

CREATE TABLE sanpham (
  ma_san_pham  SERIAL PRIMARY KEY,
  ma_vach      VARCHAR(30) UNIQUE,
  ten_san_pham VARCHAR(200) NOT NULL,
  ma_danh_muc  INT NOT NULL REFERENCES danhmucsanpham(ma_danh_muc),
  don_vi_tinh  VARCHAR(20),
  ton_kho_toi_thieu INT,
  ton_kho_toi_da    INT,
  mo_ta        TEXT,
  trang_thai   VARCHAR(20)
);

CREATE TABLE kho (
  ma_kho     SERIAL PRIMARY KEY,
  ten_kho    VARCHAR(100) NOT NULL,
  dia_chi    VARCHAR(255),
  loai_kho   VARCHAR(30),
  trang_thai VARCHAR(20),
  ma_quan    INT REFERENCES quan_huyen(ma_quan),
  vi_tri     geometry(Point, 4326)
);

CREATE TABLE tonkho (
  ma_kho      INT REFERENCES kho(ma_kho),
  ma_san_pham INT REFERENCES sanpham(ma_san_pham),
  so_luong_ton INT NOT NULL DEFAULT 0,
  vi_tri_kho  VARCHAR(50),
  thoi_diem_cap_nhat_cuoi TIMESTAMP,
  PRIMARY KEY (ma_kho, ma_san_pham)
);

CREATE TABLE cuahang (
  ma_ch   SERIAL PRIMARY KEY,
  ten_ch  VARCHAR(100) NOT NULL,
  dia_chi VARCHAR(255),
  ma_quan INT REFERENCES quan_huyen(ma_quan),
  gio_mo_cua  TIME,
  gio_dong_cua TIME,
  trang_thai VARCHAR(20),
  vi_tri  geometry(Point, 4326)
);

CREATE TABLE khuvuc_phucvu (
  ma_kv    SERIAL PRIMARY KEY,
  ma_ch    INT NOT NULL REFERENCES cuahang(ma_ch),
  ban_kinh NUMERIC(8,2),
  vung_phuc_vu geometry(Polygon, 4326)
);

-- ---------- 3. NHAN SU & DOI TAC ----------
CREATE TABLE bophan (
  ma_bo_phan  SERIAL PRIMARY KEY,
  ten_bo_phan VARCHAR(100) NOT NULL
);

CREATE TABLE chucvu (
  ma_chuc_vu  SERIAL PRIMARY KEY,
  ten_chuc_vu VARCHAR(100) NOT NULL,
  luong_co_ban NUMERIC(14,2)
);

CREATE TABLE nhanvien (
  ma_nv       SERIAL PRIMARY KEY,
  ho_ten      VARCHAR(100) NOT NULL,
  sdt         VARCHAR(15),
  ngay_vao_lam DATE,
  ma_bo_phan  INT REFERENCES bophan(ma_bo_phan),
  ma_chuc_vu  INT REFERENCES chucvu(ma_chuc_vu),
  ma_ch       INT REFERENCES cuahang(ma_ch),
  trang_thai  VARCHAR(20)
);

CREATE TABLE shipper (
  ma_shipper SERIAL PRIMARY KEY,
  ma_nv      INT UNIQUE NOT NULL REFERENCES nhanvien(ma_nv),
  bien_so    VARCHAR(15),
  vi_tri_hien_tai geometry(Point, 4326)
);

CREATE TABLE khachhang (
  ma_kh   SERIAL PRIMARY KEY,
  ho_ten  VARCHAR(100) NOT NULL,
  sdt     VARCHAR(15) UNIQUE,
  email   VARCHAR(100),
  ngay_dang_ky DATE
);

CREATE TABLE thetichdiem (
  ma_the   SERIAL PRIMARY KEY,
  ma_kh    INT UNIQUE NOT NULL REFERENCES khachhang(ma_kh),
  diem_tich_luy INT DEFAULT 0,
  hang_the VARCHAR(20),
  ngay_cap DATE
);

CREATE TABLE diachi_khachhang (
  ma_dc   SERIAL PRIMARY KEY,
  ma_kh   INT NOT NULL REFERENCES khachhang(ma_kh),
  dia_chi VARCHAR(255),
  ma_quan INT REFERENCES quan_huyen(ma_quan),
  vi_tri  geometry(Point, 4326)
);

CREATE TABLE nhacungcap (
  ma_ncc  SERIAL PRIMARY KEY,
  ten_ncc VARCHAR(150) NOT NULL,
  sdt     VARCHAR(15),
  dia_chi VARCHAR(255),
  vi_tri  geometry(Point, 4326)
);

-- ---------- 4. GIAO DICH / VAN HANH ----------
CREATE TABLE quay_pos (
  ma_quay  SERIAL PRIMARY KEY,
  ma_ch    INT NOT NULL REFERENCES cuahang(ma_ch),
  ten_quay VARCHAR(50),
  trang_thai VARCHAR(20)
);

CREATE TABLE ca_lamviec (
  ma_ca   SERIAL PRIMARY KEY,
  ma_quay INT NOT NULL REFERENCES quay_pos(ma_quay),
  ma_nv   INT NOT NULL REFERENCES nhanvien(ma_nv),
  gio_bat_dau  TIMESTAMP NOT NULL,
  gio_ket_thuc TIMESTAMP,
  tien_dau_ca  NUMERIC(14,2),
  tien_cuoi_ca NUMERIC(14,2)
);

CREATE TABLE phuongthuc_thanhtoan (
  ma_pttt  SERIAL PRIMARY KEY,
  ten_pttt VARCHAR(50) NOT NULL
);

CREATE TABLE khuyenmai (
  ma_km   SERIAL PRIMARY KEY,
  ten_km  VARCHAR(150) NOT NULL,
  ngay_bat_dau  DATE,
  ngay_ket_thuc DATE,
  trang_thai VARCHAR(20)
);

CREATE TABLE chitiet_khuyenmai (
  ma_km       INT REFERENCES khuyenmai(ma_km),
  ma_san_pham INT REFERENCES sanpham(ma_san_pham),
  phan_tram_giam NUMERIC(5,2),
  PRIMARY KEY (ma_km, ma_san_pham)
);

CREATE TABLE phieunhap (
  ma_phieu_nhap SERIAL PRIMARY KEY,
  ma_ncc INT NOT NULL REFERENCES nhacungcap(ma_ncc),
  ma_kho INT NOT NULL REFERENCES kho(ma_kho),
  ma_nv  INT NOT NULL REFERENCES nhanvien(ma_nv),
  ngay_nhap TIMESTAMP NOT NULL,
  tong_tien NUMERIC(14,2)
);

CREATE TABLE chitiet_phieunhap (
  ma_phieu_nhap INT REFERENCES phieunhap(ma_phieu_nhap),
  ma_san_pham   INT REFERENCES sanpham(ma_san_pham),
  so_luong INT NOT NULL,
  don_gia  NUMERIC(14,2) NOT NULL,
  PRIMARY KEY (ma_phieu_nhap, ma_san_pham)
);

CREATE TABLE chitiet_lo_hang (
  ma_lo_hang SERIAL PRIMARY KEY,
  ma_san_pham   INT NOT NULL REFERENCES sanpham(ma_san_pham),
  ma_phieu_nhap INT NOT NULL REFERENCES phieunhap(ma_phieu_nhap),
  nsx DATE,
  hsd DATE,
  so_luong_nhap INT,
  so_luong_ton_kho INT,
  gia_nhap NUMERIC(14,2),
  mo_ta TEXT
);

CREATE TABLE donhang (
  ma_dh   SERIAL PRIMARY KEY,
  ma_kh   INT REFERENCES khachhang(ma_kh),          -- NULL: khach vang lai
  ma_ch   INT NOT NULL REFERENCES cuahang(ma_ch),
  ma_ca   INT REFERENCES ca_lamviec(ma_ca),         -- ban tai quay
  ma_dc   INT REFERENCES diachi_khachhang(ma_dc),   -- giao hang
  ma_pttt INT REFERENCES phuongthuc_thanhtoan(ma_pttt),
  ma_km   INT REFERENCES khuyenmai(ma_km),
  loai_don VARCHAR(20),                             -- tai_quay / giao_hang
  ngay_dat TIMESTAMP NOT NULL,
  tong_tien NUMERIC(14,2),
  trang_thai VARCHAR(20)
);

CREATE TABLE chitiet_donhang (
  ma_dh       INT REFERENCES donhang(ma_dh),
  ma_san_pham INT REFERENCES sanpham(ma_san_pham),
  so_luong INT NOT NULL,
  don_gia  NUMERIC(14,2) NOT NULL,
  PRIMARY KEY (ma_dh, ma_san_pham)
);

CREATE TABLE chuyengiao (
  ma_cg      SERIAL PRIMARY KEY,
  ma_dh      INT UNIQUE NOT NULL REFERENCES donhang(ma_dh),
  ma_shipper INT NOT NULL REFERENCES shipper(ma_shipper),
  tuyen_di   geometry(LineString, 4326),
  khoang_cach NUMERIC(10,2),   -- met
  thoi_gian   INT              -- phut
);

CREATE TABLE lichsu_vitri_shipper (
  ma_ls      BIGSERIAL PRIMARY KEY,
  ma_shipper INT NOT NULL REFERENCES shipper(ma_shipper),
  vi_tri     geometry(Point, 4326),
  thoi_diem  TIMESTAMP NOT NULL
);

CREATE TABLE phieuthu (
  ma_phieu_thu SERIAL PRIMARY KEY,
  ma_dh   INT REFERENCES donhang(ma_dh),
  ma_pttt INT REFERENCES phuongthuc_thanhtoan(ma_pttt),
  ma_nv   INT REFERENCES nhanvien(ma_nv),
  so_tien NUMERIC(14,2) NOT NULL,
  ngay_thu TIMESTAMP,
  noi_dung VARCHAR(255)
);

CREATE TABLE phieuchi (
  ma_phieu_chi SERIAL PRIMARY KEY,
  ma_phieu_nhap INT REFERENCES phieunhap(ma_phieu_nhap),
  ma_pttt INT REFERENCES phuongthuc_thanhtoan(ma_pttt),
  ma_nv   INT REFERENCES nhanvien(ma_nv),
  so_tien NUMERIC(14,2) NOT NULL,
  ngay_chi TIMESTAMP,
  noi_dung VARCHAR(255)
);

-- =====================================================
-- 5. SPATIAL INDEX (GiST) cho moi cot [GEO]
-- (Tam thoi KHONG tao index cho lichsu_vitri_shipper,
--  de so sanh hieu nang o muc 8)
-- =====================================================
CREATE INDEX idx_tinh_ranhgioi    ON tinh_tp         USING GIST (ranh_gioi);
CREATE INDEX idx_quan_ranhgioi    ON quan_huyen      USING GIST (ranh_gioi);
CREATE INDEX idx_duong_tuyen      ON duong           USING GIST (tuyen);
CREATE INDEX idx_kho_vitri        ON kho             USING GIST (vi_tri);
CREATE INDEX idx_cuahang_vitri    ON cuahang         USING GIST (vi_tri);
CREATE INDEX idx_kv_vung          ON khuvuc_phucvu   USING GIST (vung_phuc_vu);
CREATE INDEX idx_shipper_vitri    ON shipper         USING GIST (vi_tri_hien_tai);
CREATE INDEX idx_dckh_vitri       ON diachi_khachhang USING GIST (vi_tri);
CREATE INDEX idx_ncc_vitri        ON nhacungcap      USING GIST (vi_tri);
CREATE INDEX idx_chuyengiao_tuyen ON chuyengiao      USING GIST (tuyen_di);