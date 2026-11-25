import crypto from 'node:crypto';
import {fetchLineProfile} from './line-auth.js';

const cookieName = '__Host-coscircle-line';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const random = () => crypto.randomBytes(32).toString('hex');
function fail(code, status = 400) {throw Object.assign(new Error(code), {code, status});}
function readBrowser(req) {
  const value = (req.get('cookie') ?? '').split(';').map(x => x.trim()).find(x => x.startsWith(cookieName+'='))?.slice(cookieName.length+1);
  return typeof value === 'string' && /^[a-f0-9]{64}\.[a-f0-9]{64}$/.test(value) ? value.split('.') : [];
}
function cookie(res, value, clear = false) {
  res.append('Set-Cookie', `${cookieName}=${value}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=${clear ? 0 : 600}`);
}
export function createLineWebLogin(pool, {
  channelId = process.env.LINE_LOGIN_CHANNEL_ID,
  channelSecret = process.env.LINE_LOGIN_CHANNEL_SECRET,
  enabled = process.env.LINE_LOGIN_ENABLED === 'true',
  origin = 'https://coscircle.app',
  fetcher = fetch,
  authenticateLine,
  linkLine,
} = {}) {
  const callback = origin+'/api/auth/line/web/callback';
  const ready = enabled && /^\d+$/.test(channelId ?? '') && typeof channelSecret === 'string' && channelSecret.length >= 16;
  function transport(req) {if (!req.secure) fail('secure_transport_required', 426);}
  function sameOrigin(req) {if (req.get('origin') !== origin) fail('invalid_login_origin', 403);}
  function linkSession(req) {
    const authorization = req.get('authorization');
    const token=req.authSessionDigest ?? (typeof authorization==='string' && /^Bearer \S+$/i.test(authorization) ? authorization.slice(7).trim() : null);
    if (!req.userId || !token) fail('authentication_required', 401);
    return hash(token);
  }
  async function start(req, res, purpose = 'login') {
    transport(req); sameOrigin(req);
    if (!ready) fail('line_login_not_configured', 503);
    const sessionHash = purpose === 'link' ? linkSession(req) : null;
    const id = random(), browser = random(), state = random(), verifier = random(), nonce = random();
    const requested = req.body?.returnPath;
    const returnPath = typeof requested === 'string' && requested.length <= 1024 &&
      /^\/(?!\/)/.test(requested) && !/[\\\x00-\x20]/.test(requested) ? requested : '/';
    await pool.execute('DELETE FROM line_web_logins WHERE expires_at<=UTC_TIMESTAMP()');
    await pool.execute(`INSERT INTO line_web_logins (id,state_hash,browser_hash,verifier,nonce,return_path,purpose,link_user_id,link_session_hash,expires_at)
      VALUES (?,?,?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(), INTERVAL 10 MINUTE))`, [id, hash(state), hash(browser), verifier, nonce, returnPath, purpose, purpose === 'link' ? req.userId : null, sessionHash]);
    cookie(res, id+'.'+browser);
    const url = new URL('https://access.line.me/oauth2/v2.1/authorize');
    url.search = new URLSearchParams({response_type:'code',client_id:channelId,redirect_uri:callback,
      scope:'profile openid',state,nonce,code_challenge:crypto.createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256'}).toString();
    return {url:url.href};
  }
  async function callbackRoute(req, res) {
    transport(req);
    if (!ready) fail('line_login_not_configured', 503);
    const [id, browser] = readBrowser(req);
    const state = req.query.state;
    if (!id || typeof state !== 'string' || !/^[a-f0-9]{64}$/.test(state)) fail('invalid_line_state');
    const [[attempt]] = await pool.execute(`SELECT * FROM line_web_logins WHERE id=? AND browser_hash=?
      AND state_hash=? AND phase='pending' AND expires_at>UTC_TIMESTAMP()`, [id, hash(browser), hash(state)]);
    if (!attempt) fail('invalid_line_state');
    const [claim] = await pool.execute(`UPDATE line_web_logins SET phase='exchanging' WHERE id=? AND phase='pending'`, [id]);
    if (claim.affectedRows !== 1) fail('invalid_line_state');
    const redirect = (status) => origin+'/app/#/'+(attempt.purpose === 'link' ? 'login-methods' : 'login')+'?'+new URLSearchParams({line:status,next:attempt.return_path});
    try {
      if (req.query.error) fail('line_authorization_cancelled');
      if (typeof req.query.code !== 'string' || req.query.code.length > 2048) fail('invalid_line_code');
      const tokenResponse = await fetcher('https://api.line.me/oauth2/v2.1/token', {
        method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:new URLSearchParams({grant_type:'authorization_code',code:req.query.code,redirect_uri:callback,
          client_id:channelId,client_secret:channelSecret,code_verifier:attempt.verifier}),signal:AbortSignal.timeout(8000)});
      if (!tokenResponse.ok) fail('line_authorization_failed');
      const tokens = await tokenResponse.json();
      const profile = await fetchLineProfile(tokens.access_token, {channelId,fetcher});
      if (typeof tokens.id_token !== 'string') fail('invalid_line_id_token');
      const verification = await fetcher('https://api.line.me/oauth2/v2.1/verify', {
        method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:new URLSearchParams({id_token:tokens.id_token,client_id:channelId,nonce:attempt.nonce}),signal:AbortSignal.timeout(8000)});
      if (!verification.ok) fail('invalid_line_id_token');
      const identity = await verification.json();
      if (identity.sub !== profile.id || String(identity.aud) !== channelId || identity.nonce !== attempt.nonce ||
        identity.iss !== 'https://access.line.me' || !Number.isFinite(identity.exp) || identity.exp <= Date.now()/1000) fail('invalid_line_id_token');
      await pool.execute(`UPDATE line_web_logins SET phase='complete',verifier=NULL,nonce=NULL,profile_json=?,
        expires_at=DATE_ADD(UTC_TIMESTAMP(), INTERVAL ${attempt.purpose === 'link' ? 5 : 1} MINUTE) WHERE id=? AND phase='exchanging'`, [JSON.stringify(profile),id]);
      res.redirect(303, redirect('complete'));
    } catch {
      await pool.execute('DELETE FROM line_web_logins WHERE id=?', [id]);
      cookie(res,'',true);
      res.redirect(303,redirect('failed'));
    }
  }
  async function complete(req, res, purpose = 'login') {
    transport(req); sameOrigin(req);
    if (!ready) fail('line_login_not_configured', 503);
    const sessionHash = purpose === 'link' ? linkSession(req) : null;
    const [id,browser] = readBrowser(req);
    if (!id) fail('line_login_expired',purpose === 'link' ? 410 : 401);
    const [[attempt]] = await pool.execute(`SELECT profile_json,purpose,link_user_id,link_session_hash FROM line_web_logins WHERE id=? AND browser_hash=?
      AND phase='complete' AND expires_at>UTC_TIMESTAMP()`,[id,hash(browser)]);
    if (!attempt) fail('line_login_expired',purpose === 'link' ? 410 : 401);
    if (attempt.purpose !== purpose || (purpose === 'link' &&
      (String(attempt.link_user_id) !== String(req.userId) || attempt.link_session_hash !== sessionHash))) fail('line_link_session_changed', 403);
    const password = req.body?.password;
    if (purpose === 'link' && (typeof password !== 'string' || !password || password.length > 1024)) fail('reauthentication_required', 403);
    const [claim] = await pool.execute("DELETE FROM line_web_logins WHERE id=? AND browser_hash=? AND phase='complete' AND expires_at>UTC_TIMESTAMP()",[id,hash(browser)]);
    cookie(res,'',true);
    if (claim.affectedRows !== 1) fail('line_login_expired',purpose === 'link' ? 410 : 401);
    const profile = typeof attempt.profile_json === 'string' ? JSON.parse(attempt.profile_json) : attempt.profile_json;
    return purpose === 'link' ? linkLine({userId:req.userId,lineUserId:profile.id,password}) : authenticateLine(profile);
  }
  return {start,callback:callbackRoute,complete,startLink:(req,res)=>start(req,res,'link'),completeLink:(req,res)=>complete(req,res,'link'),config:() => ({enabled:enabled && /^\d+$/.test(channelId ?? ''),webEnabled:ready,channelId:enabled ? channelId : null})};
}
const route = handler => async (req,res) => {
    res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer'});
    try {const value = await handler(req,res);if (!res.headersSent) res.json(value);}
    catch (error) {
      const codes = ['secure_transport_required','invalid_login_origin','line_login_not_configured','invalid_line_state','line_login_expired','account_suspended','authentication_required','line_link_session_changed','reauthentication_required','line_identity_already_linked'];
      res.status(codes.includes(error.code) ? (error.status ?? (error.code === 'account_suspended' ? 403 : 400)) : 503).json({error:codes.includes(error.code) ? error.code : 'line_login_unavailable'});
    }
  };
export function registerLineWebRoutes(app, service) {
  app.get('/api/auth/line/config',route(async () => service.config()));
  app.post('/api/auth/line/web/start',route(service.start));
  app.get('/api/auth/line/web/callback',route(service.callback));
  app.post('/api/auth/line/web/complete',route(service.complete));
}

export function registerLineWebLinkRoutes(app, service) {
  app.post('/api/me/auth-identities/line/web/start',route(service.startLink));
  app.post('/api/me/auth-identities/line/web/complete',route(service.completeLink));
}
