DELIMITER //

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
  'age',
  'ALTER TABLE users ADD COLUMN age VARCHAR(40) NULL AFTER bio'
)//

CALL add_column_if_missing(
  'users',
  'regions_json',
  'ALTER TABLE users ADD COLUMN regions_json TEXT NULL AFTER age'
)//

CALL add_column_if_missing(
  'users',
  'travel_same_region',
  'ALTER TABLE users ADD COLUMN travel_same_region BOOLEAN NOT NULL DEFAULT FALSE AFTER regions_json'
)//

CALL add_column_if_missing(
  'users',
  'travel_regions_json',
  'ALTER TABLE users ADD COLUMN travel_regions_json TEXT NULL AFTER regions_json'
)//

CALL add_column_if_missing(
  'users',
  'landmine',
  'ALTER TABLE users ADD COLUMN landmine TEXT NULL AFTER travel_same_region'
)//

CALL add_column_if_missing(
  'users',
  'gender',
  'ALTER TABLE users ADD COLUMN gender VARCHAR(40) NOT NULL DEFAULT ''private'' AFTER landmine'
)//

CALL add_column_if_missing(
  'users',
  'other_photo_urls_json',
  'ALTER TABLE users ADD COLUMN other_photo_urls_json TEXT NULL AFTER gender'
)//

CALL add_column_if_missing(
  'user_pit_works',
  'depth',
  'ALTER TABLE user_pit_works ADD COLUMN depth ENUM(''deep'',''shallow'') NOT NULL DEFAULT ''deep'' AFTER work_id'
)//

DROP PROCEDURE add_column_if_missing//

DELIMITER ;
