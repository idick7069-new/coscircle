import 'dotenv/config';
import { createPool } from '../src/db.js';

const apiBaseUrl = String(process.env.API_BASE_URL ?? 'http://34.187.168.222/api')
  .replace(/\/$/, '');
const configuredEventId = process.env.SMOKE_EVENT_ID?.trim();
const password = 'QA0714pass';
const stamp = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);
const qaPrefix = `qa_privacy_${stamp}`;
const ownerEmail = `${qaPrefix}_owner@cos.test`;
const viewerEmail = `${qaPrefix}_viewer@cos.test`;

let pool = null;
const createdUserEmails = [ownerEmail, viewerEmail];
let createdEventSourceKey = null;

async function main() {
  const eventId = await ensureSmokeEvent();
  const registeredOwner = await register(`${qaPrefix}_owner`, ownerEmail);
  const registeredViewer = await register(`${qaPrefix}_viewer`, viewerEmail);

  const owner = await login(ownerEmail);
  const viewer = await login(viewerEmail);
  assert(owner.user.id === registeredOwner.user.id, 'owner login returns registered user');
  assert(viewer.user.id === registeredViewer.user.id, 'viewer login returns registered user');

  await bookEvent(owner.token, eventId, 'coser');
  await bookEvent(viewer.token, eventId, 'self');

  await shareLocation(owner.token, eventId, {
    latitude: 25.033,
    longitude: 121.5654,
    visibility: 'circle',
    expiresInMinutes: 15,
  });

  const ownerLocations = await getLocations(owner.token, eventId);
  assert(
    ownerLocations.some((location) => String(location.userId) === String(owner.user.id)),
    'owner can see their own shared circle location',
  );
  const ownerLocation = ownerLocations.find(
    (location) => String(location.userId) === String(owner.user.id),
  );
  assert(ownerLocation.visibility === 'circle', 'location visibility is circle');
  assert(Boolean(ownerLocation.expiresAt), 'location has expiresAt');

  const publicLocations = await getLocations(viewer.token, eventId);
  assert(
    !publicLocations.some((location) => String(location.userId) === String(owner.user.id)),
    'non-circle viewer cannot see circle location',
  );

  await shareLocation(owner.token, eventId, {
    latitude: 25.0331,
    longitude: 121.5655,
    visibility: 'public',
    expiresInMinutes: 15,
  });
  const publicLocationsAfterUpdate = await getLocations(viewer.token, eventId);
  assert(
    publicLocationsAfterUpdate.some(
      (location) => String(location.userId) === String(owner.user.id),
    ),
    'viewer can see public location',
  );

  await blockUser(viewer.token, owner.user.id);
  const locationsAfterBlock = await getLocations(viewer.token, eventId);
  assert(
    !locationsAfterBlock.some((location) => String(location.userId) === String(owner.user.id)),
    'blocked user disappears from viewer location results',
  );

  await stopSharing(owner.token, eventId);
  const ownerLocationsAfterStop = await getLocations(owner.token, eventId);
  assert(
    !ownerLocationsAfterStop.some((location) => String(location.userId) === String(owner.user.id)),
    'location disappears after stop sharing',
  );

  console.log(
    JSON.stringify(
      {
        ok: true,
        apiBaseUrl,
        eventId,
        ownerId: owner.user.id,
        viewerId: viewer.user.id,
        checked: [
          'register/login',
          'circle visibility hidden from non-circle viewer',
          'public visibility visible',
          'block hides location',
          'stop sharing removes location',
        ],
      },
      null,
      2,
    ),
  );
}

async function ensureSmokeEvent() {
  if (configuredEventId) return configuredEventId;

  const pool = getPool();
  const [existingRows] = await pool.execute(
    `SELECT id
       FROM events
      WHERE status = 'approved'
      ORDER BY start_date DESC, id DESC
      LIMIT 1`,
  );
  if (existingRows[0]?.id) return existingRows[0].id;

  createdEventSourceKey = `qa-privacy-${stamp}`;
  const [result] = await pool.execute(
    `INSERT INTO events (
       source_key, source_type, source_name, category, name,
       start_date, end_date, venue, detailed_address, status
     )
     VALUES (?, 0, 'QA', 'Smoke', 'QA Privacy Smoke Event',
       CURRENT_DATE, CURRENT_DATE, 'QA Venue', 'QA Address', 'approved')`,
    [createdEventSourceKey],
  );
  return result.insertId;
}

async function register(nickname, email) {
  return request('/auth/register', {
    method: 'POST',
    body: { nickname, email, password },
  });
}

async function login(email) {
  const response = await request('/auth/login', {
    method: 'POST',
    body: { email, password },
  });
  assert(response.isNewUser === false, 'login returns existing session');
  return response;
}

async function shareLocation(token, eventId, location) {
  await request(`/events/${eventId}/location`, {
    method: 'PUT',
    token,
    body: location,
    expectJson: false,
  });
}

async function bookEvent(token, eventId, role) {
  await request(`/events/${eventId}/bookings`, {
    method: 'POST',
    token,
    body: { role, dayIndex: 1, presenceStatus: 'open' },
    expectJson: false,
  });
}

async function stopSharing(token, eventId) {
  await request(`/events/${eventId}/location`, {
    method: 'DELETE',
    token,
    expectJson: false,
  });
}

async function blockUser(token, userId) {
  await request(`/users/${userId}/block`, {
    method: 'POST',
    token,
    expectJson: false,
  });
}

async function getLocations(token, eventId) {
  return request(`/events/${eventId}/locations`, { token });
}

async function request(path, options = {}) {
  const headers = {};
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${options.method ?? 'GET'} ${path} failed: ${response.status} ${text}`);
  }
  if (options.expectJson === false || response.status === 204 || text.length === 0) {
    return null;
  }
  return JSON.parse(text);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Privacy smoke failed: ${message}`);
  }
}

async function cleanup() {
  if (!pool) return;
  if (createdUserEmails.length > 0) {
    await pool.execute(
      `DELETE FROM users
        WHERE email IN (${createdUserEmails.map(() => '?').join(', ')})`,
      createdUserEmails,
    );
  }
  if (createdEventSourceKey) {
    await pool.execute('DELETE FROM events WHERE source_key = ?', [createdEventSourceKey]);
  }
  await pool.end();
}

function getPool() {
  pool ??= createPool();
  return pool;
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(cleanup);
