import 'dotenv/config';
import * as cheerio from 'cheerio';
import { pathToFileURL } from 'url';
import { createPool } from '../src/db.js';
import { assertSourceFetchHost } from './source-fetch-host.js';
import { fetchSourceHtml } from './curl-fetch.js';
import { inTransaction } from '../src/db-transaction.js';
import { validateDoujinHtml, validateDoujinCount, saveDoujinSnapshot } from './event-snapshot.js';

const sourceUrl = 'https://www.doujin.com.tw/events/alist';
const allEventsSourceUrl = 'https://www.doujin.com.tw/events/alist/all';
const sourceOrigin = new URL(sourceUrl).origin;
const cosmosOenEventUrl =
  'https://cosmos.oen.tw/events/3DGSdlOZgTrm1idEZRYTbUp2f4y';
const acostaTaiwanUrl = 'https://acosta.jp/area/over-sea/taiwan/';
const acostaOrigin = new URL(acostaTaiwanUrl).origin;

export async function fetchDoujinEventsHtml(url = allEventsSourceUrl) {
  return fetchSourceHtml(url);
}

export async function scrapeEvents(url = allEventsSourceUrl) {
  if (url !== allEventsSourceUrl) return scrapeDoujinEvents(url);
  const { doujinEvents, supplementalEvents } = await collectEventSources();
  return dedupeEventsByFingerprint([...doujinEvents, ...supplementalEvents]);
}

export async function collectEventSources({
  doujin = scrapeDoujinEvents,
  cosmos = scrapeCosmosOenEvents,
  acosta = scrapeAcostaTaiwanEvents,
  supplemental,
} = {}) {
  const definitions = [
    {sourceKey: 'doujin-source', sourceUrl: allEventsSourceUrl, fetch: doujin},
    ...(supplemental ? [{sourceKey: 'supplemental-source', sourceUrl: '', fetch: supplemental}] : [
      {sourceKey: 'cosmos-source', sourceUrl: cosmosOenEventUrl, fetch: cosmos},
      {sourceKey: 'acosta-source', sourceUrl: acostaTaiwanUrl, fetch: acosta},
    ]),
  ];
  const results = await Promise.allSettled(definitions.map((source) => Promise.resolve().then(source.fetch)));
  const sourceResults = results.map((result, index) => ({
    sourceKey: definitions[index].sourceKey,
    sourceUrl: definitions[index].sourceUrl,
    status: result.status === 'fulfilled' ? 'success' : 'failure',
    events: result.status === 'fulfilled' ? result.value : [],
    importedCount: 0,
    errorCode: result.status === 'rejected' ? String(result.reason?.response?.status ?? result.reason?.code ?? 'fetch_failed') : null,
    errorMessage: result.status === 'rejected' ? summarizeHttpError(result.reason) : null,
  }));
  const doujinSucceeded = results[0].status === 'fulfilled';
  const doujinEvents = doujinSucceeded ? results[0].value : [];
  const supplementalEvents = sourceResults.slice(1).flatMap((source) => source.events);
  for (const result of results) {
    if (result.status === 'rejected') console.warn('[event-scraper] source failed; existing records preserved', summarizeHttpError(result.reason));
  }
  if (!doujinEvents.length && !supplementalEvents.length) {
    throw Object.assign(new Error('all_event_sources_unavailable'), {sourceResults});
  }
  return { doujinEvents, supplementalEvents, doujinSucceeded, sourceResults };
}

export async function scrapeDoujinEvents(url = allEventsSourceUrl) {
  const html = await fetchDoujinEventsHtml(url);
  return parseAndRequireEvents(html);
}

export async function scrapeSupplementalEvents() {
  const results = await Promise.allSettled([
    scrapeCosmosOenEvents(),
    scrapeAcostaTaiwanEvents(),
  ]);
  const events = [];

  for (const result of results) {
    if (result.status === 'fulfilled') {
      events.push(...result.value);
    } else {
      console.warn('[event-scraper] supplemental source failed', summarizeHttpError(result.reason));
    }
  }

  return events;
}

