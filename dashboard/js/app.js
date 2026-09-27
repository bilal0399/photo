/* Shell: admin-only sign in, navigation and routing. */
(function () {
  'use strict';
  const { h, icon, toast } = window.U;
  const Api = window.Api;

  const ROUTES = [
    { path: 'overview', label: 'نظرة عامة', icon: 'home', group: 'الأرشيف' },
    { path: 'documents', label: 'الطلبات', icon: 'docs', group: 'الأرشيف' },
    { path: 'entry', label: 'إدخال سريع', icon: 'plus', group: 'الأرشيف' },
    { path: 'bulk', label: 'الصور', icon: 'images', group: 'الأرشيف', count: () => (Api.state.documents || []).filter((d) => !d.attachment_path).length },
    { path: 'users', label: 'المستخدمون', icon: 'users', group: 'الإدارة' },
    { path: 'lists', label: 'القوائم', icon: 'list', group: 'الإدارة' },
    { path: 'backup', label: 'النسخ الاحتياطي', icon: 'backup', group: 'الإدارة' },
  ];

  const root = document.getElementById('app');
  let leaveHandlers = [];
  let shell = null;

  // ---------------------------------------------------------------- theme
  function storedTheme() {
    try { return localStorage.getItem('diwan-theme'); } catch (e) { return null; }
  }
  function applyTheme(theme) {
    if (theme) document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
  }
  function isDark() {
    const t = document.documentElement.dataset.theme;
    return t ? t === 'dark' : window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
  function toggleTheme() {
    const next = isDark() ? 'light' : 'dark';
    applyTheme(next);
    try { localStorage.setItem('diwan-theme', next); } catch (e) { /* per-viewer nicety only */ }
    if (shell) shell.themeBtn.replaceChildren(icon(isDark() ? 'sun' : 'moon'));
  }
  applyTheme(storedTheme());

  // ---------------------------------------------------------------- login
  function showLogin(message) {
    shell = null;
    const email = h('input', { class: 'input num', id: 'l-email', type: 'email', autocomplete: 'username', required: true });
    const password = h('input', { class: 'input', id: 'l-pass', type: 'password', autocomplete: 'current-password', required: true });
    const error = h('div', { class: 'error', role: 'alert' }, message || '');
    const submit = h('button', { class: 'btn primary', type: 'submit', style: 'width:100%;min-height:46px' }, 'دخول');
    const form = h('form', { class: 'stack', style: 'gap:14px' },
      h('div', { class: 'field' }, h('label', { for: 'l-email' }, 'البريد الإلكتروني'), email),
      h('div', { class: 'field' }, h('label', { for: 'l-pass' }, 'كلمة المرور'), password),
      error, submit);
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      submit.disabled = true;
      error.textContent = '';
      try {
        await Api.signIn(email.value, password.value);
        await enter();
      } catch (err) {
        error.textContent = /invalid login/i.test(err.message) ? 'البريد أو كلمة المرور غير صحيحة' : err.message;
      } finally {
        submit.disabled = false;
      }
    });
    root.replaceChildren(h('div', { class: 'login' },
      h('div', { class: 'login-art' },
        h('img', { src: 'assets/logo.png', alt: '' }),
        h('div', { class: 't1' }, 'الجمهورية العربية السورية · وزارة الدفاع'),
        h('div', { class: 't2' }, 'ديوان الفرقة 42'),
        h('div', { class: 't3' }, 'لوحة الإدارة: متابعة الأرشيف، إدخال الطلبات بسرعة، إرفاق الصور دفعة واحدة، وإدارة الحسابات.')),
      h('div', { class: 'login-form' },
        h('div', { class: 'login-card' },
          h('h2', {}, 'تسجيل الدخول'),
          h('p', {}, 'هذه اللوحة متاحة لحسابات المدير فقط'),
          form))));
    email.focus();
  }

  async function enter() {
    const profile = await Api.profile();
    if (!profile) return showLogin();
    if (profile.role !== 'admin') {
      await Api.signOut();
      return showLogin('هذه اللوحة متاحة للمدير فقط. استخدم التطبيق للدخول بحساب مستخدم.');
    }
    buildShell(profile);
    route();
  }

  // ---------------------------------------------------------------- shell
  function buildShell(profile) {
    const nav = h('nav', { class: 'nav', 'aria-label': 'التنقل' });
    let group = '';
    const links = {};
    for (const r of ROUTES) {
      if (r.group !== group) {
        group = r.group;
        nav.append(h('div', { class: 'nav-label' }, group));
      }
      links[r.path] = h('a', { href: `#/${r.path}` }, icon(r.icon), h('span', {}, r.label), r.count ? h('span', { class: 'count num', hidden: true }) : null);
      nav.append(links[r.path]);
    }
    const sidebar = h('aside', { class: 'sidebar' },
      h('div', { class: 'brand' },
        h('img', { src: 'assets/icon.png', alt: '' }),
        h('div', {}, h('div', { class: 'brand-title' }, 'ديوان الفرقة 42'), h('div', { class: 'brand-sub' }, 'لوحة الإدارة'))),
      nav,
      h('div', { class: 'sidebar-foot' }, 'البيانات نفسها التي يستخدمها التطبيق'));
    const title = h('h1', {});
    const themeBtn = h('button', { class: 'btn ghost icon', title: 'تبديل المظهر', 'aria-label': 'تبديل المظهر', onclick: toggleTheme }, icon(isDark() ? 'sun' : 'moon'));
    const topbar = h('header', { class: 'topbar' },
      h('button', { class: 'btn ghost icon menu-btn', 'aria-label': 'القائمة', onclick: () => sidebar.classList.toggle('open') }, icon('menu')),
      title,
      h('span', { class: 'spacer' }),
      themeBtn,
      h('div', { class: 'user-chip' },
        h('div', { class: 'who' }, h('div', { class: 'name' }, profile.username), h('div', { class: 'role' }, 'مدير')),
        h('span', { class: 'avatar' }, profile.username.trim().charAt(0) || '؟')),
      h('button', { class: 'btn ghost icon', title: 'خروج', 'aria-label': 'خروج', onclick: async () => { await Api.signOut(); showLogin(); } }, icon('logout')));
    const content = h('main', { class: 'content', id: 'content', tabindex: -1 });
    root.replaceChildren(h('div', { class: 'shell' }, sidebar, h('div', { class: 'main' }, topbar, content)));
    shell = { sidebar, links, title, content, themeBtn };
  }

  function updateCounts() {
    if (!shell) return;
    for (const r of ROUTES) {
      if (!r.count) continue;
      const badge = shell.links[r.path].querySelector('.count');
      const n = Api.state.documents ? r.count() : 0;
      badge.hidden = !n;
      badge.textContent = n;
      badge.title = 'طلبات بدون مرفق';
    }
  }

  // --------------------------------------------------------------- router
  const app = {
    go(hash, replace) {
      if (replace) location.replace(hash);
      else location.hash = hash;
      if (location.hash === hash) route();
    },
    onLeave(fn) { leaveHandlers.push(fn); },
  };

  let routing = 0;
  async function route() {
    if (!shell) return;
    const [path, query] = location.hash.replace(/^#\/?/, '').split('?');
    const current = ROUTES.find((r) => r.path === path) || ROUTES[0];
    if (!ROUTES.some((r) => r.path === path)) {
      history.replaceState(null, '', `#/${current.path}`);
    }
    for (const fn of leaveHandlers) fn();
    leaveHandlers = [];
    const token = ++routing;
    for (const [p, link] of Object.entries(shell.links)) link.classList.toggle('active', p === current.path);
    shell.sidebar.classList.remove('open');
    shell.title.textContent = current.label;
    document.title = `${current.label} · ديوان الفرقة 42`;
    const page = h('div', {});
    shell.content.replaceChildren(h('div', { class: 'empty-state' }, h('div', { class: 'spinner', style: 'margin:auto' })));
    try {
      await window.Views[current.path].render(page, app, new URLSearchParams(query || ''));
      if (token !== routing) return;
      shell.content.replaceChildren(page);
      updateCounts();
    } catch (e) {
      if (token !== routing) return;
      console.error(e);
      shell.content.replaceChildren(h('div', { class: 'notice danger' }, icon('alert'),
        h('div', {}, h('strong', {}, 'تعذّر تحميل الصفحة. '), e.message,
          /row-level security|permission|JWT/i.test(e.message) ? h('div', {}, 'تحقّق من تطبيق ملف الصلاحيات (README).') : null)));
    }
  }

  window.addEventListener('hashchange', route);
  Api.client.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT' && shell) showLogin('انتهت الجلسة، سجّل الدخول مجدداً');
  });

  (async () => {
    try {
      const session = await Api.currentSession();
      if (session) await enter();
      else showLogin();
    } catch (e) {
      showLogin(e.message);
    }
  })();

  window.addEventListener('unhandledrejection', (e) => {
    const message = e.reason && e.reason.message;
    if (message) toast(message, 'error');
  });
})();
