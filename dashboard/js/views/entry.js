/* إدخال سريع — keyboard-first entry of many documents in a row. */
(function () {
  'use strict';
  const { h, icon, toast, fmtDate } = window.U;

  // Kept across visits so a batch can continue where it stopped.
  const memory = {};
  const session = [];

  async function render(root, app) {
    const Api = window.Api;
    await Promise.all([Api.documents(), Api.allOptions()]);

    const log = h('div', { class: 'list' });
    const counter = h('span', { class: 'badge ok plain' });
    const drawLog = () => {
      counter.textContent = `${session.length} في هذه الجلسة`;
      log.innerHTML = '';
      if (!session.length) {
        log.append(h('div', { class: 'help', style: 'padding:8px 0' }, 'ستظهر هنا الطلبات التي تضيفها الآن.'));
        return;
      }
      for (const d of session.slice().reverse().slice(0, 12)) {
        log.append(h('div', { class: 'list-item' },
          h('span', { class: 'badge ok' }, 'حُفظ'),
          h('div', { class: 'grow' },
            h('div', { class: 'title' }, 'كتاب رقم ', h('span', { class: 'num' }, d.book_number || '—')),
            h('div', { class: 'meta' }, `${d.direction} · ${fmtDate(d.doc_date)} · ${d.requester} · ${d.summary}`)),
          d.attachment_path ? h('span', { class: 'badge info plain' }, 'مع صورة') : h('span', { class: 'badge warn plain' }, 'بدون صورة'),
          h('button', {
            class: 'btn ghost icon', title: 'تعديل', 'aria-label': 'تعديل',
            onclick: () => window.DocTools.editDocument(Api.state.documents.find((x) => x.id === d.id) || d, drawLog),
          }, icon('edit'))));
      }
    };

    const form = window.DocForm({
      mode: 'quick',
      memory,
      onSaved: (row) => {
        session.push(row);
        toast(`تم حفظ الكتاب رقم ${row.book_number || ''}`, 'ok');
        drawLog();
      },
    });

    const onKey = (e) => {
      if ((e.ctrlKey || e.metaKey) && (e.key === 'Enter' || e.key.toLowerCase() === 's')) {
        e.preventDefault();
        form.save();
      }
    };
    document.addEventListener('keydown', onKey);
    app.onLeave(() => {
      document.removeEventListener('keydown', onKey);
      form.destroy();
    });

    root.append(
      h('div', { class: 'page-head' },
        h('div', {},
          h('h2', { class: 'title' }, 'إدخال سريع'),
          h('p', { class: 'lead' }, 'بعد الحفظ يبقى التاريخ ونوع الحركة والنوع والجهة، ويتقدّم رقم الكتاب تلقائياً')),
        h('div', { class: 'actions' },
          h('button', { class: 'btn primary', onclick: () => form.save() }, icon('check'), 'حفظ والتالي ', h('span', { class: 'kbd' }, 'Ctrl+Enter')))),
      form.el,
      h('div', { class: 'card', style: 'margin-top:16px' },
        h('div', { class: 'row', style: 'margin-bottom:6px' }, h('h3', { style: 'margin:0;flex:1' }, 'أُضيف الآن'), counter),
        log));
    drawLog();
    form.focus();
  }

  window.Views = window.Views || {};
  window.Views.entry = { title: 'إدخال سريع', render };
})();
