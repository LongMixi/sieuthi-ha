INSERT INTO tinh_tp (ten_tinh, ranh_gioi)
SELECT name_1,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(geom)), 3))
FROM stg_gadm2
WHERE name_1 ILIKE 'H_ N_i'
GROUP BY name_1;

INSERT INTO quan_huyen (ma_tinh, ten_quan, ranh_gioi)
SELECT t.ma_tinh, g.name_2,
       ST_Multi(ST_CollectionExtract(ST_MakeValid(g.geom), 3))
FROM stg_gadm2 g
JOIN tinh_tp t ON t.ten_tinh = g.name_1;

UPDATE quan_huyen SET dan_so = 100000 + floor(random() * 400000)::int;

INSERT INTO duong (ten_duong, loai_duong, so_lan, tuyen)
SELECT l.name, l.highway,
       CASE l.highway
         WHEN 'motorway'  THEN 6
         WHEN 'trunk'     THEN 6
         WHEN 'primary'   THEN 4
         WHEN 'secondary' THEN 4
         ELSE 2
       END,
       l.geom
FROM stg_osm_lines l
WHERE GeometryType(l.geom) = 'LINESTRING';

INSERT INTO quan_duong (ma_quan, ma_duong)
SELECT DISTINCT q.ma_quan, d.ma_duong
FROM duong d
JOIN quan_huyen q ON ST_Intersects(d.tuyen, q.ranh_gioi);

DROP TABLE stg_gadm2, stg_osm_lines;



-- =====================================================
-- SINH DU LIEU NGHIEP VU GIA LAP (PostgreSQL + PostGIS >= 3.0)
--
-- YEU CAU TRUOC KHI CHAY:
--   * Da tao bang + index (spatial_retail_postgis.sql, muc 1-5)
--   * Bang quan_huyen da co du lieu (01_load_real_geodata.md)
--   * Script nay TRUNCATE ... RESTART IDENTITY o dau file, nen ma (ID)
--     cac bang bat dau tu 1. Cac phep tinh ID ben duoi dua tren gia dinh nay.
--
-- THOI GIAN CHAY: khoang 1-3 phut.
-- KHONG tao index cho lichsu_vitri_shipper o day: de danh cho
-- phan so sanh hieu nang (muc 8 trong spatial_retail_postgis.sql).
-- =====================================================

-- ---------- 0. HAM HO TRO ----------
-- Chon ngau nhien 1 quan
CREATE OR REPLACE FUNCTION random_quan() RETURNS int
LANGUAGE sql VOLATILE AS $$
  SELECT ma_quan FROM quan_huyen ORDER BY random() LIMIT 1
$$;

-- Sinh 1 diem ngau nhien nam BEN TRONG ranh gioi cua quan
CREATE OR REPLACE FUNCTION random_point_in_quan(p_ma_quan int) RETURNS geometry
LANGUAGE sql VOLATILE AS $$
  SELECT (ST_Dump(ST_GeneratePoints(ranh_gioi, 1))).geom
  FROM quan_huyen WHERE ma_quan = p_ma_quan
$$;

-- ---------- 1. XOA DU LIEU NGHIEP VU CU (giu lai du lieu dia ly) ----------
TRUNCATE cuahang, kho, danhmucsanpham, bophan, chucvu, khachhang,
         nhacungcap, phuongthuc_thanhtoan, khuyenmai
RESTART IDENTITY CASCADE;

-- ---------- 2. DANH MUC, SAN PHAM, BANG TRA CUU ----------
INSERT INTO danhmucsanpham (ten_danh_muc, mo_ta, trang_thai) VALUES
('Do uong', NULL, 'active'),
('Banh keo', NULL, 'active'),
('Thuc pham kho', NULL, 'active'),
('Sua va che pham', NULL, 'active'),
('Gia vi', NULL, 'active'),
('Do dung gia dinh', NULL, 'active'),
('Cham soc ca nhan', NULL, 'active'),
('Thuc pham tuoi', NULL, 'active');

INSERT INTO sanpham (ma_vach, ten_san_pham, ma_danh_muc, don_vi_tinh,
                     ton_kho_toi_thieu, ton_kho_toi_da, trang_thai)
SELECT '8930' || LPAD(g::text, 6, '0'),
       dm.ten_danh_muc || ' mau ' || g,
       dm.ma_danh_muc,
       (ARRAY['cai','chai','goi','hop','kg'])[1 + g % 5],
       20, 500, 'active'
