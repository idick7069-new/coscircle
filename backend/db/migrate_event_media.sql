ALTER TABLE events
  ADD COLUMN source_type TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER source_key,
  ADD COLUMN source_name VARCHAR(80) NOT NULL DEFAULT '同人誌中心' AFTER source_type,
  ADD COLUMN source_url TEXT NULL AFTER source_name,
  ADD COLUMN image_url TEXT NULL AFTER source_url;
