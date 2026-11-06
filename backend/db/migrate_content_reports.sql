-- Personal evidence expires after 90 days and is erased immediately on account deletion.
CREATE TABLE IF NOT EXISTS content_reports (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  reporter_user_id BIGINT UNSIGNED NULL,
  target_type ENUM('user','booking','circle') NOT NULL,
  target_user_id BIGINT UNSIGNED NULL,
  event_id BIGINT UNSIGNED NULL,
  day_index INT UNSIGNED NULL,
  circle_id BIGINT UNSIGNED NULL,
  target_booking_id BIGINT UNSIGNED NULL,
  reason ENUM('spam','harassment','sexual_content','hate','impersonation','privacy','other') NOT NULL,
  details VARCHAR(1000) NULL,
  target_snapshot JSON NULL,
  target_fingerprint CHAR(64) NULL,
  status ENUM('pending','reviewing','resolved','dismissed') NOT NULL DEFAULT 'pending',
  version INT UNSIGNED NOT NULL DEFAULT 1,
  evidence_expires_at DATETIME NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_content_reports_queue (status, id),
  KEY idx_content_reports_reporter (reporter_user_id, created_at),
  KEY idx_content_reports_target (target_user_id),
  KEY idx_content_reports_expiry (evidence_expires_at),
  CONSTRAINT fk_content_reports_reporter FOREIGN KEY (reporter_user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_content_reports_target FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_content_reports_event FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL,
  CONSTRAINT fk_content_reports_circle FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE SET NULL,
  CONSTRAINT fk_content_reports_booking FOREIGN KEY (target_booking_id) REFERENCES event_bookings(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS content_report_reviews (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  report_id BIGINT UNSIGNED NOT NULL,
  admin_user_id BIGINT UNSIGNED NULL,
  from_status ENUM('pending','reviewing','resolved','dismissed') NOT NULL,
  to_status ENUM('pending','reviewing','resolved','dismissed') NOT NULL,
  action ENUM('none','suspend_user','remove_booking','remove_circle') NOT NULL,
  note VARCHAR(1000) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_content_report_reviews_report (report_id, id),
  CONSTRAINT fk_content_report_reviews_report FOREIGN KEY (report_id) REFERENCES content_reports(id) ON DELETE CASCADE,
  CONSTRAINT fk_content_report_reviews_admin FOREIGN KEY (admin_user_id) REFERENCES users(id) ON DELETE SET NULL
);
