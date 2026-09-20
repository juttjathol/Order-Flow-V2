CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  business_name TEXT,
  notes TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS licenses (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  license_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TEXT,
  bound_device_id TEXT,
  bound_at TEXT,
  last_validated_at TEXT,
  created_at TEXT NOT NULL,
  -- v1.1.59 plan & entitlements (also auto-added at runtime to old DBs)
  plan TEXT NOT NULL DEFAULT 'full',
  allowed_models TEXT,
  allowed_features TEXT,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_licenses_key ON licenses(license_key);
CREATE INDEX IF NOT EXISTS idx_licenses_customer ON licenses(customer_id);
CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses(status);

-- v1.1.60 cloud relay (transit only — never a backup). The relay function
-- creates these itself on first use; kept here for reference / fresh setups.
-- Rows are pruned on read, expire in ~30 min, and die with the room.
CREATE TABLE IF NOT EXISTS cloud_rooms (
  room TEXT PRIMARY KEY,
  secret TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  license_key TEXT,
  main_device TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS cloud_devices (
  room TEXT NOT NULL,
  device_id TEXT NOT NULL,
  role TEXT,
  name TEXT,
  cursor INTEGER NOT NULL DEFAULT 0,
  joined_at INTEGER,
  PRIMARY KEY (room, device_id)
);
CREATE TABLE IF NOT EXISTS cloud_msgs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room TEXT NOT NULL,
  sender TEXT,
  msg TEXT NOT NULL,
  created_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_cloud_msgs_room ON cloud_msgs(room, id);

-- Audit trail for bind / validate / revoke / reset (never a shop-data backup).
CREATE TABLE IF NOT EXISTS license_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  license_id TEXT,
  license_key TEXT,
  event TEXT NOT NULL,
  device_id TEXT,
  detail TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_license_events_key ON license_events(license_key, created_at);

-- Shared D1 rate-limit windows (login / license / relay). Runtime also
-- CREATE TABLE IF NOT EXISTS so existing DBs pick this up without a migration.
CREATE TABLE IF NOT EXISTS rate_limits (
  k TEXT NOT NULL,
  w INTEGER NOT NULL,
  n INTEGER NOT NULL,
  PRIMARY KEY (k, w)
);
