import crypto from "node:crypto";
import fs from "node:fs";
import { inTransaction } from "./db-transaction.js";

export const appleAuthTables = [
  `CREATE TABLE IF NOT EXISTS apple_auth_challenges (
    id CHAR(64) PRIMARY KEY, nonce CHAR(64) NOT NULL, purpose VARCHAR(16) NOT NULL,
    user_id BIGINT UNSIGNED NULL, session_hash CHAR(64) NULL, expires_at DATETIME NOT NULL,
    KEY idx_apple_challenge_expiry (expires_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS apple_auth_tokens (
    user_id BIGINT UNSIGNED PRIMARY KEY, refresh_token TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`,
];
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
function fail(code, status = 401) {
  throw Object.assign(new Error(code), { code, status });
}
function jsonPart(part) {
  try {
    const value = JSON.parse(Buffer.from(part, "base64url").toString());
    if (!value || typeof value !== "object" || Array.isArray(value))
      fail("invalid_apple_token");
    return value;
  } catch {
    fail("invalid_apple_token");
  }
}
export function verifyAppleJwt(
  token,
  { keys, audience, nonce, now = Date.now() },
) {
  if (typeof token !== "string" || token.length > 16000)
    fail("invalid_apple_token");
  const parts = token.split(".");
  if (parts.length !== 3) fail("invalid_apple_token");
  const header = jsonPart(parts[0]),
    claims = jsonPart(parts[1]);
  if (header.alg !== "RS256" || typeof header.kid !== "string")
    fail("invalid_apple_token");
  const jwk = keys.find(
    (k) =>
      k.kid === header.kid &&
      k.kty === "RSA" &&
      k.alg === "RS256" &&
      k.use === "sig",
  );
  if (!jwk) fail("invalid_apple_token");
  try {
    if (
      !crypto.verify(
        "RSA-SHA256",
        Buffer.from(parts[0] + "." + parts[1]),
        crypto.createPublicKey({ key: jwk, format: "jwk" }),
        Buffer.from(parts[2], "base64url"),
      )
    )
      fail("invalid_apple_token");
  } catch {
    fail("invalid_apple_token");
  }
  const seconds = Math.floor(now / 1000);
  if (
    claims.iss !== "https://appleid.apple.com" ||
    claims.aud !== audience ||
    typeof claims.sub !== "string" ||
    !claims.sub ||
    claims.sub.length > 191 ||
    !Number.isSafeInteger(claims.exp) ||
    claims.exp <= seconds ||
    !Number.isSafeInteger(claims.iat) ||
    claims.iat > seconds + 60 ||
    claims.iat < seconds - 600 ||
    claims.nonce !== nonce
  )
    fail("invalid_apple_token");
  return {
    id: claims.sub,
    email:
      (claims.email_verified === true || claims.email_verified === "true") &&
      typeof claims.email === "string" &&
      claims.email.length <= 191
        ? claims.email
        : null,
  };
}
export function sealAppleToken(token, key, userId) {
  const iv = crypto.randomBytes(12),
    cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(String(userId)));
  return [iv, cipher.update(token, "utf8"), cipher.final(), cipher.getAuthTag()]
    .map((b) => b.toString("base64url"))
    .join(".");
}
export function openAppleToken(value, key, userId) {
  const [iv, data, end, tag] = value
    .split(".")
    .map((v) => Buffer.from(v, "base64url"));
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAAD(Buffer.from(String(userId)));
  decipher.setAuthTag(tag);
  return Buffer.concat([
    decipher.update(data),
    decipher.update(end),
    decipher.final(),
  ]).toString("utf8");
}
export function createAppleAuth(
  pool,
  {
    env = process.env,
    fetchImpl = fetch,
    authenticateApple,
    verifyPassword,
    now = Date.now,
  } = {},
) {
  const audience = env.APPLE_CLIENT_ID ?? "",
    team = env.APPLE_TEAM_ID ?? "",
    kid = env.APPLE_KEY_ID ?? "";
  let privateKey, encryptionKey;
  try {
    if (env.APPLE_PRIVATE_KEY_PATH)
      privateKey = crypto.createPrivateKey(
        fs.readFileSync(env.APPLE_PRIVATE_KEY_PATH),
      );
    if (env.APPLE_TOKEN_ENCRYPTION_KEY)
      encryptionKey = Buffer.from(env.APPLE_TOKEN_ENCRYPTION_KEY, "base64");
  } catch {
    /* Unconfigured deployments expose a disabled capability. */
  }
  const enabled =
    env.APPLE_LOGIN_ENABLED === "true" &&
    Boolean(
      audience &&
        team &&
        kid &&
        privateKey?.asymmetricKeyType === "ec" &&
        privateKey?.asymmetricKeyDetails?.namedCurve === "prime256v1" &&
        encryptionKey?.length === 32,
    );
  let cachedKeys = [],
    keyTime = 0;
  function configured() {
    if (!enabled) fail("apple_login_not_configured", 503);
  }
  function clientSecret() {
    const iat = Math.floor(now() / 1000),
      header = Buffer.from(JSON.stringify({ alg: "ES256", kid })).toString(
        "base64url",
      );
    const payload = Buffer.from(
      JSON.stringify({
        iss: team,
        iat,
        exp: iat + 300,
        aud: "https://appleid.apple.com",
        sub: audience,
      }),
    ).toString("base64url");
    const message = header + "." + payload;
    return (
      message +
      "." +
      crypto
        .sign("sha256", Buffer.from(message), {
          key: privateKey,
          dsaEncoding: "ieee-p1363",
        })
        .toString("base64url")
    );
  }
  async function request(url, options = {}) {
    try {
      return await fetchImpl(url, {
        ...options,
        signal: AbortSignal.timeout(12000),
      });
    } catch {
      fail("apple_login_unavailable", 503);
    }
  }
  async function keys(force = false) {
    if (force || now() - keyTime > 3600000 || !cachedKeys.length) {
      const r = await request("https://appleid.apple.com/auth/keys");
      if (!r.ok) fail("apple_login_unavailable", 503);
      const j = await r.json();
      if (!Array.isArray(j.keys)) fail("apple_login_unavailable", 503);
      cachedKeys = j.keys;
      keyTime = now();
    }
    return cachedKeys;
  }
  async function jwt(token, nonce) {
    const k = jsonPart(String(token).split(".")[0] ?? "").kid;
    let list = await keys();
    if (!list.some((v) => v.kid === k)) list = await keys(true);
    return verifyAppleJwt(token, { keys: list, audience, nonce, now: now() });
  }
  async function challenge({
    purpose = "login",
    userId = null,
    sessionToken = null,
  } = {}) {
    configured();
    if (
      !["login", "link", "delete"].includes(purpose) ||
      (purpose !== "login" && (!userId || !sessionToken))
    )
      fail("invalid_apple_challenge", 400);
    const id = crypto.randomBytes(32).toString("hex"),
      nonce = hash(crypto.randomBytes(32));
    await pool.execute(
      "DELETE FROM apple_auth_challenges WHERE expires_at<=UTC_TIMESTAMP()",
    );
    await pool.execute(
      `INSERT INTO apple_auth_challenges (id,nonce,purpose,user_id,session_hash,expires_at) VALUES (?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 5 MINUTE))`,
      [id, nonce, purpose, userId, sessionToken ? hash(sessionToken) : null],
    );
    return { challengeId: id, nonce };
  }
  async function credential(
    body,
    { purpose = "login", userId = null, sessionToken = null } = {},
  ) {
    configured();
    const { challengeId, identityToken, authorizationCode } = body ?? {};
    if (
      typeof challengeId !== "string" ||
      !/^[a-f0-9]{64}$/.test(challengeId) ||
      typeof identityToken !== "string" ||
      typeof authorizationCode !== "string" ||
      !authorizationCode ||
      authorizationCode.length > 4096
    )
      fail("invalid_apple_credential", 400);
    const [[c]] = await pool.execute(
      `SELECT nonce FROM apple_auth_challenges WHERE id=? AND purpose=? AND user_id <=> ? AND session_hash <=> ? AND expires_at>UTC_TIMESTAMP()`,
      [challengeId, purpose, userId, sessionToken ? hash(sessionToken) : null],
    );
    if (!c) fail("invalid_apple_challenge");
    const profile = await jwt(identityToken, c.nonce);
    const [consumed] = await pool.execute(
      "DELETE FROM apple_auth_challenges WHERE id=? AND expires_at>UTC_TIMESTAMP()",
      [challengeId],
    );
    if (consumed.affectedRows !== 1) fail("invalid_apple_challenge");
    const r = await request("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: audience,
        client_secret: clientSecret(),
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
    });
    if (!r.ok)
      fail(
        r.status >= 500
          ? "apple_login_unavailable"
          : "invalid_apple_credential",
        r.status >= 500 ? 503 : 401,
      );
    const exchanged = await r.json();
    const confirmed = await jwt(exchanged.id_token, c.nonce);
    if (
      confirmed.id !== profile.id ||
      typeof exchanged.refresh_token !== "string" ||
      !exchanged.refresh_token
    )
      fail("invalid_apple_credential");
    return {
      ...profile,
      refreshToken: exchanged.refresh_token,
      nickname: "圈圈新朋友",
      avatarUrl: "",
    };
  }
  async function store(db, userId, profile) {
    await db.execute(
      "INSERT INTO apple_auth_tokens (user_id,refresh_token) VALUES (?,?) ON DUPLICATE KEY UPDATE refresh_token=VALUES(refresh_token)",
      [userId, sealAppleToken(profile.refreshToken, encryptionKey, userId)],
    );
  }
  async function login(body) {
    const profile = await credential(body);
    return authenticateApple(profile, (db, id) => store(db, id, profile));
  }
  async function link(body, { userId, sessionToken }) {
    if (
      typeof body?.password !== "string" ||
      !body.password ||
      body.password.length > 1024
    )
      fail("reauthentication_required", 403);
    const profile = await credential(body, {
      purpose: "link",
      userId,
      sessionToken,
    });
    try {
      return await inTransaction(pool, async (db) => {
        const [[u]] = await db.execute(
          "SELECT session_token, account_status FROM users WHERE id=? FOR UPDATE",
          [userId],
        );
        if (
          !u ||
          u.account_status !== "active" ||
          u.session_token !== sessionToken
        )
          fail("authentication_required");
        const [[email]] = await db.execute(
          "SELECT password_hash FROM user_auth_identities WHERE user_id=? AND provider='email'",
          [userId],
        );
        if (
          !email?.password_hash ||
          !(await verifyPassword(body.password, email.password_hash))
        )
          fail("reauthentication_required", 403);
        const [[other]] = await db.execute(
          "SELECT user_id FROM user_auth_identities WHERE provider='apple' AND provider_user_id=?",
          [profile.id],
        );
        if (other && String(other.user_id) !== String(userId))
          fail("apple_identity_already_linked", 409);
        const [[own]] = await db.execute(
          "SELECT provider_user_id FROM user_auth_identities WHERE user_id=? AND provider='apple'",
          [userId],
        );
        if (own && own.provider_user_id !== profile.id)
          fail("apple_identity_already_linked", 409);
        if (!own)
          await db.execute(
            "INSERT INTO user_auth_identities (user_id,provider,provider_user_id,verified_at) VALUES (?,'apple',?,UTC_TIMESTAMP())",
            [userId, profile.id],
          );
        await store(db, userId, profile);
        return { linked: true };
      });
    } catch (e) {
      if (e.code === "ER_DUP_ENTRY") fail("apple_identity_already_linked", 409);
      throw e;
    }
  }
  async function revoke(db, userId) {
    const [[row]] = await db.execute(
      "SELECT refresh_token FROM apple_auth_tokens WHERE user_id=?",
      [userId],
    );
    if (!row) fail("apple_revocation_unavailable", 503);
    configured();
    let token;
    try {
      token = openAppleToken(row.refresh_token, encryptionKey, userId);
    } catch {
      fail("apple_revocation_unavailable", 503);
    }
    const r = await request("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: audience,
        client_secret: clientSecret(),
        token,
        token_type_hint: "refresh_token",
      }),
    });
    if (!r.ok) fail("apple_revocation_unavailable", 503);
  }
  return { enabled, challenge, credential, login, link, revoke };
}
export function registerAppleRoutes(
  app,
  service,
  { privateRoutes = false, production = false } = {},
) {
  const token = (req) => req.authSessionDigest ??
    /^Bearer ([^\s]+)$/i.exec(req.get("authorization") ?? "")?.[1];
  const route = (fn) => async (req, res, next) => {
    res.set("Cache-Control", "private, no-store");
    try {
      if (production && !req.secure) fail("secure_transport_required", 426);
      await fn(req, res);
    } catch (e) {
      if (e.status) res.status(e.status).json({ error: e.code });
      else if (e.code === "account_suspended")
        res.status(403).json({ error: e.code });
      else if (e.code === "ER_DUP_ENTRY")
        res.status(409).json({ error: "social_identity_conflict" });
      else next(e);
    }
  };
  if (!privateRoutes) {
    app.get(
      "/api/auth/apple/config",
      route(async (_req, res) => res.json({ enabled: service.enabled })),
    );
    app.post(
      "/api/auth/apple/challenge",
      route(async (_req, res) => res.json(await service.challenge())),
    );
    app.post(
      "/api/auth/apple",
      route(async (req, res) => res.json(await service.login(req.body))),
    );
  } else {
    app.post(
      "/api/me/auth-identities/apple/challenge",
      route(async (req, res) => {
        if (!["link", "delete"].includes(req.body?.purpose))
          fail("invalid_apple_challenge", 400);
        return res.json(
          await service.challenge({
            purpose: req.body.purpose,
            userId: req.userId,
            sessionToken: token(req),
          }),
        );
      }),
    );
    app.post(
      "/api/me/auth-identities/apple",
      route(async (req, res) =>
        res.json(
          await service.link(req.body, {
            userId: req.userId,
            sessionToken: token(req),
          }),
        ),
      ),
    );
  }
}
