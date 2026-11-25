-- Run once after a full backup. Existing client tokens remain usable, stored only as digests.
ALTER TABLE users ADD COLUMN is_test_account BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN can_view_test_data BOOLEAN NOT NULL DEFAULT FALSE,
 ADD COLUMN session_expires_at DATETIME NULL;
ALTER TABLE events ADD COLUMN is_test_event BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE circles ADD COLUMN is_test_circle BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE works ADD COLUMN is_test_work BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE users SET session_token=CONCAT('sha256:',SHA2(session_token,256)),
 session_expires_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY)
 WHERE session_token IS NOT NULL AND session_token NOT LIKE 'sha256:%';
