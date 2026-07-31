DELIMITER //

DROP PROCEDURE IF EXISTS add_column_if_missing//
DROP PROCEDURE IF EXISTS modify_column_if_exists//

CREATE PROCEDURE add_column_if_missing(
  IN table_name_input VARCHAR(64),
  IN column_name_input VARCHAR(64),
  IN alter_sql_input TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = table_name_input
       AND COLUMN_NAME = column_name_input
  ) THEN
    SET @alter_sql = alter_sql_input;
    PREPARE stmt FROM @alter_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END//

CREATE PROCEDURE modify_column_if_exists(
  IN table_name_input VARCHAR(64),
  IN column_name_input VARCHAR(64),
  IN alter_sql_input TEXT
)
BEGIN
  IF EXISTS (
    SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = table_name_input
       AND COLUMN_NAME = column_name_input
  ) THEN
    SET @alter_sql = alter_sql_input;
    PREPARE stmt FROM @alter_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END//

CALL add_column_if_missing(
  'users',
  'account_status',
  'ALTER TABLE users ADD COLUMN account_status ENUM(''active'',''suspended'') NOT NULL DEFAULT ''active'' AFTER is_admin'
)//

CALL modify_column_if_exists(
  'event_recognition_requests',
  'status',
  'ALTER TABLE event_recognition_requests MODIFY COLUMN status ENUM(''pending'',''come'',''busy'',''accepted'',''declined'',''expired'',''cancelled'') NOT NULL DEFAULT ''pending'''
)//

UPDATE event_recognition_requests
   SET status = 'accepted'
 WHERE status = 'come'//

UPDATE event_recognition_requests
   SET status = 'declined'
 WHERE status = 'busy'//

CALL modify_column_if_exists(
  'event_recognition_requests',
  'status',
  'ALTER TABLE event_recognition_requests MODIFY COLUMN status ENUM(''pending'',''accepted'',''declined'',''expired'',''cancelled'') NOT NULL DEFAULT ''pending'''
)//

CALL add_column_if_missing(
  'event_recognition_requests',
  'day_index',
  'ALTER TABLE event_recognition_requests ADD COLUMN day_index INT UNSIGNED NOT NULL DEFAULT 1 AFTER event_id'
)//

CALL add_column_if_missing(
  'shared_locations',
  'day_index',
  'ALTER TABLE shared_locations ADD COLUMN day_index INT UNSIGNED NOT NULL DEFAULT 1 AFTER event_id'
)//

CALL add_column_if_missing(
  'event_recognition_requests',
  'expires_at',
  'ALTER TABLE event_recognition_requests ADD COLUMN expires_at TIMESTAMP NULL AFTER created_at'
)//

CREATE TABLE IF NOT EXISTS source_sync_runs (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  source_key VARCHAR(80) NOT NULL,
  source_url TEXT NOT NULL,
  status ENUM('success','failure') NOT NULL,
  imported_count INT UNSIGNED NOT NULL DEFAULT 0,
  error_code VARCHAR(80) NULL,
  error_message TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_source_sync_runs_source_created (source_key, created_at),
  KEY idx_source_sync_runs_status_created (status, created_at)
)//

CREATE TABLE IF NOT EXISTS device_push_tokens (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  platform ENUM('android','ios','web') NOT NULL,
  token VARCHAR(512) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_device_push_token (token),
  KEY idx_device_push_tokens_user (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)//

DROP PROCEDURE add_column_if_missing//
DROP PROCEDURE modify_column_if_exists//

DELIMITER ;
