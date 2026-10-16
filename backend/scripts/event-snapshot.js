import { load } from 'cheerio';

export const sourceSnapshotsTableSql = `CREATE TABLE IF NOT EXISTS event_source_snapshots (
  source_key VARCHAR(80) PRIMARY KEY, events_json JSON NOT NULL, fetched_at DATETIME NOT NULL
)`;

export async function saveDoujinSnapshot(db, events) {
  await db.execute(`INSERT INTO event_source_snapshots (source_key,events_json,fetched_at)
    VALUES ('doujin-source',?,UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE
    events_json=VALUES(events_json), fetched_at=VALUES(fetched_at)`, [JSON.stringify(events)]);
}

function invalid(code) {
  throw Object.assign(new Error(code), { code });
}

export function validateDoujinHtml(html, events) {
  if (!/<\/html\s*>/i.test(String(html))) invalid('doujin_snapshot_truncated');
  const $ = load(html);
  const declared = [];
  const walk = (value) => {
    if (Array.isArray(value)) return value.forEach(walk);
    if (!value || typeof value !== 'object') return;
    if ([value['@type']].flat().includes('ItemList') && value.numberOfItems != null) {
      const count = Number(value.numberOfItems);
      if (!Number.isInteger(count) || count < 1) invalid('doujin_snapshot_invalid_count');
      declared.push(count);
    }
    for (const child of Object.values(value)) if (typeof child === 'object') walk(child);
  };
  $('script[type="application/ld+json"]').each((_index, element) => {
    let value;
    try { value = JSON.parse($(element).text()); }
    catch { invalid('doujin_snapshot_invalid_json'); }
    walk(value);
  });
  if (declared.some((count) => count !== events.length)) invalid('doujin_snapshot_count_mismatch');
  const urls = new Set();
  const validDate = (date) => /^\d{4}-\d{2}-\d{2}$/.test(date ?? '')
    && Number.isFinite(Date.parse(date)) && new Date(date).toISOString().slice(0, 10) === date;
  for (const event of events) {
    if (!event.name || !/^https:\/\/www\.doujin\.com\.tw\/events\/info\/\d+\/?$/.test(event.sourceUrl)
        || !validDate(event.startDate) || !validDate(event.endDate) || event.endDate < event.startDate) {
      invalid('doujin_snapshot_invalid_event');
    }
    if (urls.has(event.sourceUrl)) invalid('doujin_snapshot_duplicate_event');
    urls.add(event.sourceUrl);
  }
}

export async function validateDoujinCount(db, events) {
  const [existing] = await db.execute(`SELECT DISTINCT source_url AS sourceUrl, name FROM events
    WHERE (source_key LIKE 'doujin-%' OR source_type = 1 OR source_name = '同人誌中心')
      AND status = 'approved' AND source_url <> ''
      AND end_date >= DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00'))`);
  const incoming = new Map(events.map((event) => [event.sourceUrl, event]));
  for (const row of existing) {
    const current = incoming.get(row.sourceUrl);
    if (current && row.name && current.name !== row.name
        && events.some((other) => other.sourceUrl !== row.sourceUrl && other.name === row.name)) {
      invalid('doujin_snapshot_identity_conflict');
    }
  }
  const urls = new Set(existing.map((event) => event.sourceUrl));
  const missing = [...urls].filter((url) => !incoming.has(url)).length;
  if (urls.size >= 10 && missing > Math.max(5, urls.size * 0.35)) {
    invalid('doujin_snapshot_count_drop');
  }
}
