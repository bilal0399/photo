const test = require('node:test');
const assert = require('node:assert');
const M = require('../js/bulk-match.js');

const doc = (id, number, extra = {}) => ({
  id, book_number: number, doc_date: '2025-03-01', direction: 'صادر', attachment_path: '', ...extra,
});

test('reads plain, zero padded and Arabic-Indic numbers', () => {
  assert.strictEqual(M.numberFromName('7.jpg'), '7');
  assert.strictEqual(M.numberFromName('folder/007.PNG'), '7');
  assert.strictEqual(M.numberFromName('٤٢.jpg'), '42');
  assert.strictEqual(M.numberFromName('scan 7.jpg'), null);
  assert.strictEqual(M.numberFromName('IMG_2031.jpg'), null);
});

test('matches files and explains every other case', () => {
  const docs = [
    doc('a', '7'),
    doc('b', '8', { attachment_path: 'documents/x.jpg' }),
    doc('c', '9', { doc_date: '2024-01-01' }),
    doc('d', '9'),
  ];
  const items = M.plan(
    ['7.jpg', '8.jpg', '9.jpg', '11.jpg', 'photo.jpg', '7.docx', '٧.png'].map((name) => ({ name })),
    docs,
  );
  assert.deepStrictEqual(items.map((i) => i.status),
    ['ready', 'hasAttachment', 'ambiguous', 'notFound', 'badName', 'unsupported', 'duplicateFile']);
  assert.strictEqual(items[0].doc.id, 'a');
  assert.deepStrictEqual(items[2].candidates.map((d) => d.id), ['c', 'd']);
});

test('year, direction and replace settle the rest', () => {
  const docs = [
    doc('c', '9', { doc_date: '2024-01-01' }),
    doc('d', '9'),
    doc('e', '10', { direction: 'وارد' }),
    doc('f', '10'),
    doc('g', '12', { attachment_path: 'x.jpg' }),
  ];
  assert.strictEqual(M.plan([{ name: '9.jpg' }], docs, { year: '2024' })[0].doc.id, 'c');
  assert.strictEqual(M.plan([{ name: '10.jpg' }], docs, { direction: 'وارد' })[0].doc.id, 'e');
  const replace = M.plan([{ name: '12.jpg' }], docs, { replaceExisting: true })[0];
  assert.strictEqual(replace.status, 'replaces');
  assert.ok(M.willUpload(replace.status));
});

test('a prefixed series keeps its own numbers', () => {
  assert.strictEqual(M.numberKey('M-13'), 'M-13');
  assert.strictEqual(M.numberKey('m-007'), 'M-7');
  assert.strictEqual(M.numberKey('13'), '13');
  assert.strictEqual(M.numberKey('M13'), null);
  assert.strictEqual(M.numberFromName('M-13.jpg'), 'M-13');

  // 'M-13' and '13' are different books and must not match each other.
  const docs = [doc('ministry', 'M-13'), doc('plain', '13')];
  const items = M.plan([{ name: 'M-13.jpg' }, { name: '13.jpg' }], docs);
  assert.deepStrictEqual(items.map((i) => i.status), ['ready', 'ready']);
  assert.strictEqual(items[0].doc.id, 'ministry');
  assert.strictEqual(items[1].doc.id, 'plain');
});
