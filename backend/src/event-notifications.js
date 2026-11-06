export function createEventNotifications(pool, {sendMeetupPush, sendRecognitionReplyPush}) {
  async function deliver(query, params, send, payload) {
    try {
      const [rows] = await pool.execute(query, params);
      const result = await send({...payload, tokens: rows.map(row => row.token)});
      if (result.invalidTokens.length) {
        const placeholders = result.invalidTokens.map(() => '?').join(',');
        await pool.execute(`DELETE FROM device_push_tokens WHERE token IN (${placeholders})`, result.invalidTokens);
      }
      return {sent: result.successCount, failed: result.failureCount};
    } catch {
      return {sent: 0, failed: 0, error: 'push_send_failed'};
    }
  }

  async function meetupCreated({meetupId, eventId, circleId, creatorUserId}) {
    const [[meetup]] = await pool.execute(`SELECT u.nickname AS creatorName,
        DATEDIFF(DATE(CONVERT_TZ(m.meet_at, '+00:00', '+08:00')), e.start_date) + 1 AS dayIndex
      FROM event_meeting_points m INNER JOIN users u ON u.id=m.creator_user_id
      INNER JOIN events e ON e.id=m.event_id WHERE m.id=?`, [meetupId]);
    if (!meetup) return {sent: 0, failed: 0};
    return deliver(`SELECT DISTINCT t.token FROM device_push_tokens t
      INNER JOIN users u ON u.id=t.user_id
      INNER JOIN circle_members cm ON cm.user_id=t.user_id AND cm.circle_id=?
      WHERE t.user_id<>? AND u.session_token IS NOT NULL AND u.account_status='active'
        AND NOT EXISTS (SELECT 1 FROM user_blocks b
          WHERE (b.blocker_user_id=? AND b.blocked_user_id=t.user_id)
             OR (b.blocker_user_id=t.user_id AND b.blocked_user_id=?))`,
    [circleId, creatorUserId, creatorUserId, creatorUserId], sendMeetupPush,
    {meetupId, eventId, dayIndex: meetup.dayIndex, creatorName: meetup.creatorName});
  }

  async function recognitionResponded({requestId, targetUserId, status}) {
    const [[request]] = await pool.execute(`SELECT r.event_id AS eventId, r.day_index AS dayIndex,
        r.requester_user_id AS requesterUserId, u.nickname AS responderName
      FROM event_recognition_requests r INNER JOIN users u ON u.id=r.target_user_id
      WHERE r.id=? AND r.target_user_id=? AND r.status=?`, [requestId, targetUserId, status]);
    if (!request) return {sent: 0, failed: 0};
    return deliver(`SELECT t.token FROM device_push_tokens t INNER JOIN users u ON u.id=t.user_id
      WHERE t.user_id=? AND u.session_token IS NOT NULL AND u.account_status='active'
        AND NOT EXISTS (SELECT 1 FROM user_blocks b
          WHERE (b.blocker_user_id=? AND b.blocked_user_id=?)
             OR (b.blocker_user_id=? AND b.blocked_user_id=?))`,
    [request.requesterUserId, request.requesterUserId, targetUserId, targetUserId, request.requesterUserId],
    sendRecognitionReplyPush, {requestId, ...request, status});
  }

  return {
    meetupCreated: async payload => {
      try { return await meetupCreated(payload); }
      catch { return {sent: 0, failed: 0, error: 'push_send_failed'}; }
    },
    recognitionResponded: async payload => {
      try { return await recognitionResponded(payload); }
      catch { return {sent: 0, failed: 0, error: 'push_send_failed'}; }
    },
  };
}