export function parseEventsFromHtml(html) {
  const $ = cheerio.load(html);
  const structuredEvents = parseEventsFromStructuredData($);
  const htmlEvents = parseEventsFromVisibleHtml($);

  if (structuredEvents.length === 0) return htmlEvents;
  if (htmlEvents.length === 0) return structuredEvents;

  return structuredEvents.map((event) => {
    const htmlEvent =
      htmlEvents.find((candidate) => candidate.sourceUrl === event.sourceUrl) ??
      htmlEvents.find((candidate) => candidate.sourceKey === event.sourceKey);
    if (!htmlEvent) return event;

    return {
      ...event,
      category: htmlEvent.category || event.category,
      fee: htmlEvent.fee || event.fee,
      description: event.description || htmlEvent.description,
      organizer: event.organizer || htmlEvent.organizer,
      venue: event.venue || htmlEvent.venue,
      imageUrl: event.imageUrl || htmlEvent.imageUrl,
      status:
        htmlEvent.status === 'rejected' || event.status === 'rejected'
          ? 'rejected'
          : 'approved',
    };
  });
}

function parseEventsFromVisibleHtml($) {
  const events = [];

  $('h3').each((_index, element) => {
    const title = normalize($(element).text());
    const titleMatch = title.match(/^(綜合|ONLY|PT ONLY|茶會)\s+(.+)$/);
    if (!titleMatch) return;

    const category = titleMatch[1];
    const name = cleanDoujinEventName(titleMatch[2]);
    if (!name) return;
    const article = $(element).closest('article');
    const details = article.length ? article : $(element).nextUntil('h3');
    const media = article.length
      ? article.find('img').first()
      : previousMediaElement($(element));
    const detailText = normalize(details.text());
    const startDate = firstMatch(detailText, /活動時間：\s*(\d{4}-\d{2}-\d{2})/);
    if (!startDate) return;

    const endDate = firstMatch(detailText, /~\s*(\d{4}-\d{2}-\d{2})/) ?? startDate;
    const venue = firstMatch(detailText, /活動會場：\s*(.+?)\s+(?:入場費用：|活動內容：|主辦單位：)/) ?? '';
    const fee = firstMatch(detailText, /入場費用：\s*(.+?)\s+(?:活動內容：|主辦單位：)/) ?? '';
    const description = firstMatch(detailText, /活動內容：\s*(.+?)\s+主辦單位：/) ?? '';
    const organizer = firstMatch(detailText, /主辦單位：\s*(.+?)(?:\s+\d+(?:天|個月|小時)前更新|$)/) ?? '';
    const eventUrl = absoluteUrl(
      article.find('a[itemprop="url"][href]').first().attr('href') ??
        $(element).find('a[href]').first().attr('href') ??
        details.find('a[href]').first().attr('href'),
    );
    const imageUrl = absoluteUrl(
      media.find('img').first().attr('data-src') ??
        media.find('img').first().attr('data-original') ??
        media.find('img').first().attr('src') ??
        media.attr('data-src') ??
        media.attr('data-original') ??
        media.attr('src') ??
        details.find('img').first().attr('data-src') ??
        details.find('img').first().attr('data-original') ??
        details.find('img').first().attr('src'),
    );

    events.push({
      sourceKey: doujinSourceKey(name, startDate, eventUrl),
      sourceType: 1,
      sourceName: '同人誌中心',
      sourceUrl: eventUrl,
      imageUrl,
      category,
      name,
      startDate,
      endDate,
      venue,
      fee,
      description,
      organizer,
      status: isDoujinEventCancelled(name) ? 'rejected' : 'approved',
    });
  });

  return events;
}

function parseEventsFromStructuredData($) {
  const events = [];

  $('script[type="application/ld+json"]').each((_index, element) => {
    const text = $(element).contents().text().trim();
    if (!text) return;

    try {
      collectStructuredEvents(JSON.parse(text), events);
    } catch {
      // Ignore malformed structured data and let visible HTML parsing handle it.
    }
  });

  const uniqueEvents = new Map();
  for (const event of events) {
    uniqueEvents.set(event.sourceUrl || event.sourceKey, event);
  }

  return [...uniqueEvents.values()];
}

