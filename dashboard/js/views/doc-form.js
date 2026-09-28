/*
 * The document form, shared by "إدخال سريع" (fast entry) and the edit dialog.
 * Images are scanned (cropped + enhanced) as soon as they are chosen, pasted
 * or dropped, so what is saved is always the processed page.
 */
(function () {
  'use strict';
  const { h, icon, combobox, toast, confirmDialog, pad } = window.U;

  const FILTER_LABELS = { auto: 'تحسين تلقائي', grayscale: 'رمادي', blackWhite: 'أبيض وأسود', original: 'الأصلية' };
  const ACCEPT = '.jpg,.jpeg,.png,.pdf,.doc,.docx,.xls,.xlsx';

  /**
   * DocForm({ doc, mode: 'quick' | 'edit', memory, onSaved(row) })
   * memory: object kept between quick entries (date, direction, type, party).
   * Returns { el, save, focus, destroy }.
   */
  function DocForm({ doc = null, mode = 'quick', memory = {}, onSaved }) {
    const Api = window.Api;
    const isEdit = !!doc;
    const now = new Date();
    const date = (doc && doc.doc_date) || memory.date || `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    let [year, month, day] = date.split('-');
    let direction = (doc && doc.direction) || memory.direction || Api.OUTGOING;
    let saving = false;

    // Image state: the original file and its processed version.
    const image = { file: null, result: null, filter: 'auto', crop: true, turns: 0, busy: false, token: 0 };

    // ---------------------------------------------------------------- fields
    const number = h('input', { class: 'input num', id: 'f-number', inputmode: 'numeric', value: (doc && doc.book_number) || Api.nextBookNumber() });
    const yearSel = h('select', { class: 'select', id: 'f-year' });
    const years = new Set([String(now.getFullYear() - 1), String(now.getFullYear()), String(now.getFullYear() + 1), year]);
    [...years].sort().forEach((y) => yearSel.append(h('option', { value: y, selected: y === year }, y)));
    const monthSel = h('select', { class: 'select', id: 'f-month' });
    for (let m = 1; m <= 12; m++) monthSel.append(h('option', { value: pad(m), selected: pad(m) === month }, String(m)));
    const dayInput = h('input', { class: 'input num', id: 'f-day', inputmode: 'numeric', value: String(parseInt(day, 10)) });

    const addToList = (category) => async (value) => {
      const ok = await confirmDialog('إضافة إلى القائمة', `إضافة «${value}» إلى القائمة لاستخدامها في كل الطلبات؟`, { okLabel: 'إضافة' });
      if (!ok) return null;
      try {
        const added = await Api.addOption(category, value);
        toast('أُضيفت القيمة إلى القائمة', 'ok');
        return added;
      } catch (e) {
        toast(`تعذّرت الإضافة: ${e.message}`, 'error');
        return null;
      }
    };

    const partyCategory = () => (direction === Api.OUTGOING ? 'recipient' : 'requester');
    const typeBox = combobox({
      id: 'f-type',
      value: (doc && doc.book_type) || memory.bookType || '',
      options: Api.optionValues('book_type'),
      onCreate: addToList('book_type'),
    });
    const partyBox = combobox({
      id: 'f-party',
      value: (doc && doc.requester) || (memory.direction === direction ? memory.party : '') || '',
      options: Api.optionValues(partyCategory()),
      onCreate: (v) => addToList(partyCategory())(v),
    });
    const statusBox = combobox({
      id: 'f-status',
      value: (doc && doc.status) || Api.DEFAULT_STATUS,
      options: Api.optionValues('status'),
      onCreate: addToList('status'),
    });
    const summary = h('textarea', { class: 'input', id: 'f-summary', rows: 4, placeholder: 'موضوع الكتاب باختصار' }, (doc && doc.summary) || '');
    const partyLabel = h('label', { for: 'f-party' });
    const errors = h('div', { class: 'error', role: 'alert' });

    const seg = h('div', { class: 'seg', role: 'group', 'aria-label': 'نوع الحركة' });
    const renderSeg = () => {
      seg.innerHTML = '';
      for (const d of [Api.OUTGOING, Api.INCOMING]) {
        seg.append(h('button', {
          type: 'button',
          class: d === direction ? 'on' : '',
          onclick: () => {
            if (d === direction) return;
            direction = d;
            partyBox.setOptions(Api.optionValues(partyCategory()));
            if (partyBox.typed && !partyBox.value) partyBox.value = '';
            if (partyBox.value && !Api.optionValues(partyCategory()).includes(partyBox.value)) partyBox.value = '';
            renderSeg();
          },
        }, d));
      }
      partyLabel.textContent = direction === Api.OUTGOING ? 'الجهة المستقبلة' : 'الجهة المقدمة';
    };
    renderSeg();

    const field = (label, control, cls, help) => h('div', { class: `field ${cls}` },
      typeof label === 'string' ? h('label', { for: control.id || (control.querySelector && control.querySelector('input') ? control.querySelector('input').id : '') }, label) : label,
      control,
      help ? h('div', { class: 'help' }, help) : null);

    const formCard = h('div', { class: 'card' },
      h('div', { class: 'form-grid' },
        h('div', { class: 'field span-12' }, h('div', { class: 'label' }, 'نوع الحركة'), seg),
        field('رقم الكتاب', number, 'span-4'),
        field('السنة', yearSel, 'span-3'),
        field('الشهر', monthSel, 'span-3'),
        field('اليوم', dayInput, 'span-2'),
        field('نوع الكتاب', typeBox.el, 'span-6'),
        field(partyLabel, partyBox.el, 'span-6'),
        field('حالة الكتاب', statusBox.el, 'span-6'),
        h('div', { class: 'span-6' }),
        field('ملخص الكتاب', summary, 'span-12'),
        h('div', { class: 'span-12' }, errors)));

    // ----------------------------------------------------------------- image
    const fileInput = h('input', { type: 'file', accept: ACCEPT, hidden: true });
    const previewImg = h('img', { alt: 'معاينة المرفق', hidden: true });
    const placeholder = h('div', { class: 'placeholder' },
      icon('scan'),
      h('div', { style: 'font-weight:700;margin-top:8px' }, 'اسحب صورة الكتاب هنا، أو الصقها (Ctrl+V)، أو اضغط للاختيار'),
      h('div', { class: 'help' }, 'تُقتص الورقة وتُحسَّن تلقائياً قبل الحفظ'));
    const busy = h('div', { class: 'busy', hidden: true }, h('div', { class: 'spinner' }));
    const fileBadge = h('div', { class: 'placeholder', hidden: true });
    const preview = h('div', { class: 'preview dropzone', tabindex: 0, role: 'button', 'aria-label': 'اختيار مرفق' },
      placeholder, previewImg, fileBadge, busy);
    const status = h('div', { class: 'help', style: 'min-height:20px' });

    const filterSeg = h('div', { class: 'seg' });
    const renderFilters = () => {
      filterSeg.innerHTML = '';
      for (const [key, label] of Object.entries(FILTER_LABELS)) {
        filterSeg.append(h('button', {
          type: 'button',
          class: key === image.filter ? 'on' : '',
          onclick: () => { image.filter = key; renderFilters(); process(); },
        }, label));
      }
    };
    renderFilters();
    const cropToggle = h('input', { type: 'checkbox', checked: true, onchange: () => { image.crop = cropToggle.checked; process(); } });
    const tools = h('div', { class: 'stack', style: 'gap:10px', hidden: true },
      filterSeg,
      h('div', { class: 'row' },
        h('label', { class: 'switch' }, cropToggle, 'اقتصاص الورقة'),
        h('span', { style: 'flex:1' }),
        h('button', { class: 'btn sm', type: 'button', onclick: () => { image.turns = (image.turns + 3) % 4; process(); } }, icon('rotate'), 'تدوير'),
        h('button', { class: 'btn sm danger', type: 'button', onclick: () => clearImage() }, icon('trash'), 'إزالة')));

    const existing = isEdit && doc.attachment_path
      ? h('div', { class: 'help' }, 'المرفق الحالي محفوظ. اختر ملفاً جديداً لاستبداله.')
      : null;

    const imageCard = h('div', { class: 'card stack', style: 'gap:12px' },
      h('h3', { style: 'margin:0' }, 'المرفق'), existing, preview, status, tools, fileInput);

    preview.addEventListener('click', () => fileInput.click());
    preview.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileInput.click(); } });
    fileInput.addEventListener('change', () => { if (fileInput.files[0]) setFile(fileInput.files[0]); fileInput.value = ''; });
    preview.addEventListener('dragover', (e) => { e.preventDefault(); preview.classList.add('over'); });
    preview.addEventListener('dragleave', () => preview.classList.remove('over'));
    preview.addEventListener('drop', (e) => {
      e.preventDefault();
      preview.classList.remove('over');
      const file = e.dataTransfer.files[0];
      if (file) setFile(file);
    });

    const onPaste = (e) => {
      const item = [...(e.clipboardData ? e.clipboardData.items : [])].find((i) => i.type.startsWith('image/'));
      if (!item) return;
      e.preventDefault();
      const blob = item.getAsFile();
      setFile(new File([blob], `paste${blob.type === 'image/png' ? '.png' : '.jpg'}`, { type: blob.type }));
    };
    document.addEventListener('paste', onPaste);

    function setFile(file) {
      image.file = file;
      image.result = null;
      image.turns = 0;
      if (Api.isImagePath(file.name) || /^image\/(jpeg|png)$/.test(file.type)) {
        process();
      } else {
        showFile(file);
      }
    }

    function showFile(file) {
      previewImg.hidden = true;
      placeholder.hidden = true;
      tools.hidden = true;
      fileBadge.hidden = false;
      fileBadge.innerHTML = '';
      fileBadge.append(icon('docs'), h('div', { style: 'font-weight:700;margin-top:8px' }, file.name), h('div', { class: 'help' }, 'يُرفق كما هو'));
      status.textContent = '';
    }

    async function process() {
      if (!image.file) return;
      const token = ++image.token;
      busy.hidden = false;
      image.busy = true;
      try {
        const result = await window.ScannerPool.scan(image.file, {
          filter: image.filter,
          crop: image.crop,
          quarterTurns: image.turns,
        });
        if (token !== image.token) return;
        image.result = result;
        if (previewImg.src) URL.revokeObjectURL(previewImg.src);
        previewImg.src = URL.createObjectURL(result.blob);
        previewImg.hidden = false;
        placeholder.hidden = true;
        fileBadge.hidden = true;
        tools.hidden = false;
        status.textContent = image.crop
          ? (result.autoDetected ? '✓ تم اقتصاص الورقة وتحسينها تلقائياً' : 'لم تُكشف حواف الورقة بوضوح — طُبّق التحسين على الصورة كاملة')
          : 'الصورة كاملة بدون اقتصاص';
      } catch (e) {
        if (token !== image.token) return;
        status.textContent = `تعذّرت معالجة الصورة: ${e.message}`;
      } finally {
        if (token === image.token) {
          busy.hidden = true;
          image.busy = false;
        }
      }
    }

    function clearImage() {
      image.token++;
      image.file = null;
      image.result = null;
      image.busy = false;
      busy.hidden = true;
      if (previewImg.src) URL.revokeObjectURL(previewImg.src);
      previewImg.removeAttribute('src');
      previewImg.hidden = true;
      fileBadge.hidden = true;
      placeholder.hidden = false;
      tools.hidden = true;
      status.textContent = '';
    }

    function attachment() {
      if (!image.file) return null;
      if (image.result) return { blob: image.result.blob, ext: image.result.extension, scanned: true };
      return { blob: image.file, ext: Api.extOf(image.file.name) || '.bin', scanned: false };
    }

    // ------------------------------------------------------------------ save
    function composedDate() {
      return `${yearSel.value}-${monthSel.value}-${pad(parseInt(dayInput.value, 10) || 1)}`;
    }

    function validate() {
      const problems = [];
      const dayN = parseInt(dayInput.value, 10);
      const days = new Date(parseInt(yearSel.value, 10), parseInt(monthSel.value, 10), 0).getDate();
      dayInput.classList.toggle('invalid', !(dayN >= 1 && dayN <= days));
      if (!(dayN >= 1 && dayN <= days)) problems.push(`اليوم من 1 إلى ${days}`);
      if (number.value.trim() && !/^\d+$/.test(number.value.trim())) problems.push('رقم الكتاب أرقام فقط');
      typeBox.invalid(!typeBox.value);
      if (!typeBox.value) problems.push('اختر نوع الكتاب من القائمة');
      partyBox.invalid(!partyBox.value);
      if (!partyBox.value) problems.push(`اختر ${partyLabel.textContent} من القائمة`);
      statusBox.invalid(!statusBox.value);
      if (!statusBox.value) problems.push('اختر حالة الكتاب');
      summary.classList.toggle('invalid', !summary.value.trim());
      if (!summary.value.trim()) problems.push('الملخص مطلوب');
      if (image.busy) problems.push('انتظر حتى تنتهي معالجة الصورة');
      errors.textContent = problems.join(' · ');
      return problems.length === 0;
    }

    async function confirmDuplicate(draft) {
      if (!draft.book_number) return true;
      const clash = (Api.state.documents || []).find((d) =>
        d.id !== (doc && doc.id) &&
        d.book_number === draft.book_number &&
        d.direction === draft.direction &&
        String(d.doc_date || '').startsWith(draft.doc_date.slice(0, 4)));
      if (!clash) return true;
      return confirmDialog('رقم مكرر',
        `يوجد كتاب ${draft.direction} برقم ${draft.book_number} في سنة ${draft.doc_date.slice(0, 4)}:\n«${clash.summary || ''}»\n\nهل تريد الحفظ على أي حال؟`,
        { okLabel: 'حفظ' });
    }

    async function save() {
      if (saving || !validate()) return null;
      const draft = {
        book_number: number.value.trim(),
        doc_date: composedDate(),
        book_type: typeBox.value,
        requester: partyBox.value,
        status: statusBox.value,
        direction,
        summary: summary.value.trim(),
      };
      if (!(await confirmDuplicate(draft))) return null;
      saving = true;
      try {
        const row = isEdit
          ? await Api.updateDocument(doc, draft, attachment())
          : await Api.createDocument(draft, attachment());
        Object.assign(memory, { date: draft.doc_date, direction, bookType: draft.book_type, party: draft.requester });
        if (onSaved) onSaved(row);
        if (!isEdit && mode === 'quick') reset();
        return row;
      } catch (e) {
        toast(`تعذّر الحفظ: ${e.message}`, 'error');
        return null;
      } finally {
        saving = false;
      }
    }

    /** Ready for the next document: keep date, direction, type and party. */
    function reset() {
      summary.value = '';
      number.value = Api.nextBookNumber();
      statusBox.value = Api.DEFAULT_STATUS;
      clearImage();
      errors.textContent = '';
      summary.focus();
    }

    const el = h('div', { class: mode === 'quick' ? 'grid halves' : 'stack' }, formCard, imageCard);

    return {
      el,
      save,
      focus: () => (isEdit ? summary : (typeBox.value ? summary : typeBox.input)).focus(),
      destroy: () => document.removeEventListener('paste', onPaste),
    };
  }

  window.DocForm = DocForm;
})();
