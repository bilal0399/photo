/* النسخ الاحتياطي — the same full backup the app builds (Excel + all images in one zip). */
(function () {
  'use strict';
  const { h, icon, toast, downloadBlob, stamp, fmtNum } = window.U;

  async function render(root) {
    const Api = window.Api;
    const [docs, tasks] = await Promise.all([Api.documents(true), Api.tasks(true).catch(() => [])]);
    const withFiles = docs.filter((d) => d.attachment_path).length + tasks.filter((t) => t.attachment_path).length;

    const bar = h('div', { style: 'width:0%' });
    const label = h('div', { class: 'help' });
    const progress = h('div', { class: 'stack', style: 'gap:8px', hidden: true }, h('div', { class: 'progress' }, bar), label);
    const fullBtn = h('button', { class: 'btn primary', onclick: () => full() }, icon('backup'), 'إنشاء نسخة كاملة');
    const excelBtn = h('button', { class: 'btn', onclick: () => excelOnly() }, icon('excel'), 'السجلات فقط (Excel)');

    const records = () => {
      const T = window.DocTools;
      return T.workbook([
        { name: 'الطلبات', rows: T.exportRows(docs) },
        { name: 'المهمات', rows: [['رقم المهمة', 'الجهة'], ...tasks.map((t) => [t.task_number || '', t.entity || ''])] },
      ]);
    };

    function excelOnly() {
      downloadBlob(records(), `diwan_records_${stamp()}.xlsx`);
    }

    async function full() {
      fullBtn.disabled = excelBtn.disabled = true;
      progress.hidden = false;
      const zip = new window.JSZip();
      zip.file('records.xlsx', records());
      const jobs = [
        ...docs.filter((d) => d.attachment_path).map((d) => ({ path: d.attachment_path, bucket: Api.DOC_BUCKET, name: `images/documents/${d.book_number || d.document_code}_${d.attachment_path.split('/').pop()}` })),
        ...tasks.filter((t) => t.attachment_path).map((t) => ({ path: t.attachment_path, bucket: Api.TASK_BUCKET, name: `images/tasks/${t.task_number || t.id}_${t.attachment_path.split('/').pop()}` })),
      ];
      let done = 0;
      let missing = 0;
      let next = 0;
      const worker = async () => {
        while (next < jobs.length) {
          const job = jobs[next++];
          const blob = await Api.download(job.path, job.bucket);
          if (blob) zip.file(job.name, blob);
          else missing++;
          done++;
          bar.style.width = `${(done / jobs.length) * 90}%`;
          label.textContent = `تنزيل الصور ${done} / ${jobs.length}`;
        }
      };
      try {
        await Promise.all(Array.from({ length: 6 }, worker));
        label.textContent = 'ضغط الملف…';
        const out = await zip.generateAsync({ type: 'blob' }, (meta) => {
          bar.style.width = `${90 + meta.percent / 10}%`;
        });
        downloadBlob(out, `diwan_backup_${stamp()}.zip`);
        toast(missing ? `تم إنشاء النسخة (تعذّر تنزيل ${missing} ملف)` : 'تم إنشاء النسخة الكاملة', missing ? 'error' : 'ok');
      } catch (e) {
        toast(`تعذّر إنشاء النسخة: ${e.message}`, 'error');
      } finally {
        fullBtn.disabled = excelBtn.disabled = false;
        progress.hidden = true;
        bar.style.width = '0%';
      }
    }

    root.append(
      h('div', { class: 'page-head' },
        h('div', {}, h('h2', { class: 'title' }, 'النسخ الاحتياطي'), h('p', { class: 'lead' }, 'نسخة كاملة من السحابة بنفس صيغة نسخة التطبيق'))),
      h('div', { class: 'grid halves' },
        h('div', { class: 'card stack', style: 'gap:14px' },
          h('h3', { style: 'margin:0' }, 'محتوى النسخة'),
          h('div', { class: 'list' },
            h('div', { class: 'list-item' }, icon('docs'), h('div', { class: 'grow' }, 'الطلبات'), h('strong', { class: 'num' }, fmtNum(docs.length))),
            h('div', { class: 'list-item' }, icon('folder'), h('div', { class: 'grow' }, 'المهمات'), h('strong', { class: 'num' }, fmtNum(tasks.length))),
            h('div', { class: 'list-item' }, icon('image'), h('div', { class: 'grow' }, 'الملفات المرفقة'), h('strong', { class: 'num' }, fmtNum(withFiles)))),
          h('div', { class: 'row' }, fullBtn, excelBtn),
          progress),
        h('div', { class: 'card stack', style: 'gap:10px' },
          h('h3', { style: 'margin:0' }, 'ملاحظات'),
          h('div', { class: 'help' }, 'الملف المضغوط يحتوي records.xlsx (ورقتا الطلبات والمهمات) ومجلد images بكل الصور، مسماة برقم الكتاب.'),
          h('div', { class: 'help' }, 'النسخة نفسها متاحة للمدير من تطبيق سطح المكتب: الإعدادات ← النسخ الاحتياطي.'),
          h('div', { class: 'help' }, 'احفظ النسخة خارج هذا الجهاز (قرص خارجي أو مكان آمن).'))));
  }

  window.Views = window.Views || {};
  window.Views.backup = { title: 'النسخ الاحتياطي', render };
})();
