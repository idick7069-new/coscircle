export const sharedLocationsQuery = `SELECT shared_locations.user_id AS userId,
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              event_bookings.role,
              shared_locations.day_index AS dayIndex,
              works.id AS workId,
              works.name AS workName,
              event_bookings.character_name AS characterName,
              event_bookings.outfit_image_url AS outfitImageUrl,
              event_bookings.interaction_tags AS interactionTags,
              event_bookings.available_time AS availableTime,
              event_bookings.presence_status AS presenceStatus,
              shared_locations.latitude,
              shared_locations.longitude,
              shared_locations.visibility,
              UNIX_TIMESTAMP(shared_locations.shared_at) AS sharedAtEpoch,
              UNIX_TIMESTAMP(shared_locations.expires_at) AS expiresAtEpoch,
              DATE_FORMAT(shared_locations.shared_at, '%Y-%m-%dT%H:%i:%s') AS sharedAt,
              DATE_FORMAT(shared_locations.expires_at, '%Y-%m-%dT%H:%i:%s') AS expiresAt,
              CASE WHEN shared_locations.user_id = ? THEN TRUE ELSE FALSE END AS isMe,
              CASE WHEN follows.followed_user_id IS NULL THEN FALSE ELSE TRUE END AS isFollowed,
              CASE WHEN circle_members.user_id IS NULL THEN FALSE ELSE TRUE END AS isCircleMember,
              EXISTS (SELECT 1 FROM friendships f WHERE f.status='accepted'
                AND f.user_low_id=LEAST(shared_locations.user_id, ?)
                AND f.user_high_id=GREATEST(shared_locations.user_id, ?)) AS isFriend
         FROM shared_locations
         INNER JOIN users
           ON users.id = shared_locations.user_id
         LEFT JOIN event_bookings
           ON event_bookings.event_id = shared_locations.event_id
          AND event_bookings.user_id = shared_locations.user_id
          AND event_bookings.day_index = shared_locations.day_index
         LEFT JOIN works
           ON works.id = event_bookings.work_id
         LEFT JOIN follows
           ON follows.follower_user_id = ?
          AND follows.followed_user_id = shared_locations.user_id
         LEFT JOIN user_blocks AS my_blocks
           ON my_blocks.blocker_user_id = ?
          AND my_blocks.blocked_user_id = shared_locations.user_id
         LEFT JOIN user_blocks AS their_blocks
           ON their_blocks.blocker_user_id = shared_locations.user_id
          AND their_blocks.blocked_user_id = ?
         LEFT JOIN (
           SELECT DISTINCT event_id, user_id, day_index
             FROM event_bookings
            WHERE user_id = ?
         ) AS viewer_bookings
           ON viewer_bookings.event_id = shared_locations.event_id
          AND viewer_bookings.day_index = shared_locations.day_index
         LEFT JOIN (
           SELECT DISTINCT other_members.user_id
             FROM circle_members AS other_members
             INNER JOIN circle_members AS my_members
               ON my_members.circle_id = other_members.circle_id
              AND my_members.user_id = ?
         ) AS circle_members ON circle_members.user_id = shared_locations.user_id
        WHERE shared_locations.event_id = ?
          AND (
            shared_locations.expires_at IS NULL
            OR shared_locations.expires_at > CURRENT_TIMESTAMP
          )
          AND (
            shared_locations.user_id = ?
            OR (
              my_blocks.blocked_user_id IS NULL
              AND their_blocks.blocker_user_id IS NULL
              AND (
                (
                  shared_locations.visibility = 'circle'
                  AND circle_members.user_id IS NOT NULL
                )
                OR (
                  shared_locations.visibility = 'followed'
                  AND follows.followed_user_id IS NOT NULL
                )
                OR (
                  shared_locations.visibility = 'public'
                  AND viewer_bookings.user_id IS NOT NULL
                )
              )
            )
          )
        ORDER BY shared_locations.shared_at DESC`;

export const updateLocationCoordinatesQuery = `UPDATE shared_locations SET latitude=?, longitude=?, shared_at=CURRENT_TIMESTAMP
  WHERE event_id=? AND user_id=? AND day_index=?
    AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)`;
