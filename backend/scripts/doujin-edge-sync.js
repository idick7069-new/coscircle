import 'dotenv/config';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import axios from 'axios';
import { fetchDoujinEventsHtml, parseEventsFromHtml } from './scrape-events.js';

const defaultSourceUrl = 'https://www.doujin.com.tw/events/alist/all';
const defaultApiBaseUrl = 'http://34.187.168.222/api';
const localEnvPath = path.join(
  os.homedir(),
  'Library',
  'Application Support',
  'CosCircle',
  'doujin-edge-sync.env',
);

loadLocalEnv(localEnvPath);

const sourceUrl = process.env.DOUJIN_SOURCE_URL ?? defaultSourceUrl;
const apiBaseUrl = trimTrailingSlash(
  process.env.COSCIRCLE_API_BASE_URL ?? defaultApiBaseUrl,
);
const ingestToken = String(process.env.COSCIRCLE_SYNC_INGEST_TOKEN ?? '').trim();

if (ingestToken.length < 32) {
  console.error(
    `COSCIRCLE_SYNC_INGEST_TOKEN is missing. Expected it in ${localEnvPath}`,
  );
  process.exit(2);
}

try {
  const html = await fetchDoujinEventsHtml(sourceUrl);
  const parsedEvents = parseEventsFromHtml(html);
  if (parsedEvents.length === 0) {
    throw new Error('No Doujin events were parsed from the downloaded HTML.');
  }

  const response = await axios.post(
    `${apiBaseUrl}/source-ingest/doujin-html`,
    { sourceUrl, html },
    {
      timeout: 30000,
      maxBodyLength: Infinity,
      headers: {
        authorization: `Bearer ${ingestToken}`,
        'content-type': 'application/json',
      },
    },
  );

  console.log(
    JSON.stringify(
      {
        ok: true,
        sourceUrl,
        parsedCount: parsedEvents.length,
        importedCount: response.data?.count ?? null,
        apiBaseUrl,
        syncedAt: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify(
      {
        ok: false,
        sourceUrl,
        apiBaseUrl,
        error: summarizeError(error),
        syncedAt: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
  process.exit(1);
}

function loadLocalEnv(filePath) {
  if (!fs.existsSync(filePath)) return;

  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}

function trimTrailingSlash(value) {
  return String(value).replace(/\/+$/, '');
}

function summarizeError(error) {
  const status = error?.response?.status;
  const statusText = error?.response?.statusText;
  if (status != null) {
    return [status, statusText, error?.message].filter(Boolean).join(' ');
  }
  return error?.message?.toString() ?? error?.code?.toString() ?? 'unknown_error';
}