FROM generate_series(1, 200) g
JOIN danhmucsanpham dm ON dm.ma_danh_muc = 1 + (g % 8);

INSERT INTO bophan (ten_bo_phan) VALUES ('Giao hang'), ('Thu ngan'), ('Kho');
INSERT INTO chucvu (ten_chuc_vu, luong_co_ban) VALUES
('Shipper', 8000000), ('Thu ngan', 9000000), ('Thu kho', 10000000);
INSERT INTO phuongthuc_thanhtoan (ten_pttt) VALUES ('Tien mat'), ('Chuyen khoan');

INSERT INTO khuyenmai (ten_km, ngay_bat_dau, ngay_ket_thuc, trang_thai)
SELECT 'Khuyen mai ' || g, CURRENT_DATE - 90 + g * 5, CURRENT_DATE - 60 + g * 5, 'active'
FROM generate_series(1, 10) g;

INSERT INTO chitiet_khuyenmai (ma_km, ma_san_pham, phan_tram_giam)
SELECT km.ma_km, sp.ma_san_pham, 5 + (km.ma_km % 5) * 5
FROM khuyenmai km
JOIN sanpham sp ON sp.ma_san_pham % 10 = km.ma_km % 10;

-- ---------- 3. CUA HANG, KHU VUC PHUC VU, KHO, NHA CUNG CAP ----------
-- 30 cua hang, moi cua hang o 1 diem ngau nhien trong 1 quan ngau nhien
INSERT INTO cuahang (ten_ch, dia_chi, ma_quan, gio_mo_cua, gio_dong_cua, trang_thai, vi_tri)
SELECT 'Cua hang ' || s.g, 'Dia chi cua hang ' || s.g, s.ma_quan,
       TIME '07:00', TIME '22:00', 'active',
       random_point_in_quan(s.ma_quan)
FROM (SELECT g, random_quan() AS ma_quan FROM generate_series(1, 30) g) s;

-- Khu vuc phuc vu = vung dem 3 km quanh cua hang
INSERT INTO khuvuc_phucvu (ma_ch, ban_kinh, vung_phuc_vu)
SELECT ma_ch, 3000, ST_Buffer(vi_tri::geography, 3000)::geometry
FROM cuahang;

INSERT INTO kho (ten_kho, dia_chi, loai_kho, trang_thai, ma_quan, vi_tri)
SELECT 'Kho ' || s.g, 'Dia chi kho ' || s.g,
       CASE WHEN s.g = 1 THEN 'trung tam' ELSE 'khu vuc' END,
       'active', s.ma_quan, random_point_in_quan(s.ma_quan)
FROM (SELECT g, random_quan() AS ma_quan FROM generate_series(1, 3) g) s;

INSERT INTO tonkho (ma_kho, ma_san_pham, so_luong_ton, vi_tri_kho, thoi_diem_cap_nhat_cuoi)
SELECT k.ma_kho, sp.ma_san_pham, floor(random() * 500)::int,
       'Ke ' || (sp.ma_san_pham % 20 + 1),
       NOW() - random() * INTERVAL '7 days'
FROM kho k CROSS JOIN sanpham sp;

INSERT INTO nhacungcap (ten_ncc, sdt, dia_chi, vi_tri)
SELECT 'Nha cung cap ' || s.g, '024' || LPAD(s.g::text, 7, '0'),
       'Dia chi NCC ' || s.g, random_point_in_quan(s.ma_quan)
FROM (SELECT g, random_quan() AS ma_quan FROM generate_series(1, 15) g) s;

-- ---------- 4. NHAN VIEN, SHIPPER ----------
-- 150 nhan vien: 1-40 shipper, 41-100 thu ngan (2 nguoi / cua hang), 101-150 thu kho
INSERT INTO nhanvien (ho_ten, sdt, ngay_vao_lam, ma_bo_phan, ma_chuc_vu, ma_ch, trang_thai)
SELECT 'Nhan vien ' || g,
       '0912' || LPAD(g::text, 6, '0'),
       CURRENT_DATE - (random() * 1500)::int,
       CASE WHEN g <= 40 THEN 1 WHEN g <= 100 THEN 2 ELSE 3 END,
       CASE WHEN g <= 40 THEN 1 WHEN g <= 100 THEN 2 ELSE 3 END,
       1 + g % 30,
       'active'
FROM generate_series(1, 150) g;

INSERT INTO shipper (ma_nv, bien_so, vi_tri_hien_tai)
SELECT s.ma_nv,
       '29' || CHR(65 + s.ma_nv % 26) || '-' || LPAD((10000 + s.ma_nv * 37 % 90000)::text, 5, '0'),
       random_point_in_quan(s.ma_quan)
