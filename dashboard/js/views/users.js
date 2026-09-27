/* المستخدمون — list, create, edit and delete accounts (via the admin-users function). */
(function () {
  'use strict';
  const { h, icon, toast, openModal, confirmDialog, fmtDateTime } = window.U;

  function setupNotice() {
    return h('div', { class: 'notice warn' }, icon('alert'), h('div', {},
      h('strong', {}, 'إدارة الحسابات تحتاج تفعيل دالة الخادم مرة واحدة. '),
      'من مجلد المشروع نفّذ: ',
      h('code', {}, 'supabase functions deploy admin-users'),
      ' — التفاصيل في ', h('code', {}, 'dashboard/README.md'), '.'));
  }

  function userForm(user) {
    const isEdit = !!user;
    const name = h('input', { class: 'input', id: 'u-name', value: (user && user.username) || '', autocomplete: 'off' });
    const email = h('input', { class: 'input num', id: 'u-email', type: 'email', value: (user && user.email) || '', autocomplete: 'off' });
    const password = h('input', { class: 'input', id: 'u-pass', type: 'password', autocomplete: 'new-password', placeholder: isEdit ? 'اتركها فارغة لعدم التغيير' : '٦ أحرف على الأقل' });
    const role = h('select', { class: 'select', id: 'u-role', disabled: user && user.is_self },
      h('option', { value: 'user', selected: !user || user.role !== 'admin' }, 'مستخدم'),
      h('option', { value: 'admin', selected: user && user.role === 'admin' }, 'مدير'));
    const error = h('div', { class: 'error', role: 'alert' });
    const el = h('div', { class: 'form-grid' },
      h('div', { class: 'field span-12' }, h('label', { for: 'u-name' }, 'الاسم'), name),
      h('div', { class: 'field span-12' }, h('label', { for: 'u-email' }, 'البريد الإلكتروني'), email),
      h('div', { class: 'field span-6' }, h('label', { for: 'u-pass' }, isEdit ? 'كلمة مرور جديدة' : 'كلمة المرور'), password),
      h('div', { class: 'field span-6' }, h('label', { for: 'u-role' }, 'الصلاحية'), role,
        user && user.is_self ? h('div', { class: 'help' }, 'لا يمكنك تغيير صلاحية حسابك') : null),
      h('div', { class: 'span-12' }, error));
    const values = () => ({
      username: name.value.trim(),
      email: email.value.trim(),
      password: password.value,
      role: role.value,
    });
    const validate = () => {
      const v = values();
      if (!v.username || !v.email) return 'الاسم والبريد مطلوبان';
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.email)) return 'البريد الإلكتروني غير صحيح';
      if ((!isEdit || v.password) && v.password.length < 6) return 'كلمة المرور ٦ أحرف على الأقل';
      return null;
    };
    return { el, values, validate, error };
  }

  async function render(root) {
    const Api = window.Api;
    const tbody = h('tbody', {});
    const head = h('div', { class: 'page-head' },
      h('div', {}, h('h2', { class: 'title' }, 'المستخدمون'), h('p', { class: 'lead' }, 'إنشاء الحسابات وتعديلها وحذفها')),
      h('div', { class: 'actions' }, h('button', { class: 'btn primary', onclick: () => edit(null) }, icon('plus'), 'مستخدم جديد')));
    const body = h('div', {});
    root.append(head, body);

    let users = [];
    async function load() {
      body.innerHTML = '';
      body.append(h('div', { class: 'empty-state' }, h('div', { class: 'spinner', style: 'margin:auto' })));
      try {
        users = await Api.listUsers();
      } catch (e) {
        body.innerHTML = '';
        body.append(e.message === 'FUNCTION_MISSING' ? setupNotice() : h('div', { class: 'notice danger' }, icon('alert'), h('div', {}, e.message)));
        return;
      }
      body.innerHTML = '';
      body.append(h('div', { class: 'table-wrap' }, h('table', { class: 'data' },
        h('thead', {}, h('tr', {}, ['الاسم', 'البريد', 'الصلاحية', 'تاريخ الإنشاء', 'آخر دخول', ''].map((t) => h('th', {}, t)))),
        tbody)));
      draw();
    }

    function draw() {
      tbody.innerHTML = '';
      const sorted = users.slice().sort((a, b) => (b.role === 'admin') - (a.role === 'admin') || a.username.localeCompare(b.username, 'ar'));
      for (const u of sorted) {
        tbody.append(h('tr', {},
          h('td', {}, h('div', { class: 'row', style: 'flex-wrap:nowrap' },
            h('span', { class: 'avatar' }, (u.username || u.email || '?').trim().charAt(0)),
            h('div', {}, h('div', { style: 'font-weight:700' }, u.username || '—'), u.is_self ? h('div', { class: 'help' }, 'حسابك') : null))),
          h('td', { class: 'num' }, u.email),
          h('td', {}, u.role === 'admin' ? h('span', { class: 'badge ok' }, 'مدير') : h('span', { class: 'badge plain' }, 'مستخدم')),
          h('td', { class: 'num' }, fmtDateTime(u.created_at)),
          h('td', { class: 'num' }, u.last_sign_in_at ? fmtDateTime(u.last_sign_in_at) : 'لم يدخل بعد'),
          h('td', { class: 'actions' },
            h('button', { class: 'btn ghost icon', title: 'تعديل', 'aria-label': 'تعديل', onclick: () => edit(u) }, icon('edit')),
            u.is_self ? null : h('button', { class: 'btn ghost icon', title: 'حذف', 'aria-label': 'حذف', style: 'color:var(--danger)', onclick: () => remove(u) }, icon('trash')))));
      }
    }

    function edit(user) {
      const form = userForm(user);
      openModal({
        title: user ? `تعديل ${user.username}` : 'مستخدم جديد',
        body: form.el,
        actions: [
          { label: 'إلغاء', kind: 'ghost' },
          { label: user ? 'حفظ' : 'إنشاء الحساب', kind: 'primary', onClick: async () => {
            const problem = form.validate();
            if (problem) { form.error.textContent = problem; return false; }
            const v = form.values();
            try {
              if (user) {
                const changes = { id: user.id, username: v.username, role: v.role };
                if (v.email !== user.email) changes.email = v.email;
                if (v.password) changes.password = v.password;
                await Api.updateUser(changes);
                toast('تم حفظ التعديلات', 'ok');
              } else {
                await Api.createUser(v);
                toast(`تم إنشاء حساب ${v.username}`, 'ok');
              }
              load();
              return true;
            } catch (e) {
              form.error.textContent = e.message === 'FUNCTION_MISSING' ? 'دالة الخادم غير مفعّلة بعد (راجع README).' : e.message;
              return false;
            }
          } },
        ],
      });
    }

    async function remove(user) {
      const ok = await confirmDialog('حذف المستخدم', `سيُحذف حساب ${user.username} (${user.email}) ولن يتمكن من الدخول. الطلبات التي أضافها تبقى.`, { okLabel: 'حذف الحساب', danger: true });
      if (!ok) return;
      try {
        await Api.deleteUser(user.id);
        toast('تم حذف الحساب', 'ok');
        load();
      } catch (e) {
        toast(e.message, 'error');
      }
    }

    load();
  }

  window.Views = window.Views || {};
  window.Views.users = { title: 'المستخدمون', render };
})();