function collectStructuredEvents(value, events) {
  if (Array.isArray(value)) {
    for (const item of value) collectStructuredEvents(item, events);
    return;
  }

  if (!value || typeof value !== 'object') return;

  if (isStructuredDoujinEvent(value)) {
    const event = structuredEventToCosCircleEvent(value);
    if (event) events.push(event);
    return;
  }

  if (Array.isArray(value['@graph'])) {
    collectStructuredEvents(value['@graph'], events);
  }

  collectStructuredEvents(value.mainEntity, events);
  collectStructuredEvents(value.itemListElement, events);
  collectStructuredEvents(value.item, events);
}

function isStructuredDoujinEvent(value) {
  const type = value['@type'];
  const types = Array.isArray(type) ? type : [type];
  return types.some((item) => typeof item === 'string' && item.endsWith('Event'));
}

function structuredEventToCosCircleEvent(value) {
  const name = cleanDoujinEventName(textValue(value.name));
  const startDate = dateValue(value.startDate);
  if (!name || !startDate) return null;

  const sourceUrl = absoluteUrl(textValue(value.url));
  const endDate = dateValue(value.endDate) || startDate;
  const description = textValue(value.description || value.about);
  const organizer = textValue(value.organizer?.name || value.organizer);
  const location = value.location && typeof value.location === 'object'
    ? value.location
    : {};
  const venue = textValue(location.name || value.location);
  const imageUrl = imageValue(value.image);
  const statusValue = textValue(value.eventStatus);
  const status =
    isDoujinEventCancelled(name) || statusValue.endsWith('/EventCancelled')
      ? 'rejected'
      : 'approved';

  return {
    sourceKey: doujinSourceKey(name, startDate, sourceUrl),
    sourceType: 1,
    sourceName: '同人誌中心',
    sourceUrl,
    imageUrl,
    category: inferDoujinCategory([value.about, description, name].map(textValue).join(' ')),
    name,
    startDate,
    endDate,
    venue,
    fee: '',
    description,
    organizer,
    status,
  };
}

async function scrapeCosmosOenEvents() {
  const html = await fetchPublicHtml(cosmosOenEventUrl);
  const event = parseCosmosOenEventFromHtml(html, cosmosOenEventUrl);
  if (!event) throw new Error('cosmos_events_parse_empty');
  return [event];
}

export function parseCosmosOenEventFromHtml(html, eventUrl = cosmosOenEventUrl) {
  const $ = cheerio.load(html);
  const bodyText = normalize($('body').text());
  const dateRange = parseCosmosDateRange(bodyText);
  if (!dateRange) return null;

  const venue = firstMatch(
    bodyText,
    /活動地點：\s*(.+?)(?:（|🎟️|售票與票種說明|$)/,
  ) ?? firstMatch(bodyText, /\(UTC\+8\)\s*(.+?)(?:Copy link|活動資訊|$)/) ?? '';
  const detailedAddress = firstMatch(bodyText, /（[^）]*?([臺台]北市[^）]+)）/) ?? '';
  const fee = firstMatch(bodyText, /一般單日票：\s*(NT\$\s*\d+)/) ?? '';
  const imageUrl = absoluteUrl(
    $('meta[property="og:image"]').attr('content') ?? '',
    eventUrl,
  );

  return {
    sourceKey: 'cosmos-oen-entry-ticket-2026',
    sourceType: 4,
    sourceName: 'COSMOS 創作攝影展',
    sourceUrl: eventUrl,
    imageUrl,
    category: '綜合',
    name: 'COSMOS 創作攝影展',
    startDate: dateRange.startDate,
    endDate: dateRange.endDate,
    venue: normalize(venue.replace(/國立台灣大學/g, '國立臺灣大學')),
    detailedAddress,
    fee,
    organizer: 'COSMOS 創作攝影展',
    description: firstMatch(bodyText, /〖COSMOS Cosplay 創作攝影展〗(.+?)🎟️/) ??
      'COSMOS Cosplay 創作攝影展官方活動與售票說明。',
    status: 'approved',
  };
}

