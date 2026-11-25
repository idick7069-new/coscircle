import {sessionDigest} from './release-security.js';
const name='__Host-coscircle-session';
export function cookieSession(req) {
  return (req.get('cookie')??'').split(';').map(s=>s.trim()).find(s=>s.startsWith(name+'='))?.slice(name.length+1);
}
export function setSessionCookie(res,value,clear=false) {
  res.append('Set-Cookie',`${name}=${clear?'':value}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=${clear?0:30*86400}`);
}
export function browserSessionBoundary(req,res,next) {
  const raw=cookieSession(req);
  if (raw && !req.authSessionDigest) {
    if (!['GET','HEAD','OPTIONS'].includes(req.method) && req.get('origin')!=='https://coscircle.app')return res.status(403).json({error:'invalid_session_origin'});
    req.authSessionDigest=sessionDigest(raw);
  }
  if (req.get('x-coscircle-client')==='web' && req.get('origin')==='https://coscircle.app') {
    const json=res.json.bind(res);
    res.json=body=>{
      if (typeof body?.token==='string' && /^[a-f0-9]{64}$/.test(body.token)) {
        setSessionCookie(res,body.token);
        body={...body,token:'cookie-session'};
      }
      return json(body);
    };
  }
  next();
}
export function registerBrowserSessions(app,pool) {
  const current=async(req)=>{
    if(!req.authSessionDigest)return null;
    const [[user]]=await pool.execute("SELECT id FROM users WHERE session_token=? AND session_expires_at>UTC_TIMESTAMP() AND account_status='active' AND (is_test_account=FALSE OR can_view_test_data=TRUE OR is_admin=TRUE)",[req.authSessionDigest]);
    return user;
  };
  app.get('/api/auth/session',async(req,res,next)=>{
    try{res.set('Cache-Control','no-store');const user=await current(req);res.status(user?200:401).json({authenticated:Boolean(user)});}catch(error){next(error);}
  });
  app.post('/api/auth/session/migrate',async(req,res,next)=>{
    try {
      const raw=/^Bearer ([a-f0-9]{64})$/i.exec(req.get('authorization')??'')?.[1];
      if(req.get('origin')!=='https://coscircle.app'||!req.secure)return res.status(403).json({error:'invalid_session_origin'});
      if(!raw||!await current(req))return res.status(401).json({error:'authentication_required'});
      setSessionCookie(res,raw);res.json({authenticated:true});
    }catch(error){next(error);}
  });
}
