import assert from 'node:assert/strict';
import test from 'node:test';
import {validateDoujinHtml, validateDoujinCount} from './event-snapshot.js';

const event = {name: 'Fair', startDate: '2027-01-01', endDate: '2027-01-02', sourceUrl: 'https://www.doujin.com.tw/events/info/1'};
const html = (count = 1) => `<html><script type="application/ld+json">${JSON.stringify({'@type': 'ItemList', numberOfItems: count})}</script></html>`;

test('complete snapshots validate; malformed, truncated, duplicate and invalid dates stop import', () => {
  validateDoujinHtml(html(), [event]);
  for (const [body, rows, code] of [
    ['<html>', [event], 'doujin_snapshot_truncated'],
    [html(2), [event], 'doujin_snapshot_count_mismatch'],
    [html(), [{...event, startDate: '2027-02-30'}], 'doujin_snapshot_invalid_event'],
    [html(2), [event, event], 'doujin_snapshot_duplicate_event'],
    ['<html><script type="application/ld+json">{</script></html>', [event], 'doujin_snapshot_invalid_json'],
  ]) assert.throws(() => validateDoujinHtml(body, rows), {code});
});

test('abnormally shrinking future-event coverage fails before any writes', async () => {
  const rows = Array.from({length: 20}, (_, index) => ({sourceUrl: `https://www.doujin.com.tw/events/info/${index + 1}`}));
  const db = {execute: async (sql) => {assert.match(sql, /^SELECT/);return [rows];}};
  await assert.rejects(validateDoujinCount(db, [event]), {code: 'doujin_snapshot_count_drop'});
  await validateDoujinCount(db, rows.slice(0, 18));
});

test('an already merged identity cannot silently reassign existing attendance', async () => {
  const first = {...event, name: 'IF8'};
  const second = {...event, name: 'BIO14', sourceUrl: 'https://www.doujin.com.tw/events/info/2'};
  const db = {execute: async () => [[{sourceUrl: first.sourceUrl, name: second.name}]]};
  await assert.rejects(validateDoujinCount(db, [first, second]), {code: 'doujin_snapshot_identity_conflict'});
});