async function scrapeAcostaTaiwanEvents() {
  const listHtml = await fetchPublicHtml(acostaTaiwanUrl);
  const eventUrls = acostaTaiwanEventUrlsFromHtml(listHtml);
  if (!eventUrls.length) throw new Error('acosta_events_parse_empty');
  const events = [];

  for (const eventUrl of eventUrls) {
    const eventHtml = await fetchPublicHtml(eventUrl);
    const event = parseAcostaEventFromHtml(eventHtml, eventUrl);
    if (!event) throw new Error(`acosta_event_parse_failed: ${eventUrl}`);
    events.push(event);
  }

  return events;
}

export function acostaTaiwanEventUrlsFromHtml(html) {
  const $ = cheerio.load(html);
  const urls = new Set();

  $('a[href]').each((_index, element) => {
    const href = absoluteUrl($(element).attr('href'), acostaTaiwanUrl);
    if (!href) return;
    const url = new URL(href);
    if (url.origin !== acostaOrigin) return;
    if (!/^\/event\/(?:taipei|takao|taiwan|kaohsiung|[^/]*taipei|[^/]*takao)/i.test(url.pathname)) {
      return;
    }
    urls.add(url.href);
  });

  return [...urls];
}

export function parseAcostaEventFromHtml(html, eventUrl) {
  const $ = cheerio.load(html);
  const bodyText = normalize($('body').text());
  const rawTitle = normalize($('title').text()).replace(/\s+-\s+acosta![\s\S]*$/i, '');
  const dateRange = parseAcostaTitleDateRange(rawTitle);
  if (!dateRange) return null;

  const locationName = firstMatch(rawTitle, /acosta![＠@](.+)$/) ?? '';
  const venueBlock = firstMatch(bodyText, /会場\s+アクセス詳細\s+(.+?)\s+台湾/);
  const venue = normalize(
    (venueBlock ?? locationName)
      .replace(/\s+[【〖][\s\S]*$/, '')
      .replace(/[【〖][^】〗]+[】〗]/g, ''),
  );
  const address = firstMatch(
    bodyText,
    /会場\s+アクセス詳細\s+.+?\s+台湾\s*(.+?)\s+チケット情報/,
  ) ?? '';
  const timeRange = firstMatch(bodyText, /開催日時\s+\d{4}\s+\d{1,2}\.\d{1,2}\w+\s+(?:\d{1,2}\w+\s+)?(\d{1,2}:\d{2}～\d{1,2}:\d{2})/);
  const fee = firstMatch(bodyText, /カメラ・一般\s+\d{1,2}:\d{2}~\s+前売り([0-9,]+\s*円)/) ??
    firstMatch(bodyText, /コスプレ更衣室なし\s+\d{1,2}:\d{2}~\s+前売り([0-9,]+\s*円)/) ??
    '';
  const imageUrl = absoluteUrl(
    $('meta[property="og:image"]').attr('content') ??
      $('img[src*="taipei"], img[src*="takao"], img[src*="kaohsiung"]').first().attr('src') ??
      $('img').first().attr('src') ??
      '',
    eventUrl,
  );

  return {
    sourceKey: `acosta-${new URL(eventUrl).pathname.split('/').filter(Boolean).at(-1)}`,
    sourceType: 5,
    sourceName: 'acosta!',
    sourceUrl: eventUrl,
    imageUrl,
    category: '綜合',
    name: `acosta!@${locationName}`,
    startDate: dateRange.startDate,
    endDate: dateRange.endDate,
    venue,
    detailedAddress: address,
    fee,
    organizer: 'acosta!',
    description: ['日本大型 Cosplay 活動品牌 acosta! 台灣場。', timeRange ? `活動時間：${timeRange}` : '']
      .filter(Boolean)
      .join(' '),
    status: 'approved',
  };
}

