CREATE TABLE lightmesh_networks (
  code CHAR(6) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  relay VARCHAR(512) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (code),
  UNIQUE KEY lightmesh_networks_relay_key (relay)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
