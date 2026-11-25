'use strict';
(() => {
  const tabs = [...document.querySelectorAll('.journey-steps [role="tab"]')];
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

  const themeDemo = document.getElementById('theme-demo');
  const themeNames = { midnight: '午夜像素', glow: '冷調微光', daylight: '白晝像素' };
  document.querySelectorAll('.palette-list button[data-theme]').forEach(button => {
    button.addEventListener('click', () => {
      if (!themeDemo) return;
      const theme = button.dataset.theme;
      if (!Object.hasOwn(themeNames, theme)) return;
      themeDemo.dataset.theme = theme;
      themeDemo.querySelector('figcaption').textContent = `${themeNames[theme]} · 配色示意`;
      document.querySelectorAll('.palette-list button[data-theme]').forEach(item => {
        item.setAttribute('aria-pressed', String(item === button));
      });
    });
  });

  const meetCopy = {
    self: ['讓大家知道，現在的你。', '主動開啟狀態分享，告訴同好你現在方便認親。可見範圍與分享期限，由你設定。', '我的狀態：歡迎認親', '我的狀態地圖示意', '你在會場入口旁顯示狀態「歡迎認親」。此為範例，非即時定位。'],
    people: ['同一場活動，誰也在這裡？', '查看同活動中，你有權限看到的狀態分享；先看看對方是否方便互動，再打招呼。', '同活動可見狀態：小葵、阿青', '同活動使用者狀態地圖示意', '小葵在水池旁顯示歡迎認親，阿青在休息區顯示忙碌中。此為範例，非即時定位。'],
    gather: ['找到夥伴，約好集合。', '查看集合點與夥伴的位置，向朋友發出認親訊號，把「你在哪裡」變成「待會見」。', '小圈圈夥伴與集合點', '場次集合地圖示意', '你與夥伴沿虛線前往右側集合點。此為範例，非即時定位。'],
  };
  document.querySelectorAll('.meet-steps button').forEach(button => {
    button.addEventListener('click', () => {
      const step = button.dataset.meet;
      if (!Object.hasOwn(meetCopy, step)) return;
      document.querySelectorAll('.meet-steps button').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      document.querySelectorAll('[data-meet-layer]').forEach(layer => {
        if (layer.dataset.meetLayer === step) layer.removeAttribute('hidden');
        else layer.setAttribute('hidden', '');
      });
      ['meet-step-title', 'meet-step-copy', 'meet-legend', 'map-title', 'map-desc'].forEach((id, index) => {
        document.getElementById(id).textContent = meetCopy[step][index];
      });
    });
  });

  if (!document.getElementById('testing-status')) return;
  // URLs are published only after the project's actual tester entries are supplied.
  fetch('/official/android-testing.json?v=20261119-2', { cache: 'no-store' })
    .then(response => { if (!response.ok) throw new Error('configuration unavailable'); return response.json(); })
    .then(config => {
      let ready = 0;
      for (const kind of ['optIn', 'store']) {
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
        ready++;
      }
      if (ready === 2) {
        document.getElementById('testing-status').textContent = '測試與安裝連結已提供。請依序完成以下步驟；實際資格與版本是否可用，以 Google Play 顯示為準。';
      }
    })
    .catch(() => {
      document.getElementById('testing-status').textContent = '可使用下方連結加入測試與前往商店；實際資格與版本是否可用，以 Google Play 顯示為準。';
    });
})();
