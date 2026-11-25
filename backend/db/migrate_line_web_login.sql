CREATE TABLE IF NOT EXISTS line_web_logins (
  id CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
  state_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  browser_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  verifier VARCHAR(128) CHARACTER SET ascii NULL,
  nonce VARCHAR(128) CHARACTER SET ascii NULL,
  return_path VARCHAR(1024) NOT NULL DEFAULT '/',
  purpose ENUM('login','link') NOT NULL DEFAULT 'login',
  link_user_id BIGINT UNSIGNED NULL,
  link_session_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
  phase ENUM('pending','exchanging','complete','failed') NOT NULL DEFAULT 'pending',
  profile_json JSON NULL,
  expires_at DATETIME NOT NULL,
  KEY idx_line_web_expiry (expires_at)
) ENGINE=InnoDB;
