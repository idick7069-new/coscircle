ALTER TABLE event_bookings
  ADD COLUMN interaction_tags TEXT NULL AFTER outfit_image_url,
  ADD COLUMN available_time VARCHAR(120) NULL AFTER interaction_tags,
  ADD COLUMN presence_status VARCHAR(40) NOT NULL DEFAULT 'open' AFTER available_time;