export async function importEvents(pool = createPool(), sources = {}, onSourceResult = async () => {}) {
  let sourceResults;
  try {
    ({sourceResults} = await collectEventSources(sources));
  } catch (error) {
    for (const {events: _events, ...report} of error.sourceResults ?? []) {
      const publish = await onSourceResult(report, pool);
      if (typeof publish === 'function') publish();
    }
    throw error;
  }
  const importedEvents = [];
  for (const source of sourceResults) {
    let reported = false;
    if (source.status === 'success') {
      try {
        const publish = await inTransaction(pool, async (db) => {
          if (source.sourceKey === 'doujin-source') await validateDoujinCount(db, source.events);
          if (source.events.length) await upsertEvents(db, source.events);
          if (source.sourceKey === 'doujin-source') await saveDoujinSnapshot(db, source.events);
          source.importedCount = source.events.length;
          const {events: _events, ...report} = source;
          return onSourceResult(report, db);
        });
        reported = true;
        if (typeof publish === 'function') publish();
        importedEvents.push(...source.events);
      } catch (error) {
        source.status = 'failure';
        source.importedCount = 0;
        source.errorCode = String(error?.code ?? 'import_failed');
        source.errorMessage = summarizeHttpError(error);
      }
    }
    const {events: _events, ...report} = source;
    if (!reported) {
      const publish = await onSourceResult(report, pool);
      if (typeof publish === 'function') publish();
    }
  }
  if (sourceResults.every((source) => source.status === 'failure')) {
    throw Object.assign(new Error('all_event_sources_unavailable'), {sourceResults});
  }
  return dedupeEventsByFingerprint(importedEvents);
}

export async function importEventsFromHtml(html, pool = createPool()) {
  const events = parseAndRequireEvents(html);
  await inTransaction(pool, async (db) => {
    await validateDoujinCount(db, events);
    await upsertEvents(db, events);
    await saveDoujinSnapshot(db, events);
  });
  return events;
}

async function upsertEvents(
  pool,
  events,
) {
  for (const event of events) {
    if (await updateExistingDoujinEventByUrl(pool, event)) {
      continue;
    }
    if (await updateExistingEventByFingerprint(pool, event)) {
      continue;
    }

    await pool.execute(
      `INSERT INTO events
        (source_key, source_type, source_name, source_url, image_url, category, name, start_date, end_date, venue, detailed_address, fee, organizer, description, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
        source_type = VALUES(source_type),
        source_name = VALUES(source_name),
        source_url = VALUES(source_url),
        image_url = VALUES(image_url),
        category = VALUES(category),
        name = VALUES(name),
        start_date = VALUES(start_date),
        end_date = VALUES(end_date),
        venue = VALUES(venue),
        detailed_address = VALUES(detailed_address),
        fee = VALUES(fee),
        organizer = VALUES(organizer),
        description = VALUES(description),
        status = VALUES(status)`,
      [
        event.sourceKey,
        event.sourceType,
        event.sourceName,
        event.sourceUrl,
        event.imageUrl,
        event.category,
        event.name,
        event.startDate,
        event.endDate,
        event.venue,
        event.detailedAddress ?? '',
        event.fee,
        event.organizer,
        event.description,
        event.status,
      ],
    );
  }
  // Only explicit cancellation in fetched records changes publication status.
}

async function updateExistingDoujinEventByUrl(pool, event) {
  if (!event.sourceUrl) return false;

  const [rows] = await pool.execute(
    `SELECT id
       FROM events
      WHERE source_url = ?
        AND (source_key LIKE 'doujin-%'
          OR source_type = 1
          OR source_name = '同人誌中心')
      ORDER BY (source_key = ?) DESC, updated_at DESC, id DESC
      LIMIT 1`,
    [event.sourceUrl, event.sourceKey],
  );
  const existingId = rows[0]?.id;
  if (!existingId) return false;

  await pool.execute(
    `UPDATE events
        SET source_key = ?,
            source_type = ?,
            source_name = ?,
            source_url = ?,
            image_url = ?,
            category = ?,
            name = ?,
            start_date = ?,
            end_date = ?,
            venue = ?,
            detailed_address = COALESCE(NULLIF(detailed_address, ''), ?),
            fee = ?,
            organizer = ?,
            description = ?,
            status = ?
      WHERE id = ?`,
    [
      event.sourceKey,
      event.sourceType,
      event.sourceName,
      event.sourceUrl,
      event.imageUrl,
      event.category,
      event.name,
      event.startDate,
      event.endDate,
      event.venue,
      event.detailedAddress ?? '',
      event.fee,
      event.organizer,
      event.description,
      event.status,
      existingId,
    ],
  );

  return true;
}

