/* الطلبات — search, filter, view, edit, delete and export. */
(function () {
  'use strict';
  const { h, icon, normalize, fmtDate, fmtNum, toast, openModal, confirmDialog, downloadBlob, stamp } = window.U;

  const PAGE = 50;
  const EXPORT_HEADERS = ['المعرّف', 'رقم الكتاب', 'التاريخ', 'النوع', 'الجهة', 'الحالة', 'الحركة', 'الملخص', 'تاريخ الموافقة'];

  function statusBadge(status) {
    const Api = window.Api;
    const cls = status === Api.APPROVED ? 'ok' : status === 'مرفوض' ? 'danger' : status === Api.DEFAULT_STATUS ? 'warn' : 'plain';
    return h('span', { class: `badge ${cls}` }, status || '—');
  }

  function exportRows(docs) {
    return [EXPORT_HEADERS, ...docs.map((d) => [
      d.document_code || '', d.book_number || '', d.doc_date || '', d.book_type || '', d.requester || '',
      d.status || '', d.direction || '', d.summary || '', d.approval_date || '',
    ])];
  }

  /** Builds an .xlsx with one sheet per { name, rows } (right-to-left). */
  function workbook(sheets) {
    const wb = window.XLSX.utils.book_new();
    wb.Workbook = { Views: [{ RTL: true }] };
    for (const s of sheets) {
      const ws = window.XLSX.utils.aoa_to_sheet(s.rows);
      ws['!cols'] = s.rows[0].map((_, i) => ({ wch: i === 7 ? 60 : 16 }));
      window.XLSX.utils.book_append_sheet(wb, ws, s.name);
    }
    const out = window.XLSX.write(wb, { bookType: 'xlsx', type: 'array' });
    return new Blob([out], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  }

  /** Lazily loads a signed thumbnail when the row scrolls into view. */
  const thumbObserver = 'IntersectionObserver' in window
    ? new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        thumbObserver.unobserve(entry.target);
        window.Api.signedUrl(entry.target.dataset.path).then((url) => {
          if (url) entry.target.src = url;
        });
      }
    }, { rootMargin: '200px' })
    : null;

  function thumb(doc) {
    const Api = window.Api;
    if (!doc.attachment_path) return h('span', { class: 'thumb empty', title: 'بدون مرفق' }, icon('image'));
    if (!Api.isImagePath(doc.attachment_path)) return h('span', { class: 'thumb empty', title: 'ملف' }, icon('docs'));
    const img = h('img', { class: 'thumb', alt: '', loading: 'lazy', dataset: { path: doc.attachment_path } });
    if (thumbObserver) thumbObserver.observe(img);
    else Api.signedUrl(doc.attachment_path).then((u) => { if (u) img.src = u; });
    return img;
  }

  // ---------------------------------------------------------------- detail

  async function showDetail(doc, refresh) {
    const Api = window.Api;
    const imgBox = h('div', { class: 'preview', style: 'min-height:260px' });
    if (doc.attachment_path) {
      imgBox.append(h('div', { class: 'spinner' }));
      Api.signedUrl(doc.attachment_path).then((url) => {
        imgBox.innerHTML = '';
        if (!url) return imgBox.append(h('div', { class: 'placeholder' }, 'تعذّر تحميل المرفق'));
        if (Api.isImagePath(doc.attachment_path)) {
          imgBox.append(h('a', { href: url, target: '_blank', rel: 'noopener', title: 'فتح بالحجم الكامل' }, h('img', { src: url, alt: 'مرفق الكتاب' })));
        } else {
          imgBox.append(h('a', { class: 'btn', href: url, target: '_blank', rel: 'noopener' }, icon('docs'), 'فتح الملف'));
        }
      });
    } else {
      imgBox.append(h('div', { class: 'placeholder' }, icon('image'), h('div', {}, 'لا يوجد مرفق')));
    }
    const kv = (k, v) => [h('div', {}, h('div', { class: 'k' }, k), h('div', { class: 'v' }, v || '—'))];
    const body = h('div', { class: 'grid halves' },
      h('div', { class: 'stack' },
        h('div', { class: 'detail-grid' },
          kv('رقم الكتاب', h('span', { class: 'num' }, doc.book_number || '—')),
          kv('التاريخ', fmtDate(doc.doc_date)),
          kv('نوع الحركة', doc.direction),
          kv('نوع الكتاب', doc.book_type),
          kv(doc.direction === Api.OUTGOING ? 'الجهة المستقبلة' : 'الجهة المقدمة', doc.requester),
          kv('الحالة', statusBadge(doc.status)),
          kv('تاريخ الموافقة', fmtDate(doc.approval_date)),
          kv('المعرّف', h('span', { class: 'num' }, doc.document_code))),
        h('div', {}, h('div', { class: 'k', style: 'font-size:12px;color:var(--subtle)' }, 'الملخص'), h('p', { style: 'margin:4px 0 0;white-space:pre-line' }, doc.summary || '—'))),
      imgBox);

    const modal = openModal({
      title: `كتاب رقم ${doc.book_number || '—'}`,
      body,
      wide: true,
      actions: [
        { label: 'حذف', kind: 'danger', onClick: async () => {
          if (!(await remove(doc))) return false;
          refresh();
        } },
        { label: 'تعديل', kind: 'primary', onClick: () => { setTimeout(() => editDocument(doc, refresh), 0); } },
      ],
    });
    return modal;
  }

  async function remove(doc) {
    const ok = await confirmDialog('حذف الطلب',
      `سيُحذف الكتاب رقم ${doc.book_number || '—'} ومرفقه نهائياً. لا يمكن التراجع.`,
      { okLabel: 'حذف نهائياً', danger: true });
    if (!ok) return false;
    try {
      await window.Api.deleteDocument(doc, true);
      toast('تم حذف الطلب', 'ok');
      return true;
    } catch (e) {
      toast(`تعذّر الحذف: ${e.message}`, 'error');
      return false;
    }
  }

  function editDocument(doc, refresh) {
    const form = window.DocForm({ doc, mode: 'edit' });
    const onKey = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        submit();
      }
    };
    let modal;
    const submit = async () => {
      const row = await form.save();
      if (!row) return false;
      toast('تم حفظ التعديلات', 'ok');
      modal.close();
      refresh();
      return true;
    };
    document.addEventListener('keydown', onKey);
    modal = openModal({
      title: `تعديل الكتاب رقم ${doc.book_number || '—'}`,
      body: form.el,
      wide: true,
      onClose: () => { form.destroy(); document.removeEventListener('keydown', onKey); },
      actions: [
        { label: 'إلغاء', kind: 'ghost' },
        { label: 'حفظ التعديلات', kind: 'primary', onClick: async () => { await submit(); return false; } },
      ],
    });
  }

  // ------------------------------------------------------------------ view

  async function render(root, app, params) {
    const Api = window.Api;
    await Promise.all([Api.documents(), Api.allOptions()]);

    const f = {
      q: params.get('q') || '',
      year: params.get('year') || '',
      month: '',
      direction: params.get('direction') || '',
      type: params.get('type') || '',
      party: params.get('party') || '',
      status: params.get('status') || '',
      attachment: params.get('attachment') || '',
    };
    let sort = { key: 'doc_date', dir: -1 };
    let page = 0;

    const docs = () => Api.state.documents || [];
    const distinct = (col) => [...new Set(docs().map((d) => d[col]).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'ar'));
    const years = () => [...new Set(docs().map((d) => String(d.doc_date || '').slice(0, 4)).filter((y) => /^\d{4}$/.test(y)))].sort().reverse();

    const search = h('input', { class: 'input', type: 'search', placeholder: 'بحث في الملخص أو رقم الكتاب أو الجهة…', value: f.q, 'aria-label': 'بحث' });
    const select = (key, label, values) => {
      const s = h('select', { class: 'select', 'aria-label': label },
        h('option', { value: '' }, label), values.map(([v, l]) => h('option', { value: v, selected: v === f[key] }, l)));
      s.addEventListener('change', () => { f[key] = s.value; page = 0; draw(); });
      return s;
    };
    const pairs = (arr) => arr.map((v) => [v, v]);

    const filters = h('div', { class: 'filters' },
      select('year', 'كل السنوات', pairs(years())),
      select('month', 'كل الأشهر', Array.from({ length: 12 }, (_, i) => [String(i + 1).padStart(2, '0'), `شهر ${i + 1}`])),
      select('direction', 'صادر ووارد', pairs([Api.OUTGOING, Api.INCOMING])),
      select('type', 'كل الأنواع', pairs(distinct('book_type'))),
      select('party', 'كل الجهات', pairs(distinct('requester'))),
      select('status', 'كل الحالات', pairs(distinct('status'))),
      select('attachment', 'المرفق: الكل', [['has', 'مع مرفق'], ['none', 'بدون مرفق']]));

    const countLabel = h('span', {});
    const tbody = h('tbody', {});
    const pager = h('div', { class: 'pager' });
    const head = h('tr', {});
    const columns = [
      { key: null, label: '' },
      { key: 'book_number', label: 'الرقم' },
      { key: 'doc_date', label: 'التاريخ' },
      { key: 'direction', label: 'الحركة' },
      { key: 'book_type', label: 'النوع' },
      { key: 'requester', label: 'الجهة' },
      { key: 'status', label: 'الحالة' },
      { key: null, label: 'الملخص' },
      { key: null, label: '' },
    ];
    for (const c of columns) {
      const th = h('th', { class: c.key ? 'sortable' : '' }, c.label);
      if (c.key) {
        th.addEventListener('click', () => {
          sort = { key: c.key, dir: sort.key === c.key ? -sort.dir : (c.key === 'doc_date' ? -1 : 1) };
          draw();
        });
      }
      head.append(th);
    }

    function filtered() {
      const q = normalize(f.q);
      return docs().filter((d) => {
        const date = String(d.doc_date || '');
        if (f.year && !date.startsWith(f.year)) return false;
        if (f.month && date.slice(5, 7) !== f.month) return false;
        if (f.direction && d.direction !== f.direction) return false;
        if (f.type && d.book_type !== f.type) return false;
        if (f.party && d.requester !== f.party) return false;
        if (f.status && d.status !== f.status) return false;
        if (f.attachment === 'has' && !d.attachment_path) return false;
        if (f.attachment === 'none' && d.attachment_path) return false;
        if (q) {
          const hay = normalize(`${d.book_number} ${d.summary} ${d.requester} ${d.book_type} ${d.document_code}`);
          if (!q.split(/\s+/).every((part) => hay.includes(part))) return false;
        }
        return true;
      });
    }

    function sorted(list) {
      const { key, dir } = sort;
      return list.sort((a, b) => {
        let x = a[key] || '';
        let y = b[key] || '';
        if (key === 'book_number') {
          // A prefixed series ('M-13') sorts as its own block, not as zero.
          const split = (v) => {
            const m = /^(\D*)(\d+)$/.exec(String(v || '').trim());
            return m ? [m[1].toUpperCase(), parseInt(m[2], 10)] : [String(v || ''), 0];
          };
          const [px, nx] = split(x);
          const [py, ny] = split(y);
          return (px === py ? nx - ny : px.localeCompare(py)) * dir;
        }
        return String(x).localeCompare(String(y), 'ar') * dir;
      });
    }

    let current = [];
    function draw() {
      current = sorted(filtered());
      const pages = Math.max(1, Math.ceil(current.length / PAGE));
      page = Math.min(page, pages - 1);
      countLabel.textContent = `${fmtNum(current.length)} من ${fmtNum(docs().length)} طلب`;
      tbody.innerHTML = '';
      const slice = current.slice(page * PAGE, page * PAGE + PAGE);
      for (const d of slice) {
        const tr = h('tr', { class: 'clickable', onclick: () => showDetail(d, draw) },
          h('td', {}, thumb(d)),
          h('td', { class: 'num', style: 'font-weight:700' }, d.book_number || '—'),
          h('td', { class: 'num' }, fmtDate(d.doc_date)),
          h('td', {}, h('span', { class: `badge ${d.direction === Api.OUTGOING ? 'info' : 'plain'}` }, d.direction || '—')),
          h('td', {}, d.book_type || '—'),
          h('td', {}, d.requester || '—'),
          h('td', {}, statusBadge(d.status)),
          h('td', { class: 'summary', title: d.summary || '' }, d.summary || ''),
          h('td', { class: 'actions' },
            h('button', { class: 'btn ghost icon', title: 'تعديل', 'aria-label': 'تعديل', onclick: (e) => { e.stopPropagation(); editDocument(d, draw); } }, icon('edit')),
            h('button', { class: 'btn ghost icon', title: 'حذف', 'aria-label': 'حذف', style: 'color:var(--danger)', onclick: async (e) => { e.stopPropagation(); if (await remove(d)) draw(); } }, icon('trash'))));
        tbody.append(tr);
      }
      if (!slice.length) {
        tbody.append(h('tr', {}, h('td', { colspan: columns.length }, h('div', { class: 'empty-state' }, icon('search'), h('div', {}, 'لا توجد طلبات مطابقة')))));
      }
      pager.innerHTML = '';
      pager.append(
        h('span', {}, `صفحة ${page + 1} من ${pages}`),
        h('div', { class: 'row' },
          h('button', { class: 'btn sm', disabled: page === 0, onclick: () => { page--; draw(); } }, 'السابق'),
          h('button', { class: 'btn sm', disabled: page >= pages - 1, onclick: () => { page++; draw(); } }, 'التالي')));
    }

    let debounce;
    search.addEventListener('input', () => {
      clearTimeout(debounce);
      debounce = setTimeout(() => { f.q = search.value; page = 0; draw(); }, 150);
    });

    const exportBtn = h('button', { class: 'btn', onclick: () => {
      downloadBlob(workbook([{ name: 'الطلبات', rows: exportRows(current) }]), `documents_${stamp()}.xlsx`);
    } }, icon('excel'), 'تصدير Excel');
    const resetBtn = h('button', { class: 'btn ghost', onclick: () => app.go('#/documents', true) }, 'مسح الفلاتر');

    root.append(
      h('div', { class: 'page-head' },
        h('div', {}, h('h2', { class: 'title' }, 'الطلبات'), h('p', { class: 'lead' }, countLabel)),
        h('div', { class: 'actions' }, resetBtn, exportBtn, h('a', { class: 'btn primary', href: '#/entry' }, icon('plus'), 'إضافة'))),
      h('div', { class: 'toolbar' }, h('div', { class: 'search' }, icon('search'), search)),
      filters,
      h('div', { class: 'table-wrap' }, h('table', { class: 'data' }, h('thead', {}, head), tbody)),
      pager);
    draw();
    search.focus();
  }

  window.Views = window.Views || {};
  window.Views.documents = { title: 'الطلبات', render };
  window.DocTools = { workbook, exportRows, statusBadge, showDetail, editDocument };
})();
