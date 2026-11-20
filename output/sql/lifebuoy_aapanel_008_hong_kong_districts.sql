-- Select the Lifebuoy database in aaPanel and apply migrations 001 through 007 first.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO communities (id, name) VALUES
  ('hk-central-western', '中西區'),
  ('hk-eastern', '東區'),
  ('hk-southern', '南區'),
  ('hk-wan-chai', '灣仔區'),
  ('hk-kowloon-city', '九龍城區'),
  ('hk-yau-tsim-mong', '油尖旺區'),
  ('hk-sham-shui-po', '深水埗區'),
  ('hk-wong-tai-sin', '黃大仙區'),
  ('hk-kwun-tong', '觀塘區'),
  ('hk-tai-po', '大埔區'),
  ('hk-yuen-long', '元朗區'),
  ('hk-tuen-mun', '屯門區'),
  ('hk-north', '北區'),
  ('hk-sai-kung', '西貢區'),
  ('hk-sha-tin', '沙田區'),
  ('hk-tsuen-wan', '荃灣區'),
  ('hk-kwai-tsing', '葵青區'),
  ('hk-islands', '離島區')
ON DUPLICATE KEY UPDATE name = communities.name;

INSERT INTO lifebuoy_migrations (version, checksum)
VALUES ('008_hong_kong_districts.sql', 'b24b5617391a528095e56fa35e0c7b515b1b586c80002a55e786f467973a00f7')
ON DUPLICATE KEY UPDATE version = lifebuoy_migrations.version;