async function updateExistingEventByFingerprint(pool, event) {
  const [rows] = await pool.execute(
    `SELECT id, name, venue, source_url AS sourceUrl, detailed_address AS detailedAddress
       FROM events
      WHERE start_date = ?
        AND end_date = ?
      ORDER BY updated_at DESC, id DESC`,
    [event.startDate, event.endDate],
  );

  const existing = rows.find((row) => isLikelySameEvent(row, event));
  if (!existing) return false;

  await pool.execute(
    `UPDATE events
        SET image_url = COALESCE(NULLIF(image_url, ''), ?),
            category = ?,
            name = ?,
            venue = ?,
            detailed_address = COALESCE(NULLIF(detailed_address, ''), ?),
            fee = COALESCE(NULLIF(fee, ''), ?),
            organizer = COALESCE(NULLIF(organizer, ''), ?),
            description = CASE
              WHEN description IS NULL OR description = '' THEN ?
              WHEN CHAR_LENGTH(?) > CHAR_LENGTH(description) THEN ?
              ELSE description
            END,
            status = ?
      WHERE id = ?`,
    [
      event.imageUrl,
      event.category,
      event.name,
      event.venue,
      event.detailedAddress ?? '',
      event.fee,
      event.organizer,
      event.description,
      event.description,
      event.description,
      event.status,
      existing.id,
    ],
  );

  return true;
}

if (isCliEntry()) {
  const shouldImport = process.argv.includes('--import');
  const pool = shouldImport ? createPool() : null;
  const events = shouldImport ? await importEvents(pool) : await scrapeEvents();
  if (pool) await pool.end();

  console.log(
    JSON.stringify(
      {
        sourceUrl,
        imported: shouldImport,
        count: events.length,
        events,
      },
      null,
      2,
    ),
  );
}

function normalize(value) {
  return value.replace(/\s+/g, ' ').trim();
}

export function cleanDoujinEventName(value) {
  let name = normalize(String(value ?? ''));
  const newMarkerPattern = /[\s　]*(?:[\[【(（]\s*)?new\s*[!！]+(?:\s*[\]】)）])?[\s　]*/i;

  while (name) {
    const match = name.match(newMarkerPattern);
    if (!match) break;

    const beforeMarker = name.slice(0, match.index).trim();
    if (beforeMarker) return beforeMarker;

    name = name.slice(match.index + match[0].length).trim();
  }

  return name.trim();
}

export function doujinSourceKey(name, startDate, sourceUrl = '') {
  const sourceEventId = doujinEventIdFromUrl(sourceUrl);
  if (sourceEventId) return `doujin-${sourceEventId}`;

  return `doujin-${slugify(cleanDoujinEventName(name))}-${startDate}`;
}

