// Run with:  node --test dashboard/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const S = require('../js/scanner-core.js');

/** A dark desk with a tilted light sheet and a few dark text bars on it. */
function fakePhoto(w, h, sheet) {
  const rgb = new Uint8Array(w * h * 3);
  const inside = (x, y) => {
    let hit = false;
    for (let i = 0, j = sheet.length - 1; i < sheet.length; j = i++) {
      const [xi, yi] = sheet[i];
      const [xj, yj] = sheet[j];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
    }
    return hit;
  };
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const text = x > 220 && x < 640 && (y - 220) % 60 >= 0 && (y - 220) % 60 < 12 && y < 940;
      const v = inside(x, y) ? (text ? 30 : 236) : 47;
      const i = (y * w + x) * 3;
      rgb[i] = v;
      rgb[i + 1] = v;
      rgb[i + 2] = v;
    }
  }
  return rgb;
}

const sheet = [[150, 160], [760, 110], [800, 1080], [120, 1030]];
const photo = fakePhoto(900, 1200, sheet);

test('detects the corners of a tilted sheet', () => {
  const quad = S.detectQuad(photo, 900, 1200);
  assert.ok(quad, 'sheet found');
  for (let i = 0; i < 4; i++) {
    assert.ok(Math.abs(quad[i * 2] * 900 - sheet[i][0]) < 25, `x of corner ${i}`);
    assert.ok(Math.abs(quad[i * 2 + 1] * 1200 - sheet[i][1]) < 25, `y of corner ${i}`);
  }
});

test('falls back when nothing stands out', () => {
  const flat = new Uint8Array(600 * 800 * 3).fill(210);
  assert.strictEqual(S.detectQuad(flat, 600, 800), null);
});

test('auto filter crops to the sheet and whitens the paper', () => {
  const quad = S.detectQuad(photo, 900, 1200);
  const out = S.render(photo, 900, 1200, quad, 'auto', 0);
  assert.strictEqual(out.channels, 3);
  assert.ok(out.width < 900 && out.height > out.width);
  // Top-left corner of the scan is paper, now pure white.
  assert.ok(out.pixels[(6 * out.width + 6) * 3] > 240);
});

test('black and white keeps only two values and rotation swaps sides', () => {
  const quad = S.detectQuad(photo, 900, 1200);
  const out = S.render(photo, 900, 1200, quad, 'blackWhite', 1);
  assert.strictEqual(out.channels, 1);
  assert.ok(out.width > out.height);
  assert.deepStrictEqual(new Set(out.pixels), new Set([0, 255]));
});

test('shading across the page is flattened', () => {
  // Paper that darkens from 230 on the left to 130 on the right.
  const w = 400, h = 300;
  const lum = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) lum[y * w + x] = Math.round(230 - (100 * x) / w);
  const px = Uint8Array.from(lum);
  assert.ok(S.flattenLighting(px, lum, w, h, 1));
  const left = px[150 * w + 20];
  const right = px[150 * w + w - 20];
  assert.ok(Math.abs(left - right) < 12, `left ${left} right ${right}`);
});

test('matches the Dart implementation on the shared fixture sizes', () => {
  // Same rounding rules as the app: working side and full frame constants.
  assert.strictEqual(S.WORKING_SIDE, 2400);
  assert.deepStrictEqual(S.FULL_FRAME, [0, 0, 1, 0, 1, 1, 0, 1]);
});
