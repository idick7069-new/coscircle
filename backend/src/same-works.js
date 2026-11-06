import {registerPartnerDiscoveryRoutes} from './partner-discovery.js';

export const sameWorkUsersQuery = `
  SELECT u.id AS userId, u.public_code AS publicCode, u.nickname,
         u.avatar_url AS avatarUrl, u.bio,
         COUNT(DISTINCT mine.work_id) AS commonWorkCount
    FROM user_pit_works mine
    INNER JOIN user_pit_works theirs ON theirs.work_id = mine.work_id
      AND theirs.user_id <> mine.user_id
    INNER JOIN users u ON u.id = theirs.user_id
   WHERE mine.user_id = ?
     AND u.account_status = 'active'
     AND u.public_code IS NOT NULL AND u.public_code <> ''
     AND NOT EXISTS (
       SELECT 1 FROM user_blocks b
        WHERE (b.blocker_user_id = ? AND b.blocked_user_id = u.id)
           OR (b.blocker_user_id = u.id AND b.blocked_user_id = ?)
     )
   GROUP BY u.id, u.public_code, u.nickname, u.avatar_url, u.bio
   ORDER BY commonWorkCount DESC, u.id ASC
   LIMIT ? OFFSET ?`;

export function sameWorksQuery(userCount) {
  return `SELECT DISTINCT theirs.user_id AS userId, w.id, w.name
    FROM user_pit_works mine
    INNER JOIN user_pit_works theirs ON theirs.work_id = mine.work_id
    INNER JOIN works w ON w.id = mine.work_id
    WHERE mine.user_id = ? AND theirs.user_id IN (${Array(userCount).fill('?').join(',')})
    ORDER BY theirs.user_id ASC, w.name ASC, w.id ASC`;
}

function pageNumber(value, fallback, max, minimum) {
  if (value === undefined) return fallback;
  if (typeof value !== 'string' || !/^\d+$/.test(value)) {
    throw Object.assign(new Error('invalid_pagination'), {status: 400});
  }
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > max) {
    throw Object.assign(new Error('invalid_pagination'), {status: 400});
  }
  return number;
}

export async function listSameWorkUsers(pool, viewerId, query = {}) {
  const limit = pageNumber(query.limit, 20, 50, 1);
  const offset = pageNumber(query.offset, 0, 100000, 0);
  const [rows] = await pool.execute(sameWorkUsersQuery, [viewerId, viewerId, viewerId, limit + 1, offset]);
  const selected = rows.slice(0, limit);
  const hasMore = rows.length > limit;
  if (!selected.length) return {items: [], hasMore: false, nextOffset: null};
  const [works] = await pool.execute(sameWorksQuery(selected.length), [viewerId, ...selected.map((row) => row.userId)]);
  const byUser = new Map();
  for (const work of works) {
    const id = String(work.userId);
    if (!byUser.has(id)) byUser.set(id, []);
    byUser.get(id).push({id: String(work.id), name: work.name});
  }
  return {
    items: selected.map((row) => ({
      userId: String(row.userId), publicCode: row.publicCode,
      nickname: row.nickname, avatarUrl: row.avatarUrl ?? '', bio: row.bio ?? '',
      commonWorkCount: Number(row.commonWorkCount), commonWorks: byUser.get(String(row.userId)) ?? [],
    })),
    hasMore,
    nextOffset: hasMore ? offset + selected.length : null,
  };
}

export function registerSameWorkRoutes(app, pool) {
  registerPartnerDiscoveryRoutes(app, pool);
  app.get('/api/social/same-works', async (req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    try {
      res.json(await listSameWorkUsers(pool, req.userId, req.query));
    } catch (error) {
      if (error.status === 400) res.status(400).json({error: error.message});
      else next(error);
    }
  });
}