export function doujinEventIdFromUrl(sourceUrl) {
  if (!sourceUrl) return '';

  try {
    const url = new URL(sourceUrl, sourceOrigin);
    const match = url.pathname.match(/\/events\/info\/(\d+)(?:\/)?$/);
    return match?.[1] ?? '';
  } catch {
    const match = String(sourceUrl).match(/\/events\/info\/(\d+)(?:[/?#]|$)/);
    return match?.[1] ?? '';
  }
}

export function isDoujinEventCancelled(name) {
  return /(?:活動|場次)?取消|中止|停辦/.test(String(name ?? ''));
}

export async function rejectCancelledDoujinEventFamilies(pool) {
  await pool.execute(
    `UPDATE events AS event
      INNER JOIN (
        SELECT DISTINCT source_url
          FROM events
         WHERE (source_key LIKE 'doujin-%'
             OR source_type = 1
             OR source_name = '同人誌中心')
           AND source_url IS NOT NULL
           AND source_url <> ''
           AND name REGEXP '活動取消|場次取消|取消|中止|停辦'
      ) AS cancelled
        ON cancelled.source_url = event.source_url
       SET event.status = 'rejected'
     WHERE event.source_url IS NOT NULL
       AND event.source_url <> ''
       AND (event.source_key LIKE 'doujin-%'
         OR event.source_type = 1
         OR event.source_name = '同人誌中心')`,
  );
}

function firstMatch(value, pattern) {
  return value.match(pattern)?.[1]?.trim();
}

function textValue(value) {
  if (value == null) return '';
  if (Array.isArray(value)) {
    return value.map(textValue).filter(Boolean)[0] ?? '';
  }
  if (typeof value === 'object') {
    return textValue(value.name || value.url || value['@id']);
  }
  return normalize(String(value));
}

function dateValue(value) {
  const text = textValue(value);
  return text.match(/\d{4}-\d{2}-\d{2}/)?.[0] ?? '';
}

function parseCosmosDateRange(value) {
  const match = normalize(value).match(
    /(\d{4})\/(\d{2})\/(\d{2})\s*\([^)]*\)\s*\d{1,2}:\d{2}\s*~\s*(\d{2})\/(\d{2})\s*\([^)]*\)\s*\d{1,2}:\d{2}/,
  );
  if (!match) return null;

  return {
    startDate: `${match[1]}-${match[2]}-${match[3]}`,
    endDate: `${match[1]}-${match[4]}-${match[5]}`,
  };
}

function parseAcostaTitleDateRange(value) {
  const text = normalize(value);
  const match = text.match(
    /(\d{4})年(\d{1,2})月(\d{1,2})日(?:\([^)]*\))?(?:[・･]\s*)?(\d{1,2})?日?/,
  );
  if (!match) return null;

  const year = match[1];
  const month = match[2].padStart(2, '0');
  const startDay = match[3].padStart(2, '0');
  const endDay = (match[4] ?? match[3]).padStart(2, '0');

  return {
    startDate: `${year}-${month}-${startDay}`,
    endDate: `${year}-${month}-${endDay}`,
  };
}

function imageValue(value) {
  if (Array.isArray(value)) {
    return imageValue(value[0]);
  }
  if (value && typeof value === 'object') {
    return absoluteUrl(textValue(value.url || value.contentUrl));
  }
  return absoluteUrl(textValue(value));
}

function inferDoujinCategory(value) {
  const text = String(value ?? '').toUpperCase();
  if (text.includes('PT ONLY')) return 'PT ONLY';
  if (text.includes('ONLY')) return 'ONLY';
  if (text.includes('茶會')) return '茶會';
  return '綜合';
}

function absoluteUrl(value, baseUrl = sourceOrigin) {
  if (!value) return '';
  try {
    return new URL(value, baseUrl).href;
  } catch {
    return '';
  }
}

async function fetchPublicHtml(url) {
  assertSourceFetchHost();
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await fetchSourceHtml(url);
    } catch (error) {
      lastError = error;
      if (attempt === 2 || !shouldRetryPublicFetch(error)) break;
      await sleep(1200 + attempt * 800);
    }
  }

  throw lastError;
}

