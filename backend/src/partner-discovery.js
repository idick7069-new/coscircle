const eligibleUser = `u.id <> ?
  AND u.account_status = 'active'
  AND u.public_code IS NOT NULL AND u.public_code <> ''
  AND NOT EXISTS (
    SELECT 1 FROM user_blocks b
    WHERE (b.blocker_user_id = ? AND b.blocked_user_id = u.id)
       OR (b.blocker_user_id = u.id AND b.blocked_user_id = ?)
  )`;

function invalid(message) {
  return Object.assign(new Error(message), {status: 400});
}

function integer(value, fallback, minimum, maximum, error = 'invalid_pagination') {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== 'string' || !value.length || /[^0-9]/.test(value)) throw invalid(error);
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) throw invalid(error);
  return number;
}

function pagination(query) {
  return {
    limit: integer(query.limit, 20, 1, 50),
    offset: integer(query.offset, 0, 0, 100000),
  };
}

function page(rows, {limit, offset}, map) {
  const selected = rows.slice(0, limit);
  const hasMore = rows.length > limit && offset + selected.length <= 100000;
  return {items: selected.map(map), hasMore, nextOffset: hasMore ? offset + selected.length : null};
}

export async function listPartnerWorks(pool, viewerId, query = {}) {
  const paging = pagination(query);
  const scope = query.scope === undefined ? 'mine' : query.scope;
  if (scope !== 'mine' && scope !== 'all') throw invalid('invalid_scope');
  const q = query.q === undefined ? '' : query.q;
  if (typeof q !== 'string' || q.length > 100) throw invalid('invalid_search');
  const pattern = `%${q.replace(/[!%_]/g, (character) => `!${character}`)}%`;
  const mine = `EXISTS (SELECT 1 FROM user_pit_works mine
    WHERE mine.user_id = ? AND mine.work_id = w.id)`;
  const sql = `SELECT w.id, w.name, COALESCE(partners.partnerCount, 0) AS partnerCount,
      ${mine} AS isMine
    FROM works w
    LEFT JOIN (
      SELECT p.work_id, COUNT(DISTINCT u.id) AS partnerCount
      FROM user_pit_works p INNER JOIN users u ON u.id = p.user_id
      WHERE ${eligibleUser}
      GROUP BY p.work_id
    ) partners ON partners.work_id = w.id
    WHERE ${scope === 'mine' ? mine : 'COALESCE(partners.partnerCount, 0) > 0'}
      AND w.name LIKE ? ESCAPE '!'
    ORDER BY w.name ASC, w.id ASC LIMIT ? OFFSET ?`;
  const params = [viewerId, viewerId, viewerId, viewerId];
  if (scope === 'mine') params.push(viewerId);
  params.push(pattern, paging.limit + 1, paging.offset);
  const [rows] = await pool.execute(sql, params);
  return page(rows, paging, (row) => ({
    id: String(row.id), name: row.name, partnerCount: Number(row.partnerCount), isMine: Boolean(Number(row.isMine)),
  }));
}

export async function listWorkPartners(pool, viewerId, workId, query = {}) {
  const id = integer(workId, undefined, 1, Number.MAX_SAFE_INTEGER, 'invalid_work_id');
  const paging = pagination(query);
  const [rows] = await pool.execute(`SELECT u.id AS userId, u.public_code AS publicCode,
      u.nickname, u.avatar_url AS avatarUrl, u.bio
    FROM users u
    WHERE ${eligibleUser}
      AND EXISTS (SELECT 1 FROM user_pit_works p
        INNER JOIN works w ON w.id = p.work_id
        WHERE p.user_id = u.id AND p.work_id = ?)
    ORDER BY u.id ASC LIMIT ? OFFSET ?`, [viewerId, viewerId, viewerId, id, paging.limit + 1, paging.offset]);
  const selected = rows.slice(0, paging.limit);
  const byUser = new Map();
  if (selected.length) {
    const [works] = await pool.execute(`SELECT DISTINCT theirs.user_id AS userId, w.id, w.name
      FROM user_pit_works mine
      INNER JOIN user_pit_works theirs ON theirs.work_id = mine.work_id
      INNER JOIN works w ON w.id = mine.work_id
      WHERE mine.user_id = ? AND theirs.user_id IN (${selected.map(() => '?').join(',')})
      ORDER BY theirs.user_id ASC, w.name ASC, w.id ASC`, [viewerId, ...selected.map((row) => row.userId)]);
    for (const work of works) {
      const userId = String(work.userId);
      if (!byUser.has(userId)) byUser.set(userId, []);
      byUser.get(userId).push({id: String(work.id), name: work.name});
    }
  }
  return page(rows, paging, (row) => {
    const commonWorks = byUser.get(String(row.userId)) ?? [];
    return {
      userId: String(row.userId), publicCode: row.publicCode, nickname: row.nickname,
      avatarUrl: row.avatarUrl ?? '', bio: row.bio ?? '',
      commonWorkCount: commonWorks.length, commonWorks,
    };
  });
}

export function registerPartnerDiscoveryRoutes(app, pool) {
  const routes = new Map([
    ['/api/social/partner-works', (req) => listPartnerWorks(pool, req.userId, req.query)],
    ['/api/social/partner-works/:workId/users', (req) => listWorkPartners(pool, req.userId, req.params.workId, req.query)],
  ]);
  for (const [path, list] of routes) {
    app.get(path, async (req, res, next) => {
      res.set('Cache-Control', 'private, no-store');
      try {
        res.json(await list(req));
      } catch (error) {
        if (error.status === 400) res.status(400).json({error: error.message});
        else next(error);
      }
    });
  }
}
