import {createRequire} from 'node:module';
import fs from 'node:fs';
const require = createRequire((process.env.COSCIRCLE_API_ROOT || '/opt/coscircle/api/current') + '/package.json');
const {applicationDefault, cert} = require('firebase-admin/app');
const project = process.env.FIREBASE_PROJECT_ID || 'coscircle';
const result = {project, permission: 'cloudmessaging.messages.create', canSend: null};
try {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    result.principal = JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8')).client_email;
  }
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const metadata = await fetch('http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email', {headers:{'Metadata-Flavor':'Google'}, signal:AbortSignal.timeout(10000)});
    if (metadata.ok) result.principal = (await metadata.text()).trim();
  }
  const credential = process.env.FIREBASE_SERVICE_ACCOUNT_JSON ? cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)) : applicationDefault();
  const {access_token} = await credential.getAccessToken();
  const response = await fetch('https://cloudresourcemanager.googleapis.com/v1/projects/' + project + ':testIamPermissions', {method:'POST', headers:{Authorization:'Bearer '+access_token,'Content-Type':'application/json'},body:JSON.stringify({permissions:[result.permission]}),signal:AbortSignal.timeout(15000)});
  result.permissionCheckStatus = response.status;
  if (response.ok) result.canSend = (await response.json()).permissions?.includes(result.permission) === true;
  else {const error=await response.json();result.reason=error.error?.status || 'permission_check_failed';}
} catch {result.reason='credential_or_permission_check_unavailable';}
console.log(JSON.stringify(result));
