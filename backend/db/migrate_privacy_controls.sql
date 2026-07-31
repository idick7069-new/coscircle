DELIMITER //

DROP PROCEDURE IF EXISTS add_column_if_missing//

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

CALL add_column_if_missing(
  'users',
  'booking_visibility',
  'ALTER TABLE users ADD COLUMN booking_visibility ENUM(''public'',''circle'') NOT NULL DEFAULT ''public'' AFTER other_photo_urls_json'
)//

CALL add_column_if_missing(
  'shared_locations',
  'visibility',
  'ALTER TABLE shared_locations ADD COLUMN visibility ENUM(''public'',''followed'',''circle'') NOT NULL DEFAULT ''circle'' AFTER longitude'
)//

CALL add_column_if_missing(
  'shared_locations',
  'expires_at',
  'ALTER TABLE shared_locations ADD COLUMN expires_at TIMESTAMP NULL AFTER shared_at'
)//

CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_user_id BIGINT UNSIGNED NOT NULL,
  blocked_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  FOREIGN KEY (blocker_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE
)//

DROP PROCEDURE add_column_if_missing//

DELIMITER ;
