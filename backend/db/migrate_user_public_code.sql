ALTER TABLE users
  ADD COLUMN public_code VARCHAR(64) NULL AFTER provider_user_id;

UPDATE users
   SET public_code = LOWER(REPLACE(UUID(), '-', ''))
 WHERE public_code IS NULL
    OR public_code = '';

ALTER TABLE users
  MODIFY public_code VARCHAR(64) NOT NULL,
  ADD UNIQUE KEY uniq_user_public_code (public_code);
