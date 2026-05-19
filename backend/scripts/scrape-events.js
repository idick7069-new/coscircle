import 'dotenv/config';
import axios from 'axios';
import * as cheerio from 'cheerio';
import { pathToFileURL } from 'url';
import { createPool } from '../src/db.js';

const sourceUrl = 'https://www.doujin.com.tw/events/alist';
const sourceOrigin = new URL(sourceUrl).origin;

export async function scrapeEvents() {
  const { data } = await axios.get(sourceUrl, {
    timeout: 20000,
    headers: {
      'user-agent': 'CosCircle event importer (+https://example.local)',
    },
  });

  const $ = cheerio.load(data);
  const events = [];

  $('h3').each((_index, element) => {
    const title = normalize($(element).text());
    const titleMatch = title.match(/^(綜合|ONLY|PT ONLY|茶會)\s+(.+)$/);
    if (!titleMatch) return;

    const category = titleMatch[1];
    const name = titleMatch[2];
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
      sourceKey: `doujin-${slugify(name)}-${startDate}`,
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
    });
  });

  return events;
}

export async function importEvents(pool = createPool()) {
  const events = await scrapeEvents();
  for (const event of events) {
    await pool.execute(
      `INSERT INTO events
        (source_key, source_type, source_name, source_url, image_url, category, name, start_date, end_date, venue, fee, organizer, description)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        fee = VALUES(fee),
        organizer = VALUES(organizer),
        description = VALUES(description)`,
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
        event.fee,
        event.organizer,
        event.description,
      ],
    );
  }
  return events;
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

function firstMatch(value, pattern) {
  return value.match(pattern)?.[1]?.trim();
}

function absoluteUrl(value) {
  if (!value) return '';
  try {
    return new URL(value, sourceOrigin).href;
  } catch {
    return '';
  }
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

function slugify(value) {
  return encodeURIComponent(value)
    .replace(/%/g, '')
    .toLowerCase()
    .slice(0, 120);
}