FROM (SELECT ma_nv, random_quan() AS ma_quan
      FROM nhanvien WHERE ma_chuc_vu = 1) s;

-- ---------- 5. KHACH HANG ----------
INSERT INTO khachhang (ho_ten, sdt, email, ngay_dang_ky)
SELECT 'Khach hang ' || g, '09' || LPAD(g::text, 8, '0'),
       'kh' || g || '@example.com', CURRENT_DATE - (random() * 730)::int
FROM generate_series(1, 20000) g;

-- 2/3 khach hang co the tich diem
INSERT INTO thetichdiem (ma_kh, diem_tich_luy, hang_the, ngay_cap)
SELECT s.ma_kh, s.diem,
       CASE WHEN s.diem >= 3000 THEN 'vang' WHEN s.diem >= 1000 THEN 'bac' ELSE 'dong' END,
       kh.ngay_dang_ky
FROM (SELECT ma_kh, floor(random() * 5000)::int AS diem
      FROM khachhang WHERE ma_kh % 3 <> 0) s
JOIN khachhang kh ON kh.ma_kh = s.ma_kh;

-- Moi khach co 1 dia chi, 1/5 khach co them dia chi thu 2.
-- Diem dia chi nam trong quan duoc luu o cot ma_quan.
INSERT INTO diachi_khachhang (ma_kh, dia_chi, ma_quan, vi_tri)
SELECT s.ma_kh, 'So ' || s.n || ', ngo ' || (s.ma_kh % 200 + 1),
       s.ma_quan, random_point_in_quan(s.ma_quan)
FROM (SELECT kh.ma_kh, n, random_quan() AS ma_quan
      FROM khachhang kh CROSS JOIN generate_series(1, 2) n
      WHERE n = 1 OR kh.ma_kh % 5 = 0) s;

-- ---------- 6. QUAY POS, CA LAM VIEC (90 ngay gan nhat) ----------
INSERT INTO quay_pos (ma_ch, ten_quay, trang_thai)
SELECT ch.ma_ch, 'Quay ' || q, 'active'
FROM cuahang ch CROSS JOIN generate_series(1, 2) q;

-- Moi quay cua 1 cua hang ung voi 1 thu ngan cua cua hang do
WITH q AS (
  SELECT ma_quay, ma_ch,
         ROW_NUMBER() OVER (PARTITION BY ma_ch ORDER BY ma_quay) AS rn
  FROM quay_pos
), c AS (
  SELECT ma_nv, ma_ch,
         ROW_NUMBER() OVER (PARTITION BY ma_ch ORDER BY ma_nv) AS rn
  FROM nhanvien WHERE ma_chuc_vu = 2
)
INSERT INTO ca_lamviec (ma_quay, ma_nv, gio_bat_dau, gio_ket_thuc, tien_dau_ca, tien_cuoi_ca)
SELECT q.ma_quay, c.ma_nv, d + TIME '08:00', d + TIME '16:00',
       2000000, 2000000 + floor(random() * 8000000)
FROM q
JOIN c ON c.ma_ch = q.ma_ch AND c.rn = q.rn
CROSS JOIN generate_series((CURRENT_DATE - 89)::timestamp,
                           CURRENT_DATE::timestamp, INTERVAL '1 day') d;

-- ---------- 7. NHAP HANG ----------
-- 300 phieu nhap; nhan vien 101-150 la thu kho
INSERT INTO phieunhap (ma_ncc, ma_kho, ma_nv, ngay_nhap, tong_tien)
SELECT 1 + g % 15, 1 + g % 3, 101 + g % 50,
       NOW() - random() * INTERVAL '180 days', 0
FROM generate_series(1, 300) g;

-- Moi phieu nhap 5 san pham
INSERT INTO chitiet_phieunhap (ma_phieu_nhap, ma_san_pham, so_luong, don_gia)
SELECT pn.ma_phieu_nhap, sp.ma_san_pham,
       50 + floor(random() * 450)::int,
       5000 + (sp.ma_san_pham % 50) * 1000
FROM phieunhap pn
JOIN sanpham sp ON (sp.ma_san_pham + pn.ma_phieu_nhap) % 40 = 0;

UPDATE phieunhap p SET tong_tien = s.t
FROM (SELECT ma_phieu_nhap, SUM(so_luong * don_gia) AS t
      FROM chitiet_phieunhap GROUP BY ma_phieu_nhap) s
