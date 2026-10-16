const resendEndpoint = 'https://api.resend.com/emails';
const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$/;

function fail(code, status = 503, retryable = false) {
  throw Object.assign(new Error(code), {code, status, retryable});
}

function emailAddress(value) {
  return typeof value === 'string' && value.length <= 254 && emailPattern.test(value)
    && !/[\r\n]/.test(value);
}

function senderAddress(value) {
  if (typeof value !== 'string' || /[\r\n]/.test(value)) return null;
  const match = value.match(/^[^<>]+ <([^<>]+)>$/);
  const address = match ? match[1] : value;
  return emailAddress(address) ? address : null;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

export function mailConfiguration(env = process.env) {
  const from = String(env.MAIL_FROM || '').trim();
  const apiKey = String(env.RESEND_API_KEY || '').trim();
  const enabled = env.MAIL_ENABLED === 'true';
  const missing = [];
  if (env.MAIL_PROVIDER !== 'resend') missing.push('MAIL_PROVIDER');
  if (!apiKey || /\s/.test(apiKey)) missing.push('RESEND_API_KEY');
  if (!senderAddress(from)) missing.push('MAIL_FROM');
  let origin;
  try {
    const url = new URL(env.PUBLIC_APP_URL);
    if (url.protocol !== 'https:' || url.username || url.password) throw new Error();
    origin = url.origin;
  } catch { missing.push('PUBLIC_APP_URL'); }
  return {enabled, from, apiKey, origin, missing};
}

export function createMailService({env = process.env, fetcher = fetch} = {}) {
  const config = mailConfiguration(env);

  function requireReady() {
    if (!config.enabled) fail('mail_disabled');
    if (config.missing.length) fail('mail_not_configured');
  }

  function actionLink(value) {
    try {
      const url = new URL(value);
      if (url.protocol !== 'https:' || url.origin !== config.origin || url.username || url.password) {
        throw new Error();
      }
      return url.href;
    } catch { fail('invalid_mail_action_url', 400); }
  }

  async function send({to, subject, text, html, requestId}) {
    requireReady();
    if (!emailAddress(to)) fail('invalid_mail_recipient', 400);
    // Reuse the same ID and content when retrying an uncertain delivery.
    if (typeof requestId !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
      fail('invalid_mail_request_id', 400);
    }
    let response;
    try {
      response = await fetcher(resendEndpoint, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
        headers: {
          Authorization: `Bearer ${config.apiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': `coscircle-${requestId}`,
        },
        body: JSON.stringify({from: config.from, to: [to], subject, text, html}),
      });
    } catch {
      // Never log provider errors: they may include keys, recipients or tokens.
      fail('mail_delivery_unknown', 503, true);
    }
    if (!response.ok) {
      if (response.status === 429) fail('mail_rate_limited', 503, true);
      if (response.status >= 500) fail('mail_provider_unavailable', 503, true);
      if ([401, 403].includes(response.status)) fail('mail_provider_configuration_error');
      fail('mail_provider_rejected');
    }
    let result;
    try { result = await response.json(); }
    catch { fail('mail_delivery_unknown', 503, true); }
    if (typeof result?.id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(result.id)) {
      fail('mail_delivery_unknown', 503, true);
    }
    // Acceptance by the provider is not proof of delivery to the inbox.
    return {accepted: true, messageId: result.id};
  }

  async function sendAccountAction({to, actionUrl, requestId, kind}) {
    requireReady();
    const url = actionLink(actionUrl);
    const verification = kind === 'verify-email';
    const title = verification ? '驗證你的電子信箱' : '重設你的密碼';
    const description = verification
      ? '請使用下方連結完成 CosCircle 信箱驗證。'
      : '我們收到你的 CosCircle 密碼重設請求，請使用下方連結設定新密碼。';
    const expiry = verification ? '連結有效期限為 1 小時，且只能使用一次。' : '連結有效期限為 15 分鐘，且只能使用一次。';
    const text = `${description}\n${expiry}\n\n${url}\n\n若不是你本人提出，請忽略這封信。請勿將此連結提供給他人。`;
    const html = `<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"></head><body>
      <h1>CosCircle</h1><h2>${title}</h2><p>${description}</p><p>${expiry}</p>
      <p><a href="${escapeHtml(url)}">${title}</a></p>
      <p>若不是你本人提出，請忽略這封信。請勿將此連結提供給他人。</p>
      </body></html>`;
    return send({to, subject: `CosCircle｜${title}`, text, html, requestId});
  }

  return {
    status: () => ({enabled: config.enabled, configured: config.missing.length === 0,
      missing: [...config.missing]}),
    sendVerification: options => sendAccountAction({...options, kind: 'verify-email'}),
    sendPasswordReset: options => sendAccountAction({...options, kind: 'reset-password'}),
    sendPasswordChanged: ({to, requestId}) => send({to, requestId,
      subject: 'CosCircle｜密碼已重設',
      text: '你的 CosCircle 密碼已重設，原登入狀態已撤銷。若不是你本人操作，請立即透過忘記密碼重新取回帳號。',
      html: '<h1>CosCircle</h1><p>你的密碼已重設，原登入狀態已撤銷。若不是你本人操作，請立即透過忘記密碼重新取回帳號。</p>',
    }),
    sendTest: ({to, requestId}) => send({to, requestId,
      subject: 'CosCircle｜寄信服務測試',
      text: '這是一封 CosCircle 寄信服務測試信。不含登入、驗證或密碼重設連結。',
      html: '<h1>CosCircle</h1><p>寄信服務測試信。不含登入、驗證或密碼重設連結。</p>',
    }),
  };
}
