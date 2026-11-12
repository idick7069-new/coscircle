SET @age_visibility_sql = IF(
  EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'age_public'),
  'SELECT 1',
  'ALTER TABLE users ADD COLUMN age_public BOOLEAN NOT NULL DEFAULT TRUE AFTER age'
);
PREPARE age_visibility_statement FROM @age_visibility_sql;
EXECUTE age_visibility_statement;
DEALLOCATE PREPARE age_visibility_statement;