WHERE s.ma_phieu_nhap = p.ma_phieu_nhap;

INSERT INTO chitiet_lo_hang (ma_san_pham, ma_phieu_nhap, nsx, hsd,
                             so_luong_nhap, so_luong_ton_kho, gia_nhap)
SELECT ct.ma_san_pham, ct.ma_phieu_nhap,
       pn.ngay_nhap::date - 30,
       pn.ngay_nhap::date + 90 + (random() * 270)::int,
       ct.so_luong, floor(ct.so_luong * random())::int, ct.don_gia
FROM chitiet_phieunhap ct
JOIN phieunhap pn ON pn.ma_phieu_nhap = ct.ma_phieu_nhap;

INSERT INTO phieuchi (ma_phieu_nhap, ma_pttt, ma_nv, so_tien, ngay_chi, noi_dung)
SELECT ma_phieu_nhap, 1 + ma_phieu_nhap % 2, ma_nv, tong_tien, ngay_nhap,
       'Thanh toan phieu nhap ' || ma_phieu_nhap
FROM phieunhap;

-- ---------- 8. DON HANG ----------
-- 8.1 Don ban tai quay: 40.000 don, gan voi ca lam viec (cua hang = cua hang cua quay)
INSERT INTO donhang (ma_kh, ma_ch, ma_ca, ma_pttt, ma_km, loai_don, ngay_dat, trang_thai)
SELECT CASE WHEN random() < 0.4 THEN 1 + floor(random() * 20000)::int END,  -- 60% khach vang lai
       q.ma_ch, ca.ma_ca, 1 + round(random())::int,
       CASE WHEN random() < 0.1 THEN 1 + floor(random() * 10)::int END,
       'tai_quay',
       ca.gio_bat_dau + random() * 480 * INTERVAL '1 minute',
       'hoan_thanh'
FROM generate_series(1, 40000) g
JOIN ca_lamviec ca ON ca.ma_ca = 1 + g % (SELECT COUNT(*) FROM ca_lamviec)
JOIN quay_pos q    ON q.ma_quay = ca.ma_quay;

-- 8.2 Don giao hang: 60.000 don. Cua hang phuc vu = cua hang GAN NHAT dia chi khach
--     (toan tu <-> la K-nearest-neighbor, tan dung GiST index cua cuahang.vi_tri)
INSERT INTO donhang (ma_kh, ma_ch, ma_dc, ma_pttt, ma_km, loai_don, ngay_dat, trang_thai)
SELECT dc.ma_kh, ch.ma_ch, dc.ma_dc, 1 + round(random())::int,
       CASE WHEN random() < 0.1 THEN 1 + floor(random() * 10)::int END,
       'giao_hang',
       NOW() - random() * INTERVAL '90 days',
       CASE WHEN random() < 0.05 THEN 'da_huy' ELSE 'hoan_thanh' END
FROM generate_series(1, 60000) g
JOIN diachi_khachhang dc
  ON dc.ma_dc = 1 + (g * 7919) % (SELECT COUNT(*) FROM diachi_khachhang)
CROSS JOIN LATERAL (
  SELECT c.ma_ch FROM cuahang c ORDER BY c.vi_tri <-> dc.vi_tri LIMIT 1
) ch;

-- 8.3 Chi tiet don hang: moi don 1-5 san pham khac nhau
INSERT INTO chitiet_donhang (ma_dh, ma_san_pham, so_luong, don_gia)
SELECT s.ma_dh, s.sp, 1 + floor(random() * 5)::int, 10000 + (s.sp % 50) * 2000
FROM (
  SELECT d.ma_dh, 1 + ((d.ma_dh * 13 + k * 37) % 200) AS sp
  FROM donhang d
  CROSS JOIN generate_series(1, 5) k
  WHERE k <= 1 + (d.ma_dh % 5)
) s;

UPDATE donhang d SET tong_tien = s.t
FROM (SELECT ma_dh, SUM(so_luong * don_gia) AS t
      FROM chitiet_donhang GROUP BY ma_dh) s
WHERE s.ma_dh = d.ma_dh;

-- ---------- 9. GIAO HANG ----------
-- Tuyen di = duong thang (duong chim bay) tu cua hang den dia chi khach.
-- Toc do gia dinh 25 km/h, cong 5 phut chuan bi.
INSERT INTO chuyengiao (ma_dh, ma_shipper, tuyen_di, khoang_cach, thoi_gian)
SELECT s.ma_dh,
       1 + s.ma_dh % 40,                       -- shipper co ma 1..40
       s.tuyen, s.dist,
       (5 + round(s.dist / 25000.0 * 60))::int
