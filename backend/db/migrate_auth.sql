ALTER TABLE users
  ADD COLUMN email VARCHAR(191) NULL AFTER provider_user_id,
  ADD COLUMN password_hash TEXT NULL AFTER email,
  ADD COLUMN session_token VARCHAR(191) NULL AFTER password_hash,
  ADD UNIQUE KEY uniq_user_email (email),
  ADD UNIQUE KEY uniq_session_token (session_token);
