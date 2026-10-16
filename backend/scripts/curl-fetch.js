import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { load } from 'cheerio';
import { assertSourceFetchHost } from './source-fetch-host.js';

const execFileAsync = promisify(execFile);
const scriptPath = fileURLToPath(new URL('./curl-fetch.py', import.meta.url));
const defaultPythonPath = fileURLToPath(new URL('../.crawler-venv/bin/python', import.meta.url));

function sourceDiagnostics(result) {
  const headers = result.headers;
  return {
    origin: headers['cf-mitigated'] === 'challenge' ? 'cloudflare-challenge' : 'unknown',
    server: headers.server ?? null,
    title: load(result.data)('title').text().trim().slice(0, 160),
    providerErrorCodes: [],
  };
}

export async function fetchSourceHtml(url, { execute = execFileAsync } = {}) {
  assertSourceFetchHost();
  let result;
  try {
    const { stdout } = await execute(
      process.env.EVENT_SCRAPER_PYTHON ?? defaultPythonPath,
      [scriptPath, url],
      { timeout: new URL(url).hostname === 'www.doujin.com.tw' ? 190000 : 25000, maxBuffer: 32 * 1024 * 1024 },
    );
    result = JSON.parse(stdout);
  } catch {
    throw Object.assign(new Error('curl_source_transport_failed'), { code: 'curl_source_transport_failed' });
  }
  if (result?.error) {
    const error = Object.assign(new Error(result.error), { code: result.error });
    if (Number.isInteger(result.providerStatus)) {
      error.response = { status: result.providerStatus, headers: result.headers ?? {},
        diagnostics: { origin: 'zenrows', providerErrorCodes: [] } };
    }
    throw error;
  }
  if (!Number.isInteger(result?.status) || typeof result.data !== 'string' || !result.headers) {
    throw Object.assign(new Error('curl_source_invalid_response'), { code: 'curl_source_invalid_response' });
  }
  const response = { status: result.status, headers: result.headers, data: result.data };
  const title = load(result.data)('title').text().trim();
  if (result.headers['cf-mitigated'] === 'challenge' || /^Just a moment\.{0,3}$/i.test(title)) {
    response.diagnostics = sourceDiagnostics(result);
    throw Object.assign(new Error('source_cloudflare_challenge'), { response });
  }
  if (result.status < 200 || result.status >= 300) {
    response.diagnostics = sourceDiagnostics(result);
    throw Object.assign(new Error(`Source returned HTTP ${result.status}`), { response });
  }
  if (!String(result.headers['content-type'] ?? '').toLowerCase().includes('text/html')) {
    throw Object.assign(new Error('curl_source_not_html'), { code: 'curl_source_not_html' });
  }
  return result.data;
}
