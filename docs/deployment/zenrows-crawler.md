# ZenRows event source transport

Only the production GCP VM `coscircle-free-vm` may request event sources.
Doujin uses `https://api.zenrows.com/v1/` when the restricted configuration
`/etc/coscircle/zenrows.json` is enabled. COSMOS and acosta retain direct HTTP.
The file is owned by `root:coscircle`, mode `0640`; no key is stored in Git,
deployment archives, command arguments, response diagnostics or application logs.

The VM uses its existing curl_cffi environment for a single HTTP request with
`js_render=true`, `premium_proxy=true`, and `original_status=true`. ZenRows owns
the remote browser/proxy infrastructure. No local Chrome, DataImpulse proxy,
cookie transfer, CAPTCHA interaction, client retries or paid-plan upgrade is used.
The HTTP timeout is 180 seconds, with a 190-second subprocess limit. Cancelling
a client request does not necessarily cancel processing at ZenRows.

HTTP success alone is insufficient. The transport rejects provider HTTP errors,
non-HTML bodies and known challenge-page titles; the importer additionally requires
actual parsed events. ZenRows sometimes labels raw HTML `text/plain`: it is
normalized only when an HTML document marker is present. Error bodies and arbitrary
provider headers are not logged. Existing matching/deduplication, source attribution,
multi-day handling and per-source failure preservation remain unchanged.

To rotate the key, open an interactive SSH terminal on the VM and run:

```sh
sudo python3 /opt/coscircle/api/current/scripts/configure-zenrows.py
```

Enter the new key in the hidden prompt, then revoke the old key in ZenRows.
Configuration is read on every request; no service restart is required. Missing,
disabled, malformed or unsafe configuration stops Doujin synchronization. No
DataImpulse, direct Doujin request or local browser fallback remains in the active
code. COSMOS and acosta continue using direct HTTP.

## Credits

The official docs currently list JS + premium proxy at 25 credits per successful
request. One daily list fetch is roughly 750-775 credits/month. This excludes
manual admin syncs, tests and other consumers of the same account. The public Free
plan lists 5,000 credits/month; verify the actual account plan and configure an
API-key credit cap in the dashboard. This connector does not buy credits or upgrade
the plan and does not guarantee account-level spend limits by itself.

References:
- https://docs.zenrows.com/fetch/api-reference
- https://www.zenrows.com/pricing

## Production test, 2026-10-06

A single GCP request returned HTTP 200 in 10.07 seconds, 206,254 HTML bytes.
Offline parsing found 49 events (2026: 34, 2027: 15), including the Bahamut
30th anniversary market on 2026-10-24 through 2026-10-25. Provider request ID:
`6ac4bf8a574fbfdbabe9964aa0254206`. The provider cost header reported `0.025`;
its unit/account billing was not inferred. No source request originated locally.
The initial test did not modify the database.

The crawler-only release `/opt/coscircle/api/releases/20261006-zenrows` was
prepared from the previous deployed release with only transport/configuration and
focused test files overlaid. Local unrelated frontend/server changes were not
included. Local validation: 21 Python tests and 19 Node tests passed; GCP candidate:
17 Python tests and 18 Node tests passed (one local-host test skipped).

After the user explicitly approved a backup and production import, the saved HTML
was replayed through the deployed transport validation and imported in a DB
transaction. The restricted pre-import snapshot is stored on GCP at
`/opt/coscircle/api/backups/events-before-zenrows-20261006.json` (mode 0600).
The importer processed 49 events; total event rows remained 80 (no new duplicate
rows). A `doujin-source` success record with imported_count 49 was committed.
One existing event (ID 44) changed to rejected under the existing synchronization
rules. Bahamut ID 599 remains approved. There were no additional source requests.
The active release and API/Nginx health checks passed. The existing scheduled
synchronization workflow is not changed by this connector.

Further reconciliation found 15 incoming 2027 entries but only 14 stored: the
existing fingerprint matcher merged IF8 and BIO14 because they share a venue/date.
The fix requires compatible names as well as venues and never merges distinct
Doujin source IDs by fingerprint. Three regression tests cover co-located fairs,
distinct source IDs and legitimate cross-source duplicates. Local Node total: 22
passed. The scraper file hash was checked against the deployed version before
making this narrowly scoped change.

The repair of already merged rows requires separate user confirmation. The planned
transaction preserves BIO14 row ID 610 (and all attendance links), corrects its
source identifier to 2538, and lets the importer create the independent IF8 row
with source identifier 2537. It aborts if the expected BIO14 row has changed.

Active crawler release is now `/opt/coscircle/api/releases/20261006-zenrows-dedup`.
GCP validation: 21 Node tests passed, one local-host test skipped; 17 Python tests
passed. API and Nginx health both returned ok after restart. The second DB repair
has not run pending that separate confirmation. An anonymous event API check
returned 401 as expected; no authenticated App UI test was performed.

## Browser and DataImpulse removal, 2026-10-06

The active release is `/opt/coscircle/api/releases/20261006-zenrows-only`.
Browser fallback code, Chrome impersonation and DataImpulse configuration/setup
modules were removed from the active crawler and repository. Obsolete
`EVENT_SCRAPER_BROWSER_*` and `EVENT_SCRAPER_CHROME_PATH` settings were removed
from GCP and environment templates. Doujin now requires enabled ZenRows
configuration; missing or disabled configuration cannot fall back to direct HTTP.

GCP `google-chrome-stable` was purged. The independent Playwright environment
`/opt/coscircle/browser-diagnostic-20261006` and its dedicated temporary home were
deleted, as was `/etc/coscircle/dataimpulse.json`. Shared system libraries were
not automatically removed. Inactive release history was retained; the user's
local browsers and DataImpulse account/subscription were not changed.

Verification: local 9 Python / 22 Node tests passed; GCP 9 Python / 21 Node tests
passed with one local-host test skipped. Replay of saved HTML parsed 49 events,
without a new source request or DB write. After removal both API and Nginx health
returned ok. Daily sync remains enabled with timezone Asia/Taipei, ZenRows remains
enabled and the surviving environment/credential files retain root:coscircle 0640.
