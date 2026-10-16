export const eventListQuery = `SELECT events.id, events.category, events.name,
              DATE_FORMAT(events.start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(events.end_date, '%Y-%m-%d') AS endDate,
              events.venue, events.detailed_address AS detailedAddress,
              events.fee, events.organizer, events.description,
              events.image_url AS imageUrl,
              events.source_type AS sourceType,
              events.source_name AS sourceName,
              events.source_url AS sourceUrl,
              CASE WHEN my_bookings.event_id IS NULL THEN FALSE ELSE TRUE END AS isJoined,
              COALESCE(my_bookings.joined_day_indexes, '') AS joinedDayIndexes,
              CASE WHEN followed_bookings.event_id IS NULL THEN FALSE ELSE TRUE END AS hasFollowedParticipants,
              CASE WHEN circle_bookings.event_id IS NULL THEN FALSE ELSE TRUE END AS hasCircleMembers,
              COALESCE(followed_bookings.day_indexes, '') AS followedDayIndexes,
              COALESCE(circle_bookings.day_indexes, '') AS circleDayIndexes,
              CASE WHEN friend_bookings.event_id IS NULL THEN FALSE ELSE TRUE END AS hasFriends,
              COALESCE(friend_bookings.day_indexes, '') AS friendDayIndexes
         FROM events
         LEFT JOIN (
           SELECT event_id,
                  GROUP_CONCAT(day_index ORDER BY day_index SEPARATOR ',') AS joined_day_indexes
             FROM event_bookings
            WHERE user_id = ?
            GROUP BY event_id
         ) AS my_bookings
           ON my_bookings.event_id = events.id
         LEFT JOIN (
           SELECT event_bookings.event_id,
                  GROUP_CONCAT(DISTINCT event_bookings.day_index ORDER BY event_bookings.day_index) AS day_indexes
             FROM event_bookings
             INNER JOIN users AS booking_users
               ON booking_users.id = event_bookings.user_id
             INNER JOIN follows
               ON follows.followed_user_id = event_bookings.user_id
              AND follows.follower_user_id = ?
              LEFT JOIN user_blocks AS my_blocks
                ON my_blocks.blocker_user_id = ?
               AND my_blocks.blocked_user_id = event_bookings.user_id
              LEFT JOIN user_blocks AS their_blocks
                ON their_blocks.blocker_user_id = event_bookings.user_id
               AND their_blocks.blocked_user_id = ?
            WHERE event_bookings.user_id <> ?
              AND my_blocks.blocked_user_id IS NULL
              AND their_blocks.blocker_user_id IS NULL
              AND (
                booking_users.booking_visibility = 'public'
                OR EXISTS (
                  SELECT 1
                    FROM circle_members AS my_visibility_circles
                    INNER JOIN circle_members AS booking_visibility_circles
                      ON booking_visibility_circles.circle_id = my_visibility_circles.circle_id
                     AND booking_visibility_circles.user_id = event_bookings.user_id
                   WHERE my_visibility_circles.user_id = ?
                   LIMIT 1
                )
              )
            GROUP BY event_bookings.event_id
         ) AS followed_bookings
           ON followed_bookings.event_id = events.id
         LEFT JOIN (
           SELECT event_bookings.event_id,
                  GROUP_CONCAT(DISTINCT event_bookings.day_index ORDER BY event_bookings.day_index) AS day_indexes
             FROM event_bookings
             INNER JOIN users AS booking_users
               ON booking_users.id = event_bookings.user_id
             INNER JOIN circle_members AS other_members
               ON other_members.user_id = event_bookings.user_id
             INNER JOIN circle_members AS my_members
               ON my_members.circle_id = other_members.circle_id
              AND my_members.user_id = ?
             LEFT JOIN user_blocks AS my_blocks
               ON my_blocks.blocker_user_id = ?
              AND my_blocks.blocked_user_id = event_bookings.user_id
             LEFT JOIN user_blocks AS their_blocks
               ON their_blocks.blocker_user_id = event_bookings.user_id
              AND their_blocks.blocked_user_id = ?
            WHERE event_bookings.user_id <> ?
              AND booking_users.booking_visibility IN ('public', 'circle')
              AND my_blocks.blocked_user_id IS NULL
              AND their_blocks.blocker_user_id IS NULL
            GROUP BY event_bookings.event_id
         ) AS circle_bookings
           ON circle_bookings.event_id = events.id
         LEFT JOIN (
           SELECT b.event_id, GROUP_CONCAT(DISTINCT b.day_index ORDER BY b.day_index) AS day_indexes
             FROM event_bookings b INNER JOIN users u ON u.id=b.user_id
             INNER JOIN friendships f ON f.user_low_id=LEAST(b.user_id, ?) AND f.user_high_id=GREATEST(b.user_id, ?)
               AND f.status='accepted'
            WHERE b.user_id<>? AND u.account_status='active'
              AND NOT EXISTS (SELECT 1 FROM user_blocks blocks WHERE
                (blocks.blocker_user_id=? AND blocks.blocked_user_id=b.user_id)
                OR (blocks.blocker_user_id=b.user_id AND blocks.blocked_user_id=?))
              AND (u.booking_visibility='public' OR EXISTS (
                SELECT 1 FROM circle_members mine INNER JOIN circle_members theirs ON theirs.circle_id=mine.circle_id
                  AND theirs.user_id=b.user_id WHERE mine.user_id=?))
            GROUP BY b.event_id
         ) AS friend_bookings ON friend_bookings.event_id=events.id
        WHERE events.status = 'approved'
        ORDER BY events.start_date ASC`;
