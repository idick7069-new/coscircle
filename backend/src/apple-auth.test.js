import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import {
  verifyAppleJwt,
  sealAppleToken,
  openAppleToken,
  createAppleAuth,
  appleAuthTables,
  registerAppleRoutes,
} from "./apple-auth.js";
const rsa = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 }),
  jwk = {
    ...rsa.publicKey.export({ format: "jwk" }),
    kid: "test-key",
    alg: "RS256",
    use: "sig",
  };
const audience = "com.hikakineame.coscircle",
  now = Date.now(),
  nonce = "a".repeat(64);
function jwt(overrides = {}, header = { alg: "RS256", kid: "test-key" }) {
  const p = [
    header,
    {
      iss: "https://appleid.apple.com",
      aud: audience,
      sub: "apple-subject-1",
      exp: Math.floor(now / 1000) + 300,
      iat: Math.floor(now / 1000),
      nonce,
      ...overrides,
    },
  ].map((x) => Buffer.from(JSON.stringify(x)).toString("base64url"));
  return (
    p.join(".") +
    "." +
    crypto
      .sign("RSA-SHA256", Buffer.from(p.join(".")), rsa.privateKey)
      .toString("base64url")
  );
}
const verify = (t) => verifyAppleJwt(t, { keys: [jwk], audience, nonce, now });
test("Apple identity requires a valid Apple signature, audience, subject, issuer, fresh dates and nonce", () => {
  assert.equal(verify(jwt()).id, "apple-subject-1");
  for (const claim of [
    { iss: "https://attacker.invalid" },
    { aud: "other.bundle" },
    { nonce: "other" },
    { sub: "" },
    { exp: Math.floor(now / 1000) - 1 },
    { iat: Math.floor(now / 1000) - 601 },
    { iat: Math.floor(now / 1000) + 61 },
  ])
    assert.throws(() => verify(jwt(claim)), /invalid_apple_token/);
  assert.throws(
    () => verify(jwt({}, { alg: "none", kid: "test-key" })),
    /invalid_apple_token/,
  );
  const parts = jwt().split(".");
  parts[1] = Buffer.from("{}").toString("base64url");
  assert.throws(() => verify(parts.join(".")), /invalid_apple_token/);
});
test("Apple private relay emails are accepted only when Apple verified the claim", () => {
  assert.equal(
    verify(
      jwt({ email: "test@privaterelay.appleid.com", email_verified: "true" }),
    ).email,
    "test@privaterelay.appleid.com",
  );
  assert.equal(
    verify(jwt({ email: "unverified@example.invalid", email_verified: false }))
      .email,
    null,
  );
});
test("refresh token encryption is randomized and authenticated to user and key", () => {
  const key = crypto.randomBytes(32),
    encrypted = sealAppleToken("private-refresh", key, "1");
  assert(!encrypted.includes("private-refresh"));
  assert.equal(openAppleToken(encrypted, key, "1"), "private-refresh");
  assert.notEqual(encrypted, sealAppleToken("private-refresh", key, "1"));
  assert.throws(() => openAppleToken(encrypted, key, "2"));
  assert.throws(() => openAppleToken(encrypted, crypto.randomBytes(32), "1"));
  const p = encrypted.split(".");
  p[1] = Buffer.from("tampered").toString("base64url");
  assert.throws(() => openAppleToken(p.join("."), key, "1"));
});
function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "coscircle-apple-test-"));
  const ec = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const keyfile = path.join(dir, "key.p8");
  fs.writeFileSync(
    keyfile,
    ec.privateKey.export({ type: "pkcs8", format: "pem" }),
    { mode: 0o600 },
  );
  const db = new DatabaseSync(":memory:");
  db.exec(
    "PRAGMA foreign_keys=ON;CREATE TABLE users(id INTEGER PRIMARY KEY,session_token TEXT,account_status TEXT);CREATE TABLE user_auth_identities(id INTEGER PRIMARY KEY,user_id INTEGER,provider TEXT,provider_user_id TEXT,password_hash TEXT,verified_at TEXT,UNIQUE(provider,provider_user_id),UNIQUE(user_id,provider));INSERT INTO users VALUES(1,'session-one','active'),(2,'session-two','active');INSERT INTO user_auth_identities VALUES(1,1,'email','one@example.invalid','pw',NULL),(2,2,'email','two@example.invalid','pw',NULL);",
  );
  for (const sql of appleAuthTables)
    db.exec(
      sql
        .replace(/^\s*KEY .*\n/gm, "")
        .replace(/ ON UPDATE CURRENT_TIMESTAMP/, "")
        .replace(/ ENGINE=InnoDB/, "")
        .replace(/,\s*\)/g, ")"),
    );
  const execute = async (sql, args = []) => {
    const query = sql
      .replaceAll(" FOR UPDATE", "")
      .replaceAll("<=>", "IS")
      .replaceAll(
        "DATE_ADD(UTC_TIMESTAMP(),INTERVAL 5 MINUTE)",
        "datetime('now','+5 minutes')",
      )
      .replaceAll("UTC_TIMESTAMP()", "datetime('now')")
      .replace(
        "ON DUPLICATE KEY UPDATE refresh_token=VALUES(refresh_token)",
        "ON CONFLICT(user_id) DO UPDATE SET refresh_token=excluded.refresh_token",
      );
    const stmt = db.prepare(query);
    return sql.startsWith("SELECT")
      ? [stmt.all(...args)]
      : [{ affectedRows: Number(stmt.run(...args).changes) }];
  };
  const pool = {
    execute,
    getConnection: async () => ({
      execute,
      beginTransaction: async () => db.exec("BEGIN"),
      commit: async () => db.exec("COMMIT"),
      rollback: async () => db.exec("ROLLBACK"),
      release() {},
    }),
  };
  let exchanges = 0,
    revocations = 0;
  let failRevoke = false;
  const service = createAppleAuth(pool, {
    env: {
      APPLE_LOGIN_ENABLED: "true",
      APPLE_CLIENT_ID: audience,
      APPLE_TEAM_ID: "TEAM123456",
      APPLE_KEY_ID: "KEY1234567",
      APPLE_PRIVATE_KEY_PATH: keyfile,
      APPLE_TOKEN_ENCRYPTION_KEY: Buffer.alloc(32, 1).toString("base64"),
    },
    verifyPassword: async (p, h) => p === h,
    now: () => now,
    fetchImpl: async (url, options) => {
      if (url.endsWith("/keys")) return Response.json({ keys: [jwk] });
      if (url.endsWith("/token")) {
        exchanges++;
        const secret = options.body.get("client_secret").split(".");
        assert.equal(
          JSON.parse(Buffer.from(secret[1], "base64url")).sub,
          audience,
        );
        assert(
          crypto.verify(
            "sha256",
            Buffer.from(secret.slice(0, 2).join(".")),
            { key: ec.publicKey, dsaEncoding: "ieee-p1363" },
            Buffer.from(secret[2], "base64url"),
          ),
        );
        const [[c]] = await pool.execute(
          "SELECT nonce FROM apple_auth_challenges ORDER BY rowid DESC LIMIT 1",
        );
        return Response.json({
          id_token: jwt({ nonce: c?.nonce ?? latestNonce }),
          refresh_token: "refresh-secret",
        });
      }
      revocations++;
      return new Response("", { status: failRevoke ? 500 : 200 });
    },
    authenticateApple: async (profile, store) => {
      assert.equal(profile.id, "apple-subject-1");
      await store(pool, 1);
      return { token: "new-session", user: { id: "1" }, isNewUser: false };
    },
  });
  let latestNonce;
  const challenge = async (context) => {
    const c = await service.challenge(context);
    latestNonce = c.nonce;
    return {
      ...c,
      identityToken: jwt({ nonce: c.nonce }),
      authorizationCode: "valid-code",
    };
  };
  return {
    db,
    pool,
    service,
    challenge,
    get exchanges() {
      return exchanges;
    },
    get revocations() {
      return revocations;
    },
    set failRevoke(v) {
      failRevoke = v;
    },
    close() {
      db.close();
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}
test("unconfigured deployment advertises disabled and cannot mint a challenge", async () => {
  const s = createAppleAuth({}, { env: {} });
  assert.equal(s.enabled, false);
  await assert.rejects(
    s.challenge(),
    (e) => e.code === "apple_login_not_configured",
  );
});
test("login consumes the challenge and stores an encrypted token; replay cannot reach Apple exchange", async () => {
  const f = fixture();
  try {
    const body = await f.challenge();
    assert.equal((await f.service.login(body)).user.id, "1");
    const [rows] = await f.pool.execute(
      "SELECT refresh_token FROM apple_auth_tokens WHERE user_id=1",
    );
    assert(rows[0]);
    assert(!rows[0].refresh_token.includes("refresh-secret"));
    await assert.rejects(
      f.service.login(body),
      (e) => e.code === "invalid_apple_challenge",
    );
    assert.equal(f.exchanges, 1);
  } finally {
    f.close();
  }
});
test("wrong nonce and expired challenges are rejected before token exchange", async () => {
  const f = fixture();
  try {
    const body = await f.challenge();
    await assert.rejects(
      f.service.login({ ...body, identityToken: jwt({ nonce: "wrong" }) }),
      (e) => e.code === "invalid_apple_token",
    );
    await f.pool.execute(
      "UPDATE apple_auth_challenges SET expires_at='2000-01-01'",
      [],
    );
    await assert.rejects(
      f.service.login(body),
      (e) => e.code === "invalid_apple_challenge",
    );
    assert.equal(f.exchanges, 0);
  } finally {
    f.close();
  }
});
test("private challenge is bound to purpose, current user and session; linking requires email reauthentication", async () => {
  const f = fixture();
  try {
    let body = await f.challenge({
      purpose: "link",
      userId: 1,
      sessionToken: "session-one",
    });
    await assert.rejects(
      f.service.login(body),
      (e) => e.code === "invalid_apple_challenge",
    );
    await assert.rejects(
      f.service.link(
        { ...body, password: "pw" },
        { userId: 2, sessionToken: "session-two" },
      ),
      (e) => e.code === "invalid_apple_challenge",
    );
    assert.deepEqual(
      await f.service.link(
        { ...body, password: "pw" },
        { userId: 1, sessionToken: "session-one" },
      ),
      { linked: true },
    );
    const [rows] = await f.pool.execute(
      "SELECT user_id FROM user_auth_identities WHERE provider='apple'",
    );
    assert.equal(rows[0].user_id, 1);
    body = await f.challenge({
      purpose: "link",
      userId: 2,
      sessionToken: "session-two",
    });
    await assert.rejects(
      f.service.link(
        { ...body, password: "pw" },
        { userId: 2, sessionToken: "session-two" },
      ),
      (e) => e.code === "apple_identity_already_linked",
    );
  } finally {
    f.close();
  }
});
test("revocation fails closed and never deletes the stored token itself before account transaction completes", async () => {
  const f = fixture();
  try {
    await f.service.login(await f.challenge());
    f.failRevoke = true;
    await assert.rejects(
      f.service.revoke(f.pool, 1),
      (e) => e.code === "apple_revocation_unavailable",
    );
    f.failRevoke = false;
    await f.service.revoke(f.pool, 1);
    assert.equal(f.revocations, 2);
    assert.equal(
      (
        await f.pool.execute("SELECT COUNT(*) AS n FROM apple_auth_tokens")
      )[0][0].n,
      1,
    );
  } finally {
    f.close();
  }
});
test("routes register public and private operations separately", () => {
  const paths = [];
  const app = { get: (p) => paths.push(p), post: (p) => paths.push(p) };
  registerAppleRoutes(app, {});
  assert.deepEqual(paths, [
    "/api/auth/apple/config",
    "/api/auth/apple/challenge",
    "/api/auth/apple",
  ]);
  paths.length = 0;
  registerAppleRoutes(app, {}, { privateRoutes: true });
  assert.deepEqual(paths, [
    "/api/me/auth-identities/apple/challenge",
    "/api/me/auth-identities/apple",
  ]);
});

test("simultaneous replay of the same challenge reaches Apple token exchange only once", async () => {
  const f = fixture();
  try {
    const body = await f.challenge();
    const results = await Promise.allSettled([
      f.service.login(body),
      f.service.login(body),
    ]);
    assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
    assert.equal(f.exchanges, 1);
  } finally {
    f.close();
  }
});
