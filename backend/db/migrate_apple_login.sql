-- Native iOS Sign in with Apple; encrypted refresh tokens, never raw credentials.
CREATE TABLE IF NOT EXISTS apple_auth_challenges (
    id CHAR(64) PRIMARY KEY, nonce CHAR(64) NOT NULL, purpose VARCHAR(16) NOT NULL,
    user_id BIGINT UNSIGNED NULL, session_hash CHAR(64) NULL, expires_at DATETIME NOT NULL,
    KEY idx_apple_challenge_expiry (expires_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS apple_auth_tokens (
    user_id BIGINT UNSIGNED PRIMARY KEY, refresh_token TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB;