function shouldRetryPublicFetch(error) {
  if (error?.code === 'gcp_only_source_fetch' || String(error?.code ?? '').startsWith('curl_')) return false;
  if (error?.response?.headers?.['cf-mitigated'] === 'challenge') return false;
  const status = error?.response?.status;
  return status === 408 || status >= 500;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function dedupeEventsByFingerprint(events) {
  const byFingerprint = new Map();

  for (const event of events) {
    const key = eventFingerprint(event);
    const existing = byFingerprint.get(key);
    if (!existing || eventCompletenessScore(event) > eventCompletenessScore(existing)) {
      byFingerprint.set(key, event);
    }
  }

  return [...byFingerprint.values()];
}

export function isLikelySameEvent(existing, incoming) {
  const doujinId = (url) => String(url ?? '').match(/^https:\/\/www\.doujin\.com\.tw\/events\/info\/(\d+)(?:[/?#]|$)/)?.[1];
  const existingId = doujinId(existing.sourceUrl);
  const incomingId = doujinId(incoming.sourceUrl);
  if (existingId && incomingId && existingId !== incomingId) return false;
  const existingName = canonicalEventText(existing.name);
  const incomingName = canonicalEventText(incoming.name);
  const existingVenue = canonicalEventText(
    [existing.venue, existing.detailedAddress].filter(Boolean).join(' '),
  );
  const incomingVenue = canonicalEventText(
    [incoming.venue, incoming.detailedAddress].filter(Boolean).join(' '),
  );

  // A shared venue/date alone is not identity: independent fairs can be co-located.
  return hasSharedSignificantToken(existingName, incomingName)
    && (!existingVenue || !incomingVenue || hasSharedSignificantToken(existingVenue, incomingVenue));
}

function eventFingerprint(event) {
  return [
    event.startDate,
    event.endDate,
    canonicalEventText(event.name).slice(0, 80),
    canonicalEventText(event.venue).slice(0, 80),
  ].join('|');
}

function canonicalEventText(value) {
  return normalize(String(value ?? ''))
    .toLowerCase()
    .replace(/[【】〖〗「」『』!！@＠()[\]（）・･\s]/g, '')
    .replace(/國立台灣/g, '國立臺灣')
    .replace(/台灣/g, '臺灣')
    .replace(/園区/g, '園區')
    .replace(/号/g, '號');
}

function hasSharedSignificantToken(left, right) {
  if (!left || !right) return false;
  if (left.includes(right) || right.includes(left)) return true;

  const tokens = ['cosmos', 'acosta'];
  return tokens.some((token) => left.includes(token) && right.includes(token));
}

function eventCompletenessScore(event) {
  return [
    event.sourceUrl,
    event.imageUrl,
    event.venue,
    event.detailedAddress,
    event.fee,
    event.organizer,
    event.description,
  ].filter((value) => String(value ?? '').trim()).length;
}

function previousMediaElement(element) {
  let current = element.prev();
  while (current.length && !current.is('h3')) {
    if (current.is('img') || current.find('img').length > 0) {
      return current;
    }
    current = current.prev();
  }
  return cheerio.load('')('');
}

function isCliEntry() {
  return process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
}

export function parseAndRequireEvents(html) {
  if (isCloudflareChallengeHtml(html)) {
    throw new Error('doujin_source_cloudflare_challenge');
  }

  const events = parseEventsFromHtml(html);
  if (events.length === 0) {
    throw new Error('doujin_events_parse_empty');
  }
  validateDoujinHtml(html, events);
  return events;
}

function isCloudflareChallengeHtml(html) {
  const text = String(html ?? '').slice(0, 20000);
  const titleLooksLikeChallenge =
    /<title>\s*(?:Just a moment\.\.\.|請稍候|安全性檢查)\s*<\/title>/i.test(text);
  const bodyLooksLikeChallenge =
    text.includes('/cdn-cgi/challenge-platform/') ||
    text.includes('__cf_chl_') ||
    text.includes('cf-turnstile-response') ||
    text.includes('Checking if the site connection is secure') ||
    text.includes('Performance and Security by Cloudflare');

  return titleLooksLikeChallenge && bodyLooksLikeChallenge;
}

function summarizeHttpError(error) {
  const status = error?.response?.status;
  const statusText = error?.response?.statusText;
  if (error?.response?.headers?.['cf-mitigated'] === 'challenge') {
    return [status, 'Cloudflare 驗證攔截：未取得活動資料', error.response.headers['cf-ray']]
      .filter(Boolean).join(' ');
  }
  return [status, statusText, error?.message].filter(Boolean).join(' ') || 'unknown';
}

function slugify(value) {
  return encodeURIComponent(value)
    .replace(/%/g, '')
    .toLowerCase()
    .slice(0, 120);
}
