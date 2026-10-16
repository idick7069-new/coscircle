CREATE TABLE IF NOT EXISTS email_action_tokens (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  identity_id BIGINT UNSIGNED NOT NULL,
  kind VARCHAR(32) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  email_snapshot VARCHAR(191) NOT NULL,
  created_at_ms BIGINT UNSIGNED NOT NULL,
  expires_at_ms BIGINT UNSIGNED NOT NULL,
  consumed_at_ms BIGINT UNSIGNED NULL,
  UNIQUE KEY uniq_email_action_hash (token_hash),
  KEY idx_email_action_identity_time (identity_id, kind, created_at_ms),
  CONSTRAINT fk_email_action_identity FOREIGN KEY (identity_id) REFERENCES user_auth_identities(id) ON DELETE CASCADE
);
