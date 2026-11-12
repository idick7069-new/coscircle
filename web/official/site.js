'use strict';
(() => {
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  function activate(tab, focus) {
    for (const item of tabs) {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    }
    if (focus) tab.focus();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activate(tab, false));
    tab.addEventListener('keydown', event => {
      let next;
      if (['ArrowDown', 'ArrowRight'].includes(event.key)) next = (index + 1) % tabs.length;
      else if (['ArrowUp', 'ArrowLeft'].includes(event.key)) next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); activate(tabs[next], true); }
    });
  });

  if (!document.getElementById('testing-status')) return;
  // URLs are published only after the project's actual tester entries are supplied.
  fetch('/official/android-testing.json?v=20261111-1', { cache: 'no-store' })
    .then(response => { if (!response.ok) throw new Error('configuration unavailable'); return response.json(); })
    .then(config => {
      let ready = 0;
      for (const kind of ['enroll', 'optIn', 'store']) {
        const value = config[kind];
        if (typeof value !== 'string' || !value.trim()) continue;
        let url;
        try { url = new URL(value); } catch { continue; }
        if (url.protocol !== 'https:') continue;
        const link = document.querySelector(`[data-test-link="${kind}"]`);
        link.href = url.href;
        link.hidden = false;
        const pending = document.querySelector(`[data-pending="${kind}"]`);
        if (pending) pending.hidden = true;
        if (kind !== 'store') ready++;
      }
      if (ready === 2) {
        document.getElementById('testing-status').textContent = '測試加入入口已開放。請依序完成以下步驟；這個網站不會自動確認你的 Google 測試資格。';
      }
    })
    .catch(() => {
      document.getElementById('testing-status').textContent = '暫時無法讀取測試加入連結，請稍後重新整理。你也可以先使用 Web App。';
    });
})();
