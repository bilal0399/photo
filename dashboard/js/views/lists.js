/* القوائم — the lookup lists behind the form dropdowns. */
(function () {
  'use strict';
  const { h, icon, toast, openModal, confirmDialog, fmtNum } = window.U;

  async function render(root) {
    const Api = window.Api;
    await Promise.all([Api.documents(), Api.allOptions()]);
    let active = Api.CATEGORIES[0].key;
    const tabs = h('div', { class: 'tabs', role: 'tablist' });
    const body = h('div', {});

    const values = () => Api.state.options[active] || [];

    function drawTabs() {
      tabs.innerHTML = '';
      for (const c of Api.CATEGORIES) {
        tabs.append(h('button', { role: 'tab', class: c.key === active ? 'on' : '', onclick: () => { active = c.key; drawTabs(); draw(); } },
          c.label, h('span', { class: 'count num' }, (Api.state.options[c.key] || []).length)));
      }
    }

    function draw() {
      body.innerHTML = '';
      const list = values();
      const input = h('input', { class: 'input', placeholder: 'قيمة جديدة…', 'aria-label': 'قيمة جديدة' });
      const add = async () => {
        const v = input.value.trim();
        if (!v) return;
        if (list.includes(v)) { toast('القيمة موجودة مسبقاً', 'error'); return; }
        try {
          await Api.addOption(active, v);
          toast('أُضيفت القيمة', 'ok');
          drawTabs();
          draw();
        } catch (e) { toast(e.message, 'error'); }
      };
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') add(); });

      const rows = list.map((value, i) => {
        const used = Api.usageCount(active, value);
        return h('div', { class: 'list-item' },
          h('div', { class: 'row', style: 'gap:2px;flex-wrap:nowrap' },
            h('button', { class: 'btn ghost icon', title: 'لأعلى', 'aria-label': 'لأعلى', disabled: i === 0, onclick: () => move(i, -1) }, icon('up')),
            h('button', { class: 'btn ghost icon', title: 'لأسفل', 'aria-label': 'لأسفل', disabled: i === list.length - 1, onclick: () => move(i, 1) }, icon('down'))),
          h('div', { class: 'grow' }, h('div', { class: 'title' }, value), h('div', { class: 'meta' }, used ? `مستخدمة في ${fmtNum(used)} طلب` : 'غير مستخدمة')),
          h('button', { class: 'btn ghost icon', title: 'تعديل', 'aria-label': 'تعديل', onclick: () => rename(value, used) }, icon('edit')),
          h('button', { class: 'btn ghost icon', title: 'حذف', 'aria-label': 'حذف', style: 'color:var(--danger)', onclick: () => remove(value, used) }, icon('trash')));
      });

      const note = active === 'recipient' && !list.length
        ? h('div', { class: 'notice' }, icon('info'), h('div', {}, 'القائمة فارغة، فيستخدم التطبيق الجهات الافتراضية: الوزارة، قيادة الفيلق. أضف قيمة لتحلّ محلها.'))
        : null;

      body.append(h('div', { class: 'card stack', style: 'gap:14px' },
        h('div', { class: 'row', style: 'flex-wrap:nowrap' }, input, h('button', { class: 'btn primary', onclick: add }, icon('plus'), 'إضافة')),
        note,
        list.length ? h('div', { class: 'list' }, rows) : h('div', { class: 'empty-state' }, 'لا توجد قيم بعد')));
    }

    async function move(i, delta) {
      const list = values().slice();
      [list[i], list[i + delta]] = [list[i + delta], list[i]];
      try {
        await Api.reorderOptions(active, list);
        draw();
      } catch (e) { toast(e.message, 'error'); }
    }

    function rename(value, used) {
      const input = h('input', { class: 'input', value });
      const follow = h('input', { type: 'checkbox', checked: true });
      openModal({
        title: 'تعديل القيمة',
        body: h('div', { class: 'stack' },
          h('div', { class: 'field' }, h('label', {}, 'القيمة'), input),
          used ? h('label', { class: 'switch' }, follow, `تحديث ${fmtNum(used)} طلب يستخدم القيمة القديمة`) : null),
        actions: [
          { label: 'إلغاء', kind: 'ghost' },
          { label: 'حفظ', kind: 'primary', onClick: async () => {
            const next = input.value.trim();
            if (!next || next === value) return true;
            if (values().includes(next)) { toast('القيمة موجودة مسبقاً', 'error'); return false; }
            try {
              await Api.renameOption(active, value, next, used > 0 && follow.checked);
              toast('تم التعديل', 'ok');
              draw();
              return true;
            } catch (e) { toast(e.message, 'error'); return false; }
          } },
        ],
      });
    }

    async function remove(value, used) {
      const ok = await confirmDialog('حذف القيمة',
        used ? `«${value}» مستخدمة في ${fmtNum(used)} طلب. ستبقى تلك الطلبات كما هي، لكن القيمة لن تظهر في القائمة بعد الآن.` : `حذف «${value}» من القائمة؟`,
        { okLabel: 'حذف', danger: true });
      if (!ok) return;
      try {
        await Api.deleteOption(active, value);
        toast('حُذفت القيمة', 'ok');
        drawTabs();
        draw();
      } catch (e) { toast(e.message, 'error'); }
    }

    root.append(
      h('div', { class: 'page-head' },
        h('div', {}, h('h2', { class: 'title' }, 'القوائم'), h('p', { class: 'lead' }, 'القيم التي تظهر في قوائم الاختيار في التطبيق واللوحة، بالترتيب نفسه'))),
      tabs, body);
    drawTabs();
    draw();
  }

  window.Views = window.Views || {};
  window.Views.lists = { title: 'القوائم', render };
})();
