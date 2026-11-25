ALTER TABLE line_web_logins
  ADD COLUMN purpose ENUM('login','link') NOT NULL DEFAULT 'login',
  ADD COLUMN link_user_id BIGINT UNSIGNED NULL,
  ADD COLUMN link_session_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL;
