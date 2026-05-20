ALTER TABLE users
  ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE AFTER session_token;

UPDATE users
   SET is_admin = TRUE
 WHERE id = 1;
