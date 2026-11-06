CREATE TABLE IF NOT EXISTS user_legal_consents (
  user_id BIGINT UNSIGNED NOT NULL,
  version VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, version),
  CONSTRAINT fk_legal_consent_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