FROM (
  SELECT d.ma_dh,
         ST_MakeLine(ch.vi_tri, dc.vi_tri) AS tuyen,
         ROUND(ST_Distance(ch.vi_tri::geography, dc.vi_tri::geography)::numeric, 2) AS dist
  FROM donhang d
  JOIN cuahang ch          ON ch.ma_ch = d.ma_ch
  JOIN diachi_khachhang dc ON dc.ma_dc = d.ma_dc
  WHERE d.loai_don = 'giao_hang' AND d.trang_thai = 'hoan_thanh'
) s;

-- Lich su GPS: 11 diem doc moi tuyen giao (khoang 600.000 dong).
-- Day la bang lon nhat, dung de so sanh hieu nang truoc/sau khi tao GiST index.
INSERT INTO lichsu_vitri_shipper (ma_shipper, vi_tri, thoi_diem)
SELECT cg.ma_shipper,
       ST_LineInterpolatePoint(cg.tuyen_di, (k / 10.0)::float8),
       d.ngay_dat + (k / 10.0)::float8 * cg.thoi_gian * INTERVAL '1 minute'
FROM chuyengiao cg
JOIN donhang d ON d.ma_dh = cg.ma_dh
CROSS JOIN generate_series(0, 10) k;

-- ---------- 10. THU TIEN ----------
INSERT INTO phieuthu (ma_dh, ma_pttt, ma_nv, so_tien, ngay_thu, noi_dung)
SELECT d.ma_dh, d.ma_pttt, COALESCE(ca.ma_nv, sh.ma_nv), d.tong_tien, d.ngay_dat,
       'Thu tien don hang ' || d.ma_dh
FROM donhang d
LEFT JOIN ca_lamviec ca ON ca.ma_ca = d.ma_ca
LEFT JOIN chuyengiao cg ON cg.ma_dh = d.ma_dh
LEFT JOIN shipper sh    ON sh.ma_shipper = cg.ma_shipper
WHERE d.trang_thai = 'hoan_thanh';

-- ---------- 11. THONG KE SAU KHI SINH ----------
ANALYZE;

SELECT 'quan_huyen' AS bang, COUNT(*) AS so_dong FROM quan_huyen
UNION ALL SELECT 'duong', COUNT(*) FROM duong
UNION ALL SELECT 'cuahang', COUNT(*) FROM cuahang
UNION ALL SELECT 'sanpham', COUNT(*) FROM sanpham
UNION ALL SELECT 'nhanvien', COUNT(*) FROM nhanvien
UNION ALL SELECT 'shipper', COUNT(*) FROM shipper
UNION ALL SELECT 'khachhang', COUNT(*) FROM khachhang
UNION ALL SELECT 'diachi_khachhang', COUNT(*) FROM diachi_khachhang
UNION ALL SELECT 'ca_lamviec', COUNT(*) FROM ca_lamviec
UNION ALL SELECT 'donhang', COUNT(*) FROM donhang
UNION ALL SELECT 'chitiet_donhang', COUNT(*) FROM chitiet_donhang
UNION ALL SELECT 'chuyengiao', COUNT(*) FROM chuyengiao
UNION ALL SELECT 'lichsu_vitri_shipper', COUNT(*) FROM lichsu_vitri_shipper
UNION ALL SELECT 'phieunhap', COUNT(*) FROM phieunhap
UNION ALL SELECT 'phieuthu', COUNT(*) FROM phieuthu
ORDER BY 1;

-- Kiem tra tinh nhat quan: dia chi khach co thuc su nam trong quan da luu?
-- (ket qua nen la 0 hoac rat nho, sai lech chi do diem sat ranh gioi)
SELECT COUNT(*) AS dia_chi_sai_quan
FROM diachi_khachhang dc
JOIN quan_huyen q ON q.ma_quan = dc.ma_quan
WHERE NOT ST_Within(dc.vi_tri, q.ranh_gioi);

-- =====================================================
-- SAU KHI CHAY XONG:
--  * Chay lai cac truy van o muc 7 cua spatial_retail_postgis.sql
--    (7.3: nen tang ban kinh len 5000 m vi shipper rai khap thanh pho)
--  * Muc 8: BO QUA 8.1 (khong sinh diem ngau nhien nua, da co ~600k diem GPS).
--    Chay 8.2 -> 8.3 (tao GiST index) -> 8.4 de so sanh hieu nang.
-- =====================================================