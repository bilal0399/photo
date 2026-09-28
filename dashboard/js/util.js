/* Small DOM + formatting helpers shared by every view. */
(function () {
  'use strict';

  /** Creates an element: h('div', { class: 'x', onclick: fn }, child, 'text', ...). */
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === null || value === undefined || value === false) continue;
      if (key === 'class') el.className = value;
      else if (key === 'html') el.innerHTML = value;
      else if (key === 'dataset') Object.assign(el.dataset, value);
      else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
      else if (key === 'value') el.value = value;
      else if (value === true) el.setAttribute(key, '');
      else el.setAttribute(key, value);
    }
    append(el, children);
    return el;
  }

  function append(el, children) {
    for (const child of children.flat(Infinity)) {
      if (child === null || child === undefined || child === false) continue;
      el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
  }

  const ICONS = {
    home: '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
    docs: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/><path d="M8 13h8M8 17h5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    images: '<rect x="3" y="5" width="14" height="14" rx="2"/><path d="M7 3h12a2 2 0 0 1 2 2v12"/><circle cx="8" cy="10" r="1.5"/><path d="M17 16l-4-4-7 7"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7"/><path d="M18 14a6 6 0 0 1 3.5 6"/>',
    list: '<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
    backup: '<path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
    upload: '<path d="M12 16V4"/><path d="M7 9l5-5 5 5"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
    trash: '<path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 13h10l1-13"/><path d="M9 7V4h6v3"/>',
    close: '<path d="M6 6l12 12M18 6L6 18"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="M21 15l-5-5L5 21"/>',
    check: '<path d="M5 12l5 5L20 7"/>',
    alert: '<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
    logout: '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3"/><path d="M10 17l-5-5 5-5"/><path d="M5 12h11"/>',
    moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    excel: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 8l8 8M16 8l-8 8"/>',
    rotate: '<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/>',
    scan: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3"/><path d="M7 12h10"/>',
    up: '<path d="M12 19V5M5 12l7-7 7 7"/>',
    down: '<path d="M12 5v14M19 12l-7 7-7-7"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
  };

  function icon(name) {
    const span = document.createElement('span');
    span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
    return span.firstChild;
  }

  /** Arabic-insensitive search key: no diacritics, unified alef/yaa/taa marbuta, Latin digits. */
  function normalize(text) {
    return String(text || '')
      .replace(/[ً-ٰٟـ]/g, '')
      .replace(/[أإآٱ]/g, 'ا')
      .replace(/ى/g, 'ي')
      .replace(/ة/g, 'ه')
      .replace(/ؤ/g, 'و')
      .replace(/ئ/g, 'ي')
      .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
      .replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)))
      .toLowerCase()
      .trim();
  }

  const pad = (n) => String(n).padStart(2, '0');
  const today = () => {
    const d = new Date();
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  };
  const fmtDate = (value) => (value ? String(value).slice(0, 10).split('-').reverse().join('/') : '—');
  const fmtDateTime = (value) => {
    if (!value) return '—';
    const d = new Date(value);
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };
  const fmtNum = (n) => Number(n || 0).toLocaleString('en-US');
  const stamp = () => {
    const d = new Date();
    return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}`;
  };

  // ------------------------------------------------------------- toasts
  let toastRoot = null;
  function toast(message, type) {
    if (!toastRoot) {
      toastRoot = h('div', { class: 'toasts', role: 'status', 'aria-live': 'polite' });
      document.body.append(toastRoot);
    }
    const el = h('div', { class: `toast ${type || ''}` }, message);
    toastRoot.append(el);
    setTimeout(() => el.remove(), type === 'error' ? 6000 : 3200);
  }

  // ------------------------------------------------------------- modals
  /**
   * openModal({ title, body: Node, wide, actions: [{ label, kind, onClick }] })
   * onClick may return false (or a Promise of false) to keep the modal open.
   */
  function openModal({ title, body, wide, actions, onClose }) {
    const close = () => {
      backdrop.remove();
      document.removeEventListener('keydown', onKey);
      if (onClose) onClose();
    };
    const onKey = (e) => {
      if (e.key === 'Escape') close();
    };
    const buttons = (actions || []).map((a) => {
      const btn = h('button', { class: `btn ${a.kind || ''}`, type: 'button' }, a.label);
      btn.addEventListener('click', async () => {
        if (!a.onClick) return close();
        btn.disabled = true;
        try {
          const keep = await a.onClick(btn);
          if (keep !== false) close();
        } finally {
          btn.disabled = false;
        }
      });
      return btn;
    });
    const modal = h('div', { class: `modal ${wide ? 'wide' : ''}`, role: 'dialog', 'aria-modal': 'true' },
      h('div', { class: 'modal-head' },
        h('h3', {}, title),
        h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': 'إغلاق', onclick: close }, icon('close'))),
      h('div', { class: 'modal-body' }, body),
      buttons.length ? h('div', { class: 'modal-foot' }, buttons) : null);
    const backdrop = h('div', { class: 'modal-backdrop' }, modal);
    backdrop.addEventListener('mousedown', (e) => {
      if (e.target === backdrop) close();
    });
    document.addEventListener('keydown', onKey);
    document.body.append(backdrop);
    const focusable = modal.querySelector('input, select, textarea');
    if (focusable) setTimeout(() => focusable.focus(), 30);
    return { close, modal };
  }

  function confirmDialog(title, message, { okLabel = 'تأكيد', danger = false } = {}) {
    return new Promise((resolve) => {
      let answered = false;
      openModal({
        title,
        body: h('p', { style: 'margin:0;white-space:pre-line' }, message),
        actions: [
          { label: 'إلغاء', kind: 'ghost', onClick: () => { answered = true; resolve(false); } },
          { label: okLabel, kind: danger ? 'danger solid' : 'primary', onClick: () => { answered = true; resolve(true); } },
        ],
        onClose: () => { if (!answered) resolve(false); },
      });
    });
  }

  function downloadBlob(blob, name) {
    const url = URL.createObjectURL(blob);
    const a = h('a', { href: url, download: name });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  }

  /**
   * Searchable lookup field. Typing filters the options (Arabic-insensitive);
   * arrows + Enter pick. Starts empty unless `value` is given.
   * onCreate(value) — optional: offers "add to list" for unknown values.
   */
  function combobox({ id, value = '', options = [], placeholder = 'اكتب للبحث…', onChange, onCreate }) {
    const input = h('input', { class: 'input', id, autocomplete: 'off', placeholder, value });
    const list = h('div', { class: 'combo-list', role: 'listbox', hidden: true });
    const root = h('div', { class: 'combo' }, input, list);
    let items = options.slice();
    let active = 0;
    let shown = [];

    const choose = (v) => {
      input.value = v;
      list.hidden = true;
      input.classList.remove('invalid');
      if (onChange) onChange(v);
    };
    const render = () => {
      const q = normalize(input.value);
      shown = items.filter((o) => normalize(o).includes(q));
      // Exact prefix matches first.
      shown.sort((a, b) => normalize(b).startsWith(q) - normalize(a).startsWith(q));
      list.innerHTML = '';
      shown.forEach((o, i) => {
        list.append(h('div', {
          role: 'option',
          class: i === active ? 'active' : '',
          onmousedown: (e) => { e.preventDefault(); choose(o); },
        }, o));
      });
      const typed = input.value.trim();
      if (onCreate && typed && !items.some((o) => normalize(o) === normalize(typed))) {
        list.append(h('div', {
          class: 'add' + (shown.length === active ? ' active' : ''),
          onmousedown: async (e) => {
            e.preventDefault();
            const created = await onCreate(typed);
            if (created) {
              items.push(created);
              choose(created);
            }
          },
        }, `+ إضافة «${typed}» إلى القائمة`));
      } else if (!shown.length) {
        list.append(h('div', { class: 'empty' }, 'لا توجد نتائج'));
      }
      list.hidden = false;
    };

    input.addEventListener('focus', () => { active = 0; render(); });
    input.addEventListener('input', () => { active = 0; render(); });
    input.addEventListener('blur', () => setTimeout(() => { list.hidden = true; }, 120));
    input.addEventListener('keydown', (e) => {
      const count = list.querySelectorAll('[role=option], .add').length;
      if (e.key === 'ArrowDown') { active = Math.min(active + 1, count - 1); render(); e.preventDefault(); }
      else if (e.key === 'ArrowUp') { active = Math.max(active - 1, 0); render(); e.preventDefault(); }
      else if (e.key === 'Enter' && !list.hidden && !e.ctrlKey && !e.metaKey) {
        const el = list.querySelectorAll('[role=option], .add')[active];
        if (el) {
          e.preventDefault();
          el.dispatchEvent(new MouseEvent('mousedown'));
        }
      } else if (e.key === 'Escape') list.hidden = true;
    });

    return {
      el: root,
      input,
      get value() {
        const v = input.value.trim();
        return items.find((o) => normalize(o) === normalize(v)) || '';
      },
      get typed() { return input.value.trim(); },
      set value(v) { input.value = v || ''; },
      setOptions(next) { items = next.slice(); },
      invalid(on) { input.classList.toggle('invalid', on); },
    };
  }

  window.U = {
    h, append, icon, normalize, today, fmtDate, fmtDateTime, fmtNum, stamp, pad,
    toast, openModal, confirmDialog, downloadBlob, combobox,
  };
})();
