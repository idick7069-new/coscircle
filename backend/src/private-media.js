import crypto from 'node:crypto';
import path from 'node:path';
import {canonicalMediaUrl,currentAudience} from './release-security.js';
const filename=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$/;
const origin='https://coscircle.app';
export function mediaName(value) {
  try {const u=new URL(value);const name=u.pathname.slice('/uploads/'.length);return u.origin===origin && u.pathname==='/uploads/'+name && filename.test(name)?name:null;} catch {return null;}
}
export function mayReadMedia({viewer,owner,publicReference,bookingReference,circleMember,blocked}) {
  if (!owner) return false;
  if (viewer?.admin) return true;
  if (owner.account_status!=='active') return false;
  if (owner.is_test_account && !viewer?.includeTestData) return false;
  if (String(owner.id)===String(viewer?.userId)) return true;
  if (blocked) return false;
  return publicReference || (bookingReference && (owner.booking_visibility==='public' || circleMember));
}
export function createPrivateMedia(pool,{key=process.env.MEDIA_SIGNING_KEY,uploadDir,canReadFeedMedia=async()=>({referenced:false,allowed:false}),now=()=>Date.now()}={}) {
  if (typeof key!=='string'||Buffer.from(key,'base64').length!==32) throw Error('media_signing_key_required');
  const secret=Buffer.from(key,'base64');
  const sign=(name,expires,user)=>crypto.createHmac('sha256',secret).update([name,expires,user?.id??0,user?.session_token??'public'].join('\n')).digest('hex');
  async function viewer(id) {
    if (!id) return null;
    const [[u]]=await pool.execute("SELECT id,is_admin,is_test_account,can_view_test_data,session_token FROM users WHERE id=? AND account_status='active' AND session_expires_at>UTC_TIMESTAMP() AND session_token IS NOT NULL",[id]);
    return u??null;
  }
  async function allowed(name,user) {
    const url=origin+'/uploads/'+name;
    const [[tracking]]=await pool.execute('SELECT user_id FROM account_uploads WHERE file_name=?',[name]);
    if (tracking && tracking.user_id==null) return false;
    const [owners]=await pool.execute(`SELECT u.id,u.account_status,u.is_test_account,u.booking_visibility,u.avatar_url,u.other_photo_urls_json,
      EXISTS(SELECT 1 FROM events e WHERE e.image_url=? AND e.status='approved' AND (e.is_test_event=FALSE OR ?) AND u.is_admin=TRUE) AS publicEventReference,
      EXISTS(SELECT 1 FROM event_bookings b JOIN events e ON e.id=b.event_id WHERE b.user_id=u.id AND b.outfit_image_url=? AND e.status='approved' AND (e.is_test_event=FALSE OR ?)) AS bookingReference,
      EXISTS(SELECT 1 FROM circle_members mine JOIN circle_members theirs ON theirs.circle_id=mine.circle_id WHERE mine.user_id=? AND theirs.user_id=u.id) AS circleMember,
      EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_user_id=? AND b.blocked_user_id=u.id) OR (b.blocker_user_id=u.id AND b.blocked_user_id=?)) AS blocked
      FROM users u WHERE ${tracking?'u.id=?':`u.avatar_url=? OR JSON_CONTAINS(COALESCE(u.other_photo_urls_json,'[]'),JSON_QUOTE(?)) OR EXISTS(SELECT 1 FROM event_bookings b WHERE b.user_id=u.id AND b.outfit_image_url=?)`}`,
    [url,Boolean(user?.is_admin||user?.can_view_test_data),url,Boolean(user?.is_admin||user?.can_view_test_data),user?.id??0,user?.id??0,user?.id??0,...(tracking?[tracking.user_id]:[url,url,url])]);
    const feedAccess=await canReadFeedMedia(url,user);
    const scope={userId:user?.id,admin:Boolean(user?.is_admin),includeTestData:Boolean(user?.is_admin||user?.can_view_test_data)};
    // Untracked legacy references must ALL permit access; a copied public reference cannot expose a private original.
    return owners.length>0 && owners.every(owner=>{
      let photos=[];try{photos=JSON.parse(owner.other_photo_urls_json??'[]');}catch{return false;}
      return mayReadMedia({viewer:scope,owner,publicReference:Boolean(feedAccess.allowed)||Boolean(owner.publicEventReference)||owner.avatar_url===url||photos.includes(url),bookingReference:Boolean(owner.bookingReference),circleMember:Boolean(owner.circleMember),blocked:Boolean(owner.blocked)});
    });
  }
  async function grant(value,user) {
    const name=mediaName(value);if(!name) return value;
    if (!await allowed(name,user)) return '';
    const expires=Math.floor(now()/60000)*60+300;
    return `${origin}/uploads/${name}?e=${expires}&v=${user?.id??0}&s=${sign(name,expires,user)}`;
  }
  function responseBoundary(req,res,next) {
    const original=res.json.bind(res);
    res.json=(body)=>{
      (async()=>{
        const user=await viewer(currentAudience().userId ?? (body?.token&&body?.user?.id));
        const cache=new Map();
        async function visit(value) {
          if (typeof value==='string'&&mediaName(value)) {
            const canonical=canonicalMediaUrl(value);
            if(!cache.has(canonical))cache.set(canonical,grant(canonical,user));
            return cache.get(canonical);
          }
          if(Array.isArray(value))return Promise.all(value.map(visit));
          if(value&&typeof value==='object'&&!(value instanceof Date)&&!Buffer.isBuffer(value)){const entries=await Promise.all(Object.entries(value).map(async([k,v])=>[k,await visit(v)]));return Object.fromEntries(entries);}
          return value;
        }
        original(await visit(body));
      })().catch(()=>{if(!res.headersSent)res.status(503);original({error:'media_unavailable'});});
      return res;
    };
    next();
  }
  async function download(req,res) {
    res.set({'Cache-Control':'private, no-store, max-age=0','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'});
    const name=req.params.file;
    const expires=Number(req.query.e),id=String(req.query.v??''),signature=String(req.query.s??'');
    if(!filename.test(name)||!Number.isSafeInteger(expires)||expires<Math.floor(now()/1000)||expires>Math.floor(now()/1000)+300||!/^\d+$/.test(id)||! /^[a-f0-9]{64}$/.test(signature))return res.sendStatus(404);
    try {
      const user=await viewer(id==='0'?null:id);if(id!=='0'&&!user)return res.sendStatus(404);
      if(!crypto.timingSafeEqual(Buffer.from(signature),Buffer.from(sign(name,expires,user)))||!await allowed(name,user))return res.sendStatus(404);
      res.sendFile(path.join(uploadDir,name),{cacheControl:false,dotfiles:'deny'},error=>{if(error&&!res.headersSent)res.sendStatus(404);});
    }catch{return res.sendStatus(404);}
  }
  async function renew(req,res) {
    const value=req.body?.url;
    if (!mediaName(value)) return res.status(400).json({error:'invalid_media_url'});
    try {
      const url=await grant(value,await viewer(currentAudience().userId));
      if(!url)return res.status(404).json({error:'resource_not_found'});
      res.json({url});
    }catch{return res.status(503).json({error:'media_unavailable'});}
  }
  return {grant,download,responseBoundary,renew};
}
