/* الصور — attach many files by name, and reprocess old images in bulk. */
(function () {
  'use strict';
  const { h, icon, toast, fmtNum, fmtDate, confirmDialog, downloadBlob, stamp } = window.U;

  const FILTERS = [['auto', 'تحسين تلقائي'], ['grayscale', 'رمادي'], ['blackWhite', 'أبيض وأسود']];
  const CONCURRENCY = 3;

  /** Runs `task` over `items`, `limit` at a time; stops starting new ones when cancelled. */
  async function pool(items, limit, task, isCancelled) {
    let next = 0;
    const worker = async () => {
      while (next < items.length && !isCancelled()) {
        const i = next++;
        await task(items[i], i);
      }
    };
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  }

  function filterSeg(state) {
    const seg = h('div', { class: 'seg' });
    const draw = () => {
      seg.innerHTML = '';
      for (const [key, label] of FILTERS) {
        seg.append(h('button', { type: 'button', class: state.filter === key ? 'on' : '', onclick: () => { state.filter = key; draw(); } }, label));
      }
    };
    draw();
    return seg;
  }

  function progressBlock() {
    const bar = h('div', { style: 'width:0%' });
    const label = h('div', { class: 'help', style: 'text-align:center' });
    const el = h('div', { class: 'stack', style: 'gap:8px', hidden: true }, h('div', { class: 'progress' }, bar), label);
    return {
      el,
      set(done, total, text) {
        el.hidden = false;
        bar.style.width = `${total ? (done / total) * 100 : 0}%`;
        label.textContent = `${done} / ${total}${text ? ` — ${text}` : ''}`;
      },
      hide() { el.hidden = true; },
    };
  }

  // ------------------------------------------------------ attach by file name

  function attachTab(app) {
    const Api = window.Api;
    const M = window.BulkMatch;
    const state = { files: [], year: '', direction: '', replace: false, enhance: true, filter: 'auto', running: false, cancel: false };

    const input = h('input', { type: 'file', multiple: true, accept: '.jpg,.jpeg,.png,.pdf', hidden: true });
    const folderInput = h('input', { type: 'file', multiple: true, webkitdirectory: true, hidden: true });
    const drop = h('div', { class: 'dropzone', tabindex: 0, role: 'button' },
      icon('images'),
      h('div', { class: 'big' }, 'اسحب الصور هنا أو اضغط للاختيار'),
      h('div', { class: 'small' }, 'كل ملف باسم رقم الكتاب: 7.jpg يُرفق بالطلب رقم 7 · تُقبل ٧ و 007'));
    const addFiles = (list) => {
      const known = new Set(state.files.map((f) => `${f.name}|${f.size}`));
      for (const f of list) if (!known.has(`${f.name}|${f.size}`)) state.files.push(f);
      draw();
    };
    drop.addEventListener('click', () => input.click());
    drop.addEventListener('keydown', (e) => { if (e.key === 'Enter') input.click(); });
    drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
    drop.addEventListener('dragleave', () => drop.classList.remove('over'));
    drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); addFiles([...e.dataTransfer.files]); });
    input.addEventListener('change', () => { addFiles([...input.files]); input.value = ''; });
    folderInput.addEventListener('change', () => { addFiles([...folderInput.files]); folderInput.value = ''; });

    const years = [...new Set((Api.state.documents || []).map((d) => String(d.doc_date || '').slice(0, 4)).filter((y) => /^\d{4}$/.test(y)))].sort().reverse();
    const yearSel = h('select', { class: 'select', onchange: () => { state.year = yearSel.value; draw(); } },
      h('option', { value: '' }, 'كل السنوات'), years.map((y) => h('option', { value: y }, y)));
    const dirSel = h('select', { class: 'select', onchange: () => { state.direction = dirSel.value; draw(); } },
      h('option', { value: '' }, 'صادر ووارد'), h('option', { value: Api.OUTGOING }, Api.OUTGOING), h('option', { value: Api.INCOMING }, Api.INCOMING));
    const replaceBox = h('input', { type: 'checkbox', onchange: () => { state.replace = replaceBox.checked; draw(); } });
    const enhanceBox = h('input', { type: 'checkbox', checked: true, onchange: () => { state.enhance = enhanceBox.checked; filters.hidden = !state.enhance; } });
    const filters = filterSeg(state);

    const summary = h('div', { class: 'row' });
    const tbody = h('tbody', {});
    const table = h('div', { class: 'table-wrap', hidden: true },
      h('table', { class: 'data' },
        h('thead', {}, h('tr', {}, h('th', {}, 'الملف'), h('th', {}, 'الرقم'), h('th', {}, 'الطلب'), h('th', {}, 'الحالة'), h('th', {}, ''))),
        tbody));
    const startBtn = h('button', { class: 'btn primary', onclick: () => start() }, icon('upload'), 'إرفاق');
    const cancelBtn = h('button', { class: 'btn', hidden: true, onclick: () => { state.cancel = true; cancelBtn.disabled = true; cancelBtn.textContent = 'جارٍ الإيقاف…'; } }, 'إيقاف');
    const progress = progressBlock();
    const results = h('div', {});

    let items = [];
    function draw() {
      items = M.plan(state.files, Api.state.documents || [], { year: state.year, direction: state.direction, replaceExisting: state.replace });
      const ready = items.filter((i) => M.willUpload(i.status)).length;
      summary.innerHTML = '';
      const counts = {};
      for (const i of items) counts[i.status] = (counts[i.status] || 0) + 1;
      for (const [status, n] of Object.entries(counts)) {
        const cls = M.willUpload(status) ? 'ok' : status === 'hasAttachment' ? 'plain' : 'warn';
        summary.append(h('span', { class: `badge ${cls}` }, `${M.STATUS[status]}: ${n}`));
      }
      startBtn.disabled = state.running || ready === 0;
      startBtn.lastChild.textContent = ready ? `إرفاق ${ready} ملف` : 'لا توجد ملفات جاهزة';
      table.hidden = items.length === 0;
      tbody.innerHTML = '';
      for (const item of items) {
        const d = item.doc;
        const ok = M.willUpload(item.status);
        const detail = item.status === 'ambiguous'
          ? item.candidates.map((c) => `${c.direction} ${fmtDate(c.doc_date)}`).join('، ')
          : d ? `${d.direction} · ${fmtDate(d.doc_date)} · ${d.summary || ''}` : '';
        tbody.append(h('tr', {},
          h('td', { class: 'num' }, item.file.name),
          h('td', { class: 'num' }, item.number || '—'),
          h('td', { class: 'summary', title: detail }, detail || '—'),
          h('td', {}, h('span', { class: `badge ${ok ? 'ok' : item.status === 'hasAttachment' ? 'plain' : 'warn'}` }, M.STATUS[item.status])),
          h('td', { class: 'actions' }, h('button', {
            class: 'btn ghost icon', 'aria-label': 'إزالة', title: 'إزالة', disabled: state.running,
            onclick: () => { state.files.splice(state.files.indexOf(item.file), 1); draw(); },
          }, icon('close')))));
      }
    }

    async function start() {
      const work = items.filter((i) => M.willUpload(i.status));
      const replacing = work.filter((i) => i.status === 'replaces').length;
      const ok = await confirmDialog('تأكيد الإرفاق',
        `سيتم إرفاق ${work.length} ملف بطلباتها${state.enhance ? ' بعد اقتصاص الصور وتحسينها' : ''}.` +
        (replacing ? `\n\nسيُستبدل المرفق الحالي لـ ${replacing} طلب ويُحذف القديم نهائياً.` : ''),
        { okLabel: 'ابدأ' });
      if (!ok) return;
      state.running = true;
      state.cancel = false;
      cancelBtn.hidden = false;
      cancelBtn.disabled = false;
      cancelBtn.textContent = 'إيقاف';
      startBtn.disabled = true;
      results.innerHTML = '';
      const report = { cropped: 0, enhanced: 0, attached: 0, failed: [] };
      let done = 0;
      progress.set(0, work.length);
      await pool(work, CONCURRENCY, async (item) => {
        try {
          const isImage = Api.isImagePath(item.file.name);
          if (state.enhance && isImage) {
            const scan = await window.ScannerPool.scan(item.file, { filter: state.filter });
            await Api.setAttachment(item.doc, scan.blob, scan.extension, { scanned: true, deleteOld: true });
            report[scan.autoDetected ? 'cropped' : 'enhanced']++;
          } else {
            await Api.setAttachment(item.doc, item.file, Api.extOf(item.file.name), { scanned: false, deleteOld: true });
            report.attached++;
          }
          state.files.splice(state.files.indexOf(item.file), 1);
        } catch (e) {
          report.failed.push({ item, message: e.message });
        }
        done++;
        progress.set(done, work.length, `كتاب ${item.number}`);
      }, () => state.cancel);
      state.running = false;
      cancelBtn.hidden = true;
      await Api.documents(true);
      draw();
      results.append(h('div', { class: 'card' },
        h('h3', {}, 'النتيجة'),
        h('div', { class: 'row' },
          report.cropped ? h('span', { class: 'badge ok' }, `اقتصاص وتحسين: ${report.cropped}`) : null,
          report.enhanced ? h('span', { class: 'badge info' }, `تحسين فقط: ${report.enhanced}`) : null,
          report.attached ? h('span', { class: 'badge plain' }, `كما هي: ${report.attached}`) : null,
          report.failed.length ? h('span', { class: 'badge danger' }, `فشل: ${report.failed.length}`) : null),
        report.failed.map((f) => h('div', { class: 'list-item' }, icon('alert'), h('div', { class: 'grow' }, h('div', { class: 'title' }, f.item.file.name), h('div', { class: 'meta' }, f.message))))));
      toast(`تم إرفاق ${done - report.failed.length} ملف`, report.failed.length ? 'error' : 'ok');
    }

    const missing = (Api.state.documents || []).filter((d) => !d.attachment_path).length;
    const el = h('div', { class: 'stack' },
      h('div', { class: 'notice' }, icon('info'), h('div', {},
        h('strong', {}, `طلبات بدون مرفق: ${fmtNum(missing)}. `),
        'سمِّ كل صورة برقم الكتاب واسحبها كلها مرة واحدة؛ ستُطابق كل صورة مع طلبها وتُقتص وتُحسَّن قبل الرفع. ',
        h('a', { href: '#/documents?attachment=none' }, 'عرض الطلبات بدون مرفق'))),
      drop, input, folderInput,
      h('div', { class: 'row' }, h('button', { class: 'btn sm', onclick: () => folderInput.click() }, icon('folder'), 'اختيار مجلد كامل')),
      h('div', { class: 'card stack', style: 'gap:14px' },
        h('div', { class: 'form-grid' },
          h('div', { class: 'field span-6' }, h('label', {}, 'السنة'), yearSel),
          h('div', { class: 'field span-6' }, h('label', {}, 'نوع الحركة'), dirSel),
          h('div', { class: 'help span-12' }, 'حدِّد السنة أو نوع الحركة إذا كان رقم الكتاب يتكرر بينها.')),
        h('label', { class: 'switch' }, enhanceBox, 'اقتصاص الصور وتحسينها قبل الإرفاق'),
        filters,
        h('label', { class: 'switch' }, replaceBox, 'استبدال المرفق إذا كان للطلب مرفق مسبقاً')),
      summary,
      h('div', { class: 'row' }, startBtn, cancelBtn, h('button', { class: 'btn ghost', onclick: () => { state.files = []; draw(); } }, 'مسح القائمة')),
      progress.el,
      results,
      table);
    draw();
    return el;
  }

  // ------------------------------------------------------- reprocess old ones

  function rescanTab() {
    const Api = window.Api;
    const state = { filter: 'auto', deleteOld: true, running: false, cancel: false };
    const pending = () => (Api.state.documents || []).filter((d) =>
      d.attachment_path && Api.isImagePath(d.attachment_path) && !d.attachment_path.startsWith(Api.SCANNED_PREFIX));

    const count = h('strong', {});
    const deleteBox = h('input', { type: 'checkbox', checked: true, onchange: () => { state.deleteOld = deleteBox.checked; } });
    const startBtn = h('button', { class: 'btn primary', onclick: () => start() }, icon('scan'), 'بدء المعالجة');
    const backupBtn = h('button', { class: 'btn', onclick: () => backupOriginals() }, icon('backup'), 'تنزيل الأصول أولاً (ZIP)');
    const cancelBtn = h('button', { class: 'btn', hidden: true, onclick: () => { state.cancel = true; cancelBtn.disabled = true; } }, 'إيقاف');
    const progress = progressBlock();
    const results = h('div', {});

    const refresh = () => {
      const n = pending().length;
      count.textContent = fmtNum(n);
      startBtn.disabled = state.running || n === 0;
      backupBtn.disabled = state.running || n === 0;
    };

    async function backupOriginals() {
      const list = pending();
      const zip = new window.JSZip();
      backupBtn.disabled = true;
      let done = 0;
      await pool(list, 4, async (d) => {
        const blob = await Api.download(d.attachment_path);
        if (blob) zip.file(`${d.book_number || d.document_code}_${d.attachment_path.split('/').pop()}`, blob);
        progress.set(++done, list.length, 'تنزيل الأصول');
      }, () => false);
      const out = await zip.generateAsync({ type: 'blob' });
      downloadBlob(out, `diwan_originals_${stamp()}.zip`);
      progress.hide();
      backupBtn.disabled = false;
      toast('تم تنزيل نسخة الأصول', 'ok');
    }

    async function start() {
      const list = pending();
      const ok = await confirmDialog('تأكيد المعالجة',
        `ستتم معالجة ${list.length} صورة: اقتصاص الحواف وتحسينها ثم استبدال الصورة.` +
        (state.deleteOld ? '\n\nتُحذف الصورة الأصلية من التخزين بعد نجاح المعالجة. يُنصح بتنزيل الأصول أولاً.' : ''),
        { okLabel: 'ابدأ', danger: state.deleteOld });
      if (!ok) return;
      state.running = true;
      state.cancel = false;
      cancelBtn.hidden = false;
      cancelBtn.disabled = false;
      refresh();
      results.innerHTML = '';
      const report = { cropped: 0, enhanced: 0, failed: [] };
      let done = 0;
      progress.set(0, list.length);
      await pool(list, CONCURRENCY, async (d) => {
        try {
          const blob = await Api.download(d.attachment_path);
          if (!blob) throw new Error('تعذّر تحميل الصورة');
          const scan = await window.ScannerPool.scan(blob, { filter: state.filter });
          await Api.setAttachment(d, scan.blob, scan.extension, { scanned: true, deleteOld: state.deleteOld });
          report[scan.autoDetected ? 'cropped' : 'enhanced']++;
        } catch (e) {
          report.failed.push({ d, message: e.message });
        }
        progress.set(++done, list.length, `كتاب ${d.book_number || ''}`);
      }, () => state.cancel);
      state.running = false;
      cancelBtn.hidden = true;
      await Api.documents(true);
      refresh();
      results.append(h('div', { class: 'card' },
        h('h3', {}, 'النتيجة'),
        h('div', { class: 'row' },
          h('span', { class: 'badge ok' }, `اقتصاص وتحسين: ${report.cropped}`),
          h('span', { class: 'badge info' }, `تحسين فقط: ${report.enhanced}`),
          report.failed.length ? h('span', { class: 'badge danger' }, `فشل: ${report.failed.length}`) : null),
        report.failed.map((f) => h('div', { class: 'list-item' }, icon('alert'), h('div', { class: 'grow' }, h('div', { class: 'title' }, `كتاب ${f.d.book_number}`), h('div', { class: 'meta' }, f.message))))));
    }

    const el = h('div', { class: 'stack' },
      h('div', { class: 'card stack', style: 'gap:14px' },
        h('div', {}, 'صور قديمة بانتظار المعالجة: ', count),
        h('div', { class: 'help' }, 'تُقتص حواف الورقة تلقائياً لكل صورة. إذا لم تظهر الحواف بوضوح تبقى الصورة كاملة ويُطبَّق التحسين فقط.'),
        filterSeg(state),
        h('label', { class: 'switch' }, deleteBox, 'حذف الصورة الأصلية من التخزين بعد المعالجة'),
        h('div', { class: 'row' }, backupBtn, startBtn, cancelBtn)),
      progress.el,
      results);
    refresh();
    return el;
  }

  async function render(root, app, params) {
    await window.Api.documents();
    const tabs = h('div', { class: 'tabs', role: 'tablist' });
    const body = h('div', {});
    const views = [['attach', 'إرفاق حسب اسم الملف', attachTab], ['rescan', 'معالجة الصور القديمة', rescanTab]];
    let active = params.get('tab') === 'rescan' ? 'rescan' : 'attach';
    const draw = () => {
      tabs.innerHTML = '';
      for (const [key, label] of views) {
        tabs.append(h('button', { role: 'tab', class: key === active ? 'on' : '', onclick: () => { active = key; draw(); } }, label));
      }
      body.innerHTML = '';
      body.append(views.find((v) => v[0] === active)[2](app));
    };
    root.append(
      h('div', { class: 'page-head' },
        h('div', {}, h('h2', { class: 'title' }, 'الصور'), h('p', { class: 'lead' }, 'إرفاق صور كثيرة مرة واحدة، ومعالجة الصور القديمة'))),
      tabs, body);
    draw();
  }

  window.Views = window.Views || {};
  window.Views.bulk = { title: 'الصور', render };
})();
