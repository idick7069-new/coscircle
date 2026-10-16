CREATE TABLE IF NOT EXISTS event_sync_jobs (
  id VARCHAR(36) PRIMARY KEY,
  scheduled_date DATE NULL,
  status ENUM('running','success','partial','failure') NOT NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 1,
  sources_json JSON NULL,
  error_code VARCHAR(80) NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NULL,
  UNIQUE KEY uniq_event_sync_daily (scheduled_date),
  KEY idx_event_sync_status (status, started_at)
);

CREATE TABLE IF NOT EXISTS event_source_snapshots (
  source_key VARCHAR(80) PRIMARY KEY,
  events_json JSON NOT NULL,
  fetched_at DATETIME NOT NULL
);
