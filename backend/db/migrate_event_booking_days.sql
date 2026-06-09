DELIMITER //

DROP PROCEDURE IF EXISTS add_column_if_missing//
DROP PROCEDURE IF EXISTS drop_index_if_exists//
DROP PROCEDURE IF EXISTS add_index_if_missing//

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

CREATE PROCEDURE drop_index_if_exists(
  IN table_name_input VARCHAR(64),
  IN index_name_input VARCHAR(64)
)
BEGIN
  IF EXISTS (
    SELECT 1
      FROM INFORMATION_SCHEMA.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = table_name_input
       AND INDEX_NAME = index_name_input
  ) THEN
    SET @alter_sql = CONCAT('ALTER TABLE ', table_name_input, ' DROP INDEX ', index_name_input);
    PREPARE stmt FROM @alter_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END//

CREATE PROCEDURE add_index_if_missing(
  IN table_name_input VARCHAR(64),
  IN index_name_input VARCHAR(64),
  IN alter_sql_input TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM INFORMATION_SCHEMA.STATISTICS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = table_name_input
       AND INDEX_NAME = index_name_input
  ) THEN
    SET @alter_sql = alter_sql_input;
    PREPARE stmt FROM @alter_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END//

CALL add_column_if_missing(
  'event_bookings',
  'day_index',
  'ALTER TABLE event_bookings ADD COLUMN day_index INT UNSIGNED NOT NULL DEFAULT 1 AFTER user_id'
)//

CALL add_index_if_missing(
  'event_bookings',
  'idx_event_bookings_event_id',
  'ALTER TABLE event_bookings ADD INDEX idx_event_bookings_event_id (event_id)'
)//

CALL add_index_if_missing(
  'event_bookings',
  'idx_event_bookings_user_id',
  'ALTER TABLE event_bookings ADD INDEX idx_event_bookings_user_id (user_id)'
)//

CALL drop_index_if_exists('event_bookings', 'uniq_event_user')//

CALL add_index_if_missing(
  'event_bookings',
  'uniq_event_user_day',
  'ALTER TABLE event_bookings ADD UNIQUE KEY uniq_event_user_day (event_id, user_id, day_index)'
)//

DROP PROCEDURE add_column_if_missing//
DROP PROCEDURE drop_index_if_exists//
DROP PROCEDURE add_index_if_missing//

DELIMITER ;
