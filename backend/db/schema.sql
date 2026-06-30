CREATE TABLE users (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  provider VARCHAR(32) NOT NULL,
  provider_user_id VARCHAR(191) NOT NULL,
  public_code VARCHAR(64) NOT NULL,
  email VARCHAR(191) NULL,
  password_hash TEXT NULL,
  session_token VARCHAR(191) NULL,
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  nickname VARCHAR(80) NOT NULL,
  avatar_url TEXT NULL,
  facebook_url TEXT NULL,
  bio TEXT NULL,
  age VARCHAR(40) NULL,
  regions_json TEXT NULL,
  travel_regions_json TEXT NULL,
  travel_same_region BOOLEAN NOT NULL DEFAULT FALSE,
  landmine TEXT NULL,
  gender VARCHAR(40) NOT NULL DEFAULT 'private',
  other_photo_urls_json TEXT NULL,
  booking_visibility ENUM('public','circle') NOT NULL DEFAULT 'public',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_provider_user (provider, provider_user_id),
  UNIQUE KEY uniq_user_public_code (public_code),
  UNIQUE KEY uniq_user_email (email),
  UNIQUE KEY uniq_session_token (session_token)
);

CREATE TABLE works (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_work_name (name)
);

CREATE TABLE user_pit_works (
  user_id BIGINT UNSIGNED NOT NULL,
  work_id BIGINT UNSIGNED NOT NULL,
  depth ENUM('deep','shallow') NOT NULL DEFAULT 'deep',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, work_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE CASCADE
);

CREATE TABLE events (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  source_key VARCHAR(191) UNIQUE NULL,
  source_type TINYINT UNSIGNED NOT NULL DEFAULT 1,
  source_name VARCHAR(80) NOT NULL DEFAULT '同人誌中心',
  source_url TEXT NULL,
  image_url TEXT NULL,
  category VARCHAR(80) NOT NULL,
  name VARCHAR(255) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  venue VARCHAR(255) NOT NULL,
  detailed_address TEXT NULL,
  fee VARCHAR(80) NULL,
  organizer VARCHAR(255) NULL,
  description TEXT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'approved',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE event_bookings (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  event_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  day_index INT UNSIGNED NOT NULL DEFAULT 1,
  role ENUM('photographer','coser','manager','self') NOT NULL,
  work_id BIGINT UNSIGNED NULL,
  character_name VARCHAR(120) NULL,
  outfit_image_url TEXT NULL,
  interaction_tags TEXT NULL,
  available_time VARCHAR(120) NULL,
  presence_status VARCHAR(40) NOT NULL DEFAULT 'open',
  message TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_event_user_day (event_id, user_id, day_index),
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (work_id) REFERENCES works(id) ON DELETE SET NULL
);

CREATE TABLE follows (
  follower_user_id BIGINT UNSIGNED NOT NULL,
  followed_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (follower_user_id, followed_user_id),
  FOREIGN KEY (follower_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (followed_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE user_blocks (
  blocker_user_id BIGINT UNSIGNED NOT NULL,
  blocked_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  FOREIGN KEY (blocker_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE circles (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  owner_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(120) NOT NULL,
  description TEXT NULL,
  invite_code VARCHAR(40) NOT NULL UNIQUE,
  invite_url TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE circle_members (
  circle_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (circle_id, user_id),
  FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE shared_locations (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  event_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  latitude DECIMAL(10, 7) NOT NULL,
  longitude DECIMAL(10, 7) NOT NULL,
  shared_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_latest_location (event_id, user_id),
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE event_meeting_points (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  event_id BIGINT UNSIGNED NOT NULL,
  circle_id BIGINT UNSIGNED NOT NULL,
  creator_user_id BIGINT UNSIGNED NOT NULL,
  latitude DECIMAL(10, 7) NOT NULL,
  longitude DECIMAL(10, 7) NOT NULL,
  description TEXT NULL,
  meet_at DATETIME NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE,
  FOREIGN KEY (creator_user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_event_meeting_points_event (event_id),
  KEY idx_event_meeting_points_circle (circle_id)
);

CREATE TABLE event_recognition_requests (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  event_id BIGINT UNSIGNED NOT NULL,
  requester_user_id BIGINT UNSIGNED NOT NULL,
  target_user_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending','come','busy') NOT NULL DEFAULT 'pending',
  response_message VARCHAR(80) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  responded_at TIMESTAMP NULL,
  FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  FOREIGN KEY (requester_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_event_recognition_event (event_id),
  KEY idx_event_recognition_target (target_user_id),
  KEY idx_event_recognition_requester (requester_user_id)
);

CREATE TABLE event_submissions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  submitter_user_id BIGINT UNSIGNED NULL,
  name VARCHAR(255) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  venue VARCHAR(255) NOT NULL,
  detailed_address TEXT NULL,
  description TEXT NULL,
  review_status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (submitter_user_id) REFERENCES users(id) ON DELETE SET NULL
);
