ALTER TABLE events
  ADD COLUMN detailed_address TEXT NULL AFTER venue;

UPDATE events
   SET detailed_address = venue
 WHERE detailed_address IS NULL OR detailed_address = '';

ALTER TABLE event_submissions
  ADD COLUMN detailed_address TEXT NULL AFTER venue;

UPDATE event_submissions
   SET detailed_address = venue
 WHERE detailed_address IS NULL OR detailed_address = '';

ALTER TABLE event_bookings
  MODIFY role ENUM('photographer','coser','manager','self') NOT NULL;
