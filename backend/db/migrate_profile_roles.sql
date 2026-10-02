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
  'profile_roles_json',
  'ALTER TABLE users ADD COLUMN profile_roles_json TEXT NULL AFTER gender'
)//

DROP PROCEDURE add_column_if_missing//

DELIMITER ;
