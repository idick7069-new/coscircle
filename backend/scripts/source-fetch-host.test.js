import assert from 'node:assert/strict';
import os from 'node:os';
import test from 'node:test';
import {assertSourceFetchHost} from './source-fetch-host.js';
import * as scraper from './scrape-events.js';

test('only the specified VM can make activity source requests', () => {
  assert.doesNotThrow(() => assertSourceFetchHost('coscircle-free-vm'));
  assert.doesNotThrow(() => assertSourceFetchHost('coscircle-free-vm.us-west1-b.c.cos-circle.internal'));
  for (const hostname of ['localhost', 'frank-macbook', 'other-gcp-vm', 'coscircle-free-vm-fake']) {
    assert.throws(() => assertSourceFetchHost(hostname), {code: 'gcp_only_source_fetch'});
  }
});

test('a local invocation stops before HTTP execution', {
  skip: /^coscircle-free-vm(?:\.|$)/.test(os.hostname()),
}, async () => {
  await assert.rejects(() => scraper.fetchDoujinEventsHtml(), {code: 'gcp_only_source_fetch'});
});

test('the scraper no longer exports browser fallback entry points', () => {
  assert.equal('fetchDoujinEventsHtmlWithBrowser' in scraper, false);
  assert.equal('fetchDoujinEventsHtmlWithFallback' in scraper, false);
});
