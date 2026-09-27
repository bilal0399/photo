/*
 * Matching files to documents by name — same rules as the app's
 * BulkAttachService: "7.jpg" belongs to book 7; Arabic-Indic digits and
 * leading zeros are fine; year/direction narrow repeated numbers.
 */
(function (root) {
  'use strict';

  const EXTENSIONS = ['jpg', 'jpeg', 'png', 'pdf'];
  const STATUS = {
    ready: 'جاهز للإرفاق',
    replaces: 'سيستبدل المرفق الحالي',
    hasAttachment: 'للطلب مرفق مسبقاً',
    notFound: 'لا يوجد طلب بهذا الرقم',
    ambiguous: 'أكثر من طلب بهذا الرقم',
    duplicateFile: 'ملف آخر لنفس الطلب',
    badName: 'اسم الملف ليس رقماً',
    unsupported: 'نوع ملف غير مدعوم',
  };
  const willUpload = (status) => status === 'ready' || status === 'replaces';

  function numberFromName(name) {
    const base = String(name).split(/[\\/]/).pop().replace(/\.[^.]*$/, '').trim()
      .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
      .replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
    if (!/^\d+$/.test(base)) return null;
    return String(parseInt(base, 10));
  }

  /**
   * files: [{ name, ... }]; docs: rows with book_number, doc_date, direction,
   * attachment_path, id. Returns [{ file, status, number, doc, candidates }].
   */
  function plan(files, docs, { year = '', direction = '', replaceExisting = false } = {}) {
    const byNumber = new Map();
    for (const d of docs) {
      if (year && !String(d.doc_date || '').startsWith(year)) continue;
      if (direction && d.direction !== direction) continue;
      const n = parseInt(String(d.book_number || '').trim(), 10);
      if (Number.isNaN(n)) continue;
      const key = String(n);
      if (!byNumber.has(key)) byNumber.set(key, []);
      byNumber.get(key).push(d);
    }
    const claimed = new Set();
    return files.map((file) => {
      const ext = (/\.([^.]+)$/.exec(file.name) || [])[1];
      if (!ext || !EXTENSIONS.includes(ext.toLowerCase())) return { file, status: 'unsupported' };
      const number = numberFromName(file.name);
      if (number === null) return { file, status: 'badName' };
      const matches = byNumber.get(number) || [];
      if (!matches.length) return { file, number, status: 'notFound' };
      if (matches.length > 1) return { file, number, status: 'ambiguous', candidates: matches };
      const doc = matches[0];
      let status;
      if (claimed.has(doc.id)) status = 'duplicateFile';
      else if (doc.attachment_path) status = replaceExisting ? 'replaces' : 'hasAttachment';
      else status = 'ready';
      claimed.add(doc.id);
      return { file, number, doc, status };
    });
  }

  const api = { EXTENSIONS, STATUS, willUpload, numberFromName, plan };
  root.BulkMatch = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof self !== 'undefined' ? self : globalThis);
