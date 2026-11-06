(() => {
  'use strict';

  const element = id => document.getElementById(id);
  const loginForm = element('login-form');
  const deleteForm = element('delete-form');
  const email = element('email');
  const loginPassword = element('login-password');
  const deletePassword = element('delete-password');
  const confirmation = element('confirmation');
  const understood = element('understood');
  const loginButton = element('login-button');
  const deleteButton = element('delete-button');
  const cancelButton = element('cancel-button');
  const status = element('status');
  let phase = 'sign-in';
  let token = '';
  let generation = 0;
  let controller;

  function message(text, error = false) {
    status.textContent = text;
    status.dataset.error = String(error);
  }

  function render() {
    const signingIn = phase === 'signing-in';
    const deleting = phase === 'deleting';
    loginForm.hidden = !['sign-in', 'signing-in'].includes(phase);
    deleteForm.hidden = !['confirm', 'deleting'].includes(phase);
    element('done').hidden = phase !== 'done';
    loginForm.setAttribute('aria-busy', String(signingIn));
    deleteForm.setAttribute('aria-busy', String(deleting));
    email.disabled = signingIn;
    loginPassword.disabled = signingIn;
    loginButton.disabled = phase !== 'sign-in';
    deletePassword.disabled = deleting;
    confirmation.disabled = deleting;
    understood.disabled = deleting;
    cancelButton.disabled = deleting;
    deleteButton.disabled = phase !== 'confirm' || !token || !understood.checked ||
      confirmation.value !== 'DELETE' || !deletePassword.value;
  }

  function clearSession() {
    generation += 1;
    controller?.abort();
    token = '';
    loginForm.reset();
    deleteForm.reset();
    element('account-label').textContent = '';
    phase = 'sign-in';
    render();
  }

  async function post(path, body, bearer = '') {
    controller = new AbortController();
    const activeController = controller;
    const timeout = setTimeout(() => activeController.abort(), 20000);
    try {
      const response = await fetch(path, {
        method: 'POST', mode: 'same-origin', credentials: 'omit',
        cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer',
        headers: {'Content-Type': 'application/json', ...(bearer ? {Authorization: `Bearer ${bearer}`} : {})},
        body: JSON.stringify(body), signal: activeController.signal,
      });
      let data = null;
      if (response.status !== 204) {
        try { data = await response.json(); }
        catch { /* A non-JSON response never confirms login or deletion. */ }
      }
      return {status: response.status, ok: response.ok, data};
    } finally {
      clearTimeout(timeout);
    }
  }

  loginForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (phase !== 'sign-in' || !loginForm.reportValidity()) return;
    if (location.protocol !== 'https:') {
      message('請透過 CosCircle 的 HTTPS 網站開啟本頁，再輸入帳號密碼。', true);
      return;
    }
    const current = ++generation;
    const credentials = {email: email.value.trim().toLowerCase(), password: loginPassword.value};
    loginPassword.value = '';
    phase = 'signing-in';
    render();
    message('正在驗證帳號…');
    try {
      const response = await post('/api/auth/login', credentials);
      if (current !== generation) return;
      if (!response.ok) {
        const code = response.data?.error;
        const text = response.status === 429
          ? '嘗試次數過多，請稍後再登入。'
          : code === 'account_suspended'
            ? '此帳號目前無法登入。請使用下方表單申請人工刪除與身分核驗。'
            : response.status === 401
              ? 'Email 或密碼不正確。僅使用 LINE 的帳號請使用下方人工刪除方式。'
              : '目前無法登入。請稍後重試，或使用下方人工刪除方式。';
        throw new Error(text);
      }
      const result = response.data;
      if (typeof result?.token !== 'string' || !/^[^\s]{1,191}$/.test(result.token) ||
          !result.user || typeof result.user !== 'object') {
        throw new Error('無法確認登入結果，請重新登入。');
      }
      token = result.token;
      const nickname = typeof result.user.nickname === 'string' ? result.user.nickname.slice(0, 80) : 'CosCircle 使用者';
      element('account-label').textContent = `${nickname}（${credentials.email}）`;
      deleteForm.reset();
      phase = 'confirm';
      message('登入完成，尚未刪除帳號。請確認帳號並完成第二步。');
      render();
      element('delete-title').focus();
    } catch (error) {
      if (current !== generation) return;
      token = '';
      phase = 'sign-in';
      message(error instanceof TypeError || error.name === 'AbortError'
        ? '連線中斷或逾時，請重新登入。' : error.message || '無法確認登入結果，請重新登入。', true);
      render();
    } finally {
      credentials.password = '';
    }
  });

  for (const input of [deletePassword, confirmation, understood]) {
    input.addEventListener('input', render);
    input.addEventListener('change', render);
  }

  deleteForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (phase !== 'confirm' || !token || !understood.checked ||
        confirmation.value !== 'DELETE' || !deletePassword.value || !deleteForm.reportValidity()) return;
    const current = ++generation;
    const body = {confirmation: 'DELETE', password: deletePassword.value};
    deletePassword.value = '';
    phase = 'deleting';
    render();
    message('正在送出永久刪除請求，請勿重複送出…');
    try {
      const response = await post('/api/me/delete-account', body, token);
      if (current !== generation) return;
      if (response.status === 204) {
        token = '';
        loginForm.reset();
        deleteForm.reset();
        element('account-label').textContent = '';
        phase = 'done';
        message('帳號已刪除。');
        render();
        element('done-title').focus();
        return;
      }
      const code = response.data?.error;
      if (response.status >= 500 || response.ok) throw new Error('uncertain_deletion');
      if (response.status === 401) {
        clearSession();
        message('登入狀態已失效。請重新登入，或使用下方人工刪除方式。', true);
        return;
      }
      phase = 'confirm';
      const text = code === 'reauthentication_required' || code === 'invalid_credentials'
        ? '密碼驗證未通過，請再次輸入目前帳號的密碼。'
        : response.status === 429
          ? '嘗試次數過多，請稍後再操作。'
          : '刪除請求未完成。請確認資料，或使用下方表單聯絡營運團隊核對處理。';
      message(text, true);
      render();
    } catch {
      if (current !== generation) return;
      clearSession();
      message('尚無法確認刪除結果。請先重新登入確認帳號狀態，再決定是否再次提出刪除；需要協助可使用下方聯絡表單。', true);
    } finally {
      body.password = '';
    }
  });

  cancelButton.addEventListener('click', () => {
    if (phase !== 'confirm') return;
    clearSession();
    message('已取消，沒有送出刪除請求。');
    email.focus();
  });
  window.addEventListener('pagehide', clearSession);
  window.addEventListener('pageshow', event => {
    if (event.persisted) {
      clearSession();
      message('請重新登入。');
    }
  });
  clearSession();
})();
