CREATE TABLE IF NOT EXISTS user_auth_identities (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(32) NOT NULL,
  provider_user_id VARCHAR(191) NOT NULL,
  password_hash TEXT NULL,
  verified_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_auth_provider_subject (provider, provider_user_id),
  UNIQUE KEY uniq_auth_user_provider (user_id, provider),
  CONSTRAINT fk_auth_identity_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT IGNORE INTO user_auth_identities (user_id,provider,provider_user_id,password_hash)
SELECT id,provider,provider_user_id,CASE WHEN provider='email' THEN password_hash ELSE NULL END
FROM users;
