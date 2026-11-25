import crypto from 'node:crypto';
import {AsyncLocalStorage} from 'node:async_hooks';

const audience = new AsyncLocalStorage();
export const sessionLifetimeDays = 30;
export function sessionDigest(value) {
  if (typeof value !== 'string' || !value || value.length > 191) return null;
  return 'sha256:' + crypto.createHash('sha256').update(value).digest('hex');
}
export function securityBoundary(req, res, next) {
  const raw = /^Bearer ([^\s]+)$/i.exec(req.get('authorization') ?? '')?.[1];
  req.authSessionDigest = sessionDigest(raw);
  res.set('Cache-Control', 'private, no-store');
  audience.run({includeTestData:false, fixtureActor:false, userId:null, admin:false}, next);
}
export function setAudience(user) {
  const scope = audience.getStore();
  if (!scope) return;
  scope.userId = user?.id ?? null;
  scope.admin = Boolean(Number(user?.is_admin ?? user?.isAdmin ?? 0));
  scope.fixtureActor = Boolean(Number(user?.is_test_account ?? user?.isTestAccount ?? 0));
  scope.includeTestData = scope.admin || Boolean(Number(user?.can_view_test_data ?? user?.canViewTestData ?? 0));
}
export function currentAudience() {
  return audience.getStore() ?? {includeTestData:false, fixtureActor:false, userId:null, admin:false};
}
export function visibleRow(alias, type='user') {
  if (!/^[a-z_][a-z0-9_]*$/i.test(alias)) throw new Error('invalid_sql_alias');
  const field = {user:'is_test_account',event:'is_test_event',circle:'is_test_circle',work:'is_test_work'}[type];
  if (!field) throw new Error('invalid_audience_type');
  const fixture = currentAudience().includeTestData ? '1=1' : `${alias}.${field}=FALSE`;
  return type==='user' ? `(${fixture} AND ${alias}.account_status='active')` : fixture;
}
export function canonicalMediaUrl(value) {
  if (typeof value !== 'string') return value;
  try {
    const url = new URL(value);
    if (['coscircle.app','34.187.168.222'].includes(url.hostname) && ['https:','http:'].includes(url.protocol) && !url.username && !url.password && /^\/uploads\/[0-9a-f-]+\.(jpg|png|webp)$/.test(url.pathname)) return 'https://coscircle.app'+url.pathname;
  } catch { /* Non-URL text is unchanged. */ }
  return value;
}
export function canonicalizeMediaInput(value) {
  if (typeof value==='string') return canonicalMediaUrl(value);
  if (Array.isArray(value)) return value.map(canonicalizeMediaInput);
  if (value && typeof value==='object') return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,canonicalizeMediaInput(item)]));
  return value;
}
export function canonicalMediaBoundary(req,_res,next) {
  if (req.body) req.body=canonicalizeMediaInput(req.body);
  next();
}
export function unavailable() {return Object.assign(new Error('resource_not_found'),{status:404,code:'resource_not_found'});}
export async function audienceGuard(pool, req) {
  const checks=[];
  const event=/^\/api\/events\/([1-9]\d*)(?:\/|$)/.exec(req.path);
  if (event) checks.push(['events','is_test_event',event[1]]);
  const user=/^\/api\/(?:users|friend-invites|friends)\/([1-9]\d*)(?:\/|$)/.exec(req.path);
  if (user) checks.push(['users','is_test_account',user[1]]);
  const circle=/^\/api\/circles\/([1-9]\d*)(?:\/|$)/.exec(req.path);
  if (circle) checks.push(['circles','is_test_circle',circle[1]]);
  if (req.body?.eventId && /^[1-9]\d*$/.test(String(req.body.eventId))) checks.push(['events','is_test_event',req.body.eventId]);
  for (const [pattern,table] of [[/^\/api\/recognitions\/([1-9]\d*)\/respond$/, 'event_recognition_requests'],[/^\/api\/friend-requests\/([1-9]\d*)\/respond$/, 'friendships']]) {
    const match=pattern.exec(req.path);
    if(match){const [[row]]=await pool.execute(`SELECT ${table==='friendships'?'requester_id,recipient_id':'requester_user_id AS requester_id,target_user_id AS recipient_id,event_id'} FROM ${table} WHERE id=?`,[match[1]]);if(row){checks.push(['users','is_test_account',row.requester_id],['users','is_test_account',row.recipient_id]);if(row.event_id)checks.push(['events','is_test_event',row.event_id]);}}
  }
  for (const key of ['targetUserId','userId']) {
    if (req.body?.[key] && /^[1-9]\d*$/.test(String(req.body[key]))) checks.push(['users','is_test_account',req.body[key]]);
  }
  if (req.body?.circleId && /^[1-9]\d*$/.test(String(req.body.circleId)))checks.push(['circles','is_test_circle',req.body.circleId]);
  const works=[req.body?.workId,...(Array.isArray(req.body?.pitWorkIds)?req.body.pitWorkIds:[]),...(Array.isArray(req.body?.deepPitWorkIds)?req.body.deepPitWorkIds:[]),...(Array.isArray(req.body?.shallowPitWorkIds)?req.body.shallowPitWorkIds:[])];
  for(const id of new Set(works.filter(v=>v&&/^[1-9]\d*$/.test(String(v)))))checks.push(['works','is_test_work',id]);
  const scope=currentAudience();
  for (const [table,field,id] of checks) {
    const [[row]]=await pool.execute(`SELECT ${field} AS fixture${table==='users'?',account_status':''} FROM ${table} WHERE id=?`,[id]);
    if (!row || (!scope.includeTestData && row.fixture) || (table==='users' && row.account_status!=='active')) throw unavailable();
    if (table==='users' && scope.fixtureActor && !scope.admin && !row.fixture) throw unavailable();
  }
  if (req.path==='/api/circles/join' && typeof req.body?.inviteCode==='string') {
    const [[row]]=await pool.execute('SELECT is_test_circle AS fixture FROM circles WHERE invite_code=?',[req.body.inviteCode]);
    if (row?.fixture && !scope.includeTestData) throw unavailable();
  }
}
