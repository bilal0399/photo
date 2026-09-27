/*
 * Document scanner — the same pipeline as lib/core/scanner/document_scanner.dart
 * so images added from the dashboard look exactly like the app's:
 * find the sheet, straighten it, flatten the lighting, boost contrast, sharpen.
 *
 * Pure functions on RGB buffers (Uint8Array, 3 bytes per pixel), usable from a
 * Web Worker, the page itself, or Node (for tests). The browser-only parts
 * (decoding and encoding) are in `scanBlob` at the bottom.
 */
(function (root) {
  'use strict';

  const WORKING_SIDE = 2400;
  const MAX_OUTPUT_SIDE = 2400;
  const DETECT_SIDE = 420;
  const JPEG_QUALITY = 0.9;
  const FULL_FRAME = [0, 0, 1, 0, 1, 1, 0, 1];
  const FILTERS = ['original', 'auto', 'grayscale', 'blackWhite'];

  const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

  /** Area-average downscale of an interleaved buffer to tw x th. */
  function shrink(src, w, h, channels, tw, th) {
    const out = new Uint8Array(tw * th * channels);
    const xs = new Int32Array(tw + 1);
    for (let tx = 0; tx <= tw; tx++) xs[tx] = Math.floor((tx * w) / tw);
    const sums = new Int32Array(tw * channels);
    for (let ty = 0; ty < th; ty++) {
      const y0 = Math.floor((ty * h) / th);
      const y1 = Math.max(y0 + 1, Math.floor(((ty + 1) * h) / th));
      sums.fill(0);
      for (let y = y0; y < y1; y++) {
        const row = y * w * channels;
        for (let tx = 0; tx < tw; tx++) {
          const x1 = Math.max(xs[tx] + 1, xs[tx + 1]);
          const s = tx * channels;
          for (let x = xs[tx]; x < x1; x++) {
            const i = row + x * channels;
            for (let c = 0; c < channels; c++) sums[s + c] += src[i + c];
          }
        }
      }
      const rows = y1 - y0;
      const base = ty * tw * channels;
      for (let tx = 0; tx < tw; tx++) {
        const count = rows * (Math.max(xs[tx] + 1, xs[tx + 1]) - xs[tx]);
        const s = tx * channels;
        for (let c = 0; c < channels; c++) {
          out[base + s + c] = Math.floor((sums[s + c] + (count >> 1)) / count);
        }
      }
    }
    return out;
  }

  /** Rec. 601 luma of an RGB buffer. */
  function luma(rgb, count) {
    const out = new Uint8Array(count);
    for (let i = 0, j = 0; i < count; i++, j += 3) {
      out[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
    }
    return out;
  }

  // ---------------------------------------------------------- edge detection

  /**
   * Finds the sheet by separating it from the background, then takes the four
   * extreme points of the largest region. Returns null when the result does
   * not look like a document (the caller keeps the full frame).
   */
  function detectQuad(rgb, width, height) {
    const scale = DETECT_SIDE / Math.max(width, height);
    let w = width;
    let h = height;
    let px = rgb;
    if (scale < 1) {
      const tw = Math.max(16, Math.round(w * scale));
      const th = Math.max(16, Math.round(h * scale));
      px = shrink(px, w, h, 3, tw, th);
      w = tw;
      h = th;
    }
    const lum = luma(px, w * h);

    const band = Math.max(2, Math.round(Math.min(w, h) * 0.04));
    const border = [];
    const centre = [];
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const v = lum[y * w + x];
        if (x < band || y < band || x >= w - band || y >= h - band) border.push(v);
        else if (x > w * 0.3 && x < w * 0.7 && y > h * 0.3 && y < h * 0.7) centre.push(v);
      }
    }
    if (!border.length || !centre.length) return null;
    border.sort((a, b) => a - b);
    centre.sort((a, b) => a - b);
    const background = border[border.length >> 1];
    const foreground = centre[centre.length >> 1];
    const contrast = Math.abs(foreground - background);
    if (contrast < 20) return null;

    const brighter = foreground > background;
    const threshold = Math.max(18, Math.round(contrast * 0.35));
    const mask = new Uint8Array(w * h);
    for (let k = 0; k < mask.length; k++) {
      const v = lum[k];
      mask[k] = (brighter ? v > background + threshold : v < background - threshold) ? 1 : 0;
    }

    const region = largestRegion(mask, w, h);
    if (!region) return null;

    let minSum = Infinity, maxSum = -Infinity, minDiff = Infinity, maxDiff = -Infinity;
    let tl = [0, 0], tr = [0, 0], br = [0, 0], bl = [0, 0];
    for (let n = 0; n < region.length; n++) {
      const index = region[n];
      const x = index % w;
      const y = (index - x) / w;
      const sum = x + y;
      const diff = x - y;
      if (sum < minSum) { minSum = sum; tl = [x, y]; }
      if (sum > maxSum) { maxSum = sum; br = [x, y]; }
      if (diff > maxDiff) { maxDiff = diff; tr = [x, y]; }
      if (diff < minDiff) { minDiff = diff; bl = [x, y]; }
    }
    const corners = [tl[0] / w, tl[1] / h, tr[0] / w, tr[1] / h, br[0] / w, br[1] / h, bl[0] / w, bl[1] / h];
    return isPlausible(corners) ? inset(corners) : null;
  }

  /** Flood fills the mask and returns the pixel indices of the biggest region. */
  function largestRegion(mask, w, h) {
    const visited = new Uint8Array(mask.length);
    const queue = new Int32Array(mask.length);
    const minArea = Math.round(mask.length * 0.12);
    let best = null;
    for (let start = 0; start < mask.length; start++) {
      if (mask[start] === 0 || visited[start] === 1) continue;
      let head = 0;
      let tail = 0;
      queue[tail++] = start;
      visited[start] = 1;
      while (head < tail) {
        const index = queue[head++];
        const x = index % w;
        const y = (index - x) / w;
        const push = (n) => {
          if (mask[n] === 1 && visited[n] === 0) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        };
        if (x > 0) push(index - 1);
        if (x < w - 1) push(index + 1);
        if (y > 0) push(index - w);
        if (y < h - 1) push(index + w);
      }
      if (tail >= minArea && (!best || tail > best.length)) best = queue.slice(0, tail);
    }
    return best;
  }

  /** Rejects detections that are too small, too thin or nearly degenerate. */
  function isPlausible(q) {
    let area = 0;
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      area += q[i * 2] * q[j * 2 + 1] - q[j * 2] * q[i * 2 + 1];
    }
    if (Math.abs(area) / 2 < 0.15) return false;
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      const dx = q[j * 2] - q[i * 2];
      const dy = q[j * 2 + 1] - q[i * 2 + 1];
      if (Math.sqrt(dx * dx + dy * dy) < 0.12) return false;
    }
    return true;
  }

  /** Pulls the corners slightly inwards so no background line leaks in. */
  function inset(q) {
    const keep = 0.99;
    const cx = (q[0] + q[2] + q[4] + q[6]) / 4;
    const cy = (q[1] + q[3] + q[5] + q[7]) / 4;
    return q.map((v, i) => (i % 2 === 0 ? cx + (v - cx) * keep : cy + (v - cy) * keep));
  }

  // --------------------------------------------------------------- rendering

  /**
   * Straightens the quad (normalised corners) into a rectangle and applies the
   * filter. Returns { pixels, width, height, channels }.
   */
  function render(rgb, w, h, quad, filter, quarterTurns) {
    const c = quad.map((v, i) => v * (i % 2 === 0 ? w : h));
    const dist = (a, b) => Math.hypot(c[a * 2] - c[b * 2], c[a * 2 + 1] - c[b * 2 + 1]);
    let ow = clamp(Math.round(Math.max(dist(0, 1), dist(3, 2))), 32, 6000);
    let oh = clamp(Math.round(Math.max(dist(0, 3), dist(1, 2))), 32, 6000);
    const longest = Math.max(ow, oh);
    if (longest > MAX_OUTPUT_SIDE) {
      const f = MAX_OUTPUT_SIDE / longest;
      ow = Math.max(32, Math.round(ow * f));
      oh = Math.max(32, Math.round(oh * f));
    }

    let pixels = warp(rgb, w, h, c, ow, oh);
    let channels = 3;
    switch (filter) {
      case 'auto':
        enhanceDocument(pixels, ow, oh, 3);
        break;
      case 'grayscale':
        pixels = luma(pixels, ow * oh);
        channels = 1;
        enhanceDocument(pixels, ow, oh, 1);
        break;
      case 'blackWhite': {
        const lum = luma(pixels, ow * oh);
        flattenLighting(lum, lum, ow, oh, 1);
        pixels = adaptiveThreshold(lum, ow, oh);
        channels = 1;
        break;
      }
      default:
        break;
    }

    const turns = ((quarterTurns || 0) % 4 + 4) % 4;
    if (turns) {
      pixels = rotate(pixels, ow, oh, channels, turns);
      if (turns % 2) [ow, oh] = [oh, ow];
    }
    return { pixels, width: ow, height: oh, channels };
  }

  /** Perspective-correct warp with bilinear sampling (Heckbert's projective map). */
  function warp(src, w, h, c, ow, oh) {
    const [x0, y0, x1, y1, x2, y2, x3, y3] = c;
    const sx = x0 - x1 + x2 - x3;
    const sy = y0 - y1 + y2 - y3;
    let a, b, d, e, g, hh;
    if (Math.abs(sx) < 1e-9 && Math.abs(sy) < 1e-9) {
      a = x1 - x0; b = x3 - x0; d = y1 - y0; e = y3 - y0; g = 0; hh = 0;
    } else {
      const dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
      const den = dx1 * dy2 - dx2 * dy1;
      g = den === 0 ? 0 : (sx * dy2 - dx2 * sy) / den;
      hh = den === 0 ? 0 : (dx1 * sy - sx * dy1) / den;
      a = x1 - x0 + g * x1;
      b = x3 - x0 + hh * x3;
      d = y1 - y0 + g * y1;
      e = y3 - y0 + hh * y3;
    }
    const out = new Uint8Array(ow * oh * 3);
    const maxX = w - 1;
    const maxY = h - 1;
    const stride = w * 3;
    let o = 0;
    for (let j = 0; j < oh; j++) {
      const v = (j + 0.5) / oh;
      for (let i = 0; i < ow; i++) {
        const u = (i + 0.5) / ow;
        const z = g * u + hh * v + 1;
        const fx = clamp((a * u + b * v + x0) / z - 0.5, 0, maxX);
        const fy = clamp((d * u + e * v + y0) / z - 0.5, 0, maxY);
        const ix = fx | 0;
        const iy = fy | 0;
        const tx = fx - ix;
        const ty = fy - iy;
        const p00 = iy * stride + ix * 3;
        const p10 = p00 + (ix < maxX ? 3 : 0);
        const p01 = p00 + (iy < maxY ? stride : 0);
        const p11 = p01 + (ix < maxX ? 3 : 0);
        const w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
        for (let k = 0; k < 3; k++) {
          out[o++] = (src[p00 + k] * w00 + src[p10 + k] * w10 + src[p01 + k] * w01 + src[p11 + k] * w11 + 0.5) | 0;
        }
      }
    }
    return out;
  }

  function percentile(histogram, total, fraction) {
    const target = Math.round(total * fraction);
    let seen = 0;
    for (let v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen >= target) return v;
    }
    return 255;
  }

  /** Evens out the lighting, whitens the paper, darkens the ink and sharpens. */
  function enhanceDocument(pixels, w, h, channels) {
    const lum = channels === 3 ? luma(pixels, w * h) : Uint8Array.from(pixels);
    if (!flattenLighting(pixels, lum, w, h, channels)) return;

    const normalised = channels === 3 ? luma(pixels, w * h) : pixels;
    const histogram = new Int32Array(256);
    for (let i = 0; i < normalised.length; i++) histogram[normalised[i]]++;
    const black = Math.min(percentile(histogram, normalised.length, 0.005), 110);
    const white = 232;
    const lut = new Uint8Array(256);
    for (let v = 0; v < 256; v++) {
      const t = clamp((v - black) / (white - black), 0, 1);
      const curved = t * t * (3 - 2 * t);
      lut[v] = clamp(Math.round(Math.pow(t * 0.5 + curved * 0.5, 1.35) * 255), 0, 255);
    }
    for (let i = 0; i < pixels.length; i++) pixels[i] = lut[pixels[i]];

    sharpen(pixels, w, h, channels, 0.8);
  }

  /** Divides out the paper's own shading. Returns false when there is no paper. */
  function flattenLighting(pixels, lum, w, h, channels) {
    const factor = Math.max(1, Math.round(Math.max(w, h) / 160));
    const sw = Math.max(1, Math.floor(w / factor));
    const sh = Math.max(1, Math.floor(h / factor));
    let grid = shrink(lum, w, h, 1, sw, sh);
    for (let i = 0; i < 3; i++) grid = maxFilter(grid, sw, sh);
    grid = boxBlur(grid, sw, sh, 2);

    const histogram = new Int32Array(256);
    for (let i = 0; i < grid.length; i++) histogram[grid[i]]++;
    const paper = percentile(histogram, grid.length, 0.9);
    if (paper < 64) return false;
    const floor = paper * 0.6;

    const gains = new Float64Array(sw * sh);
    for (let i = 0; i < gains.length; i++) gains[i] = 255 / Math.max(grid[i], floor);

    const xs = new Float64Array(w);
    for (let x = 0; x < w; x++) xs[x] = clamp((x + 0.5) / factor - 0.5, 0, sw - 1);
    let o = 0;
    for (let y = 0; y < h; y++) {
      const gy = clamp((y + 0.5) / factor - 0.5, 0, sh - 1);
      const y0 = gy | 0;
      const y1 = Math.min(y0 + 1, sh - 1);
      const ty = gy - y0;
      for (let x = 0; x < w; x++) {
        const gx = xs[x];
        const x0 = gx | 0;
        const x1 = Math.min(x0 + 1, sw - 1);
        const tx = gx - x0;
        const top = gains[y0 * sw + x0] * (1 - tx) + gains[y0 * sw + x1] * tx;
        const bottom = gains[y1 * sw + x0] * (1 - tx) + gains[y1 * sw + x1] * tx;
        const gain = top * (1 - ty) + bottom * ty;
        for (let c = 0; c < channels; c++) {
          const v = pixels[o] * gain;
          pixels[o++] = v >= 255 ? 255 : v | 0;
        }
      }
    }
    return true;
  }

  function maxFilter(src, w, h) {
    const out = new Uint8Array(src.length);
    for (let y = 0; y < h; y++) {
      const ya = Math.max(0, y - 1), yb = Math.min(h - 1, y + 1);
      for (let x = 0; x < w; x++) {
        const xa = Math.max(0, x - 1), xb = Math.min(w - 1, x + 1);
        let m = 0;
        for (let yy = ya; yy <= yb; yy++) {
          for (let xx = xa; xx <= xb; xx++) {
            const v = src[yy * w + xx];
            if (v > m) m = v;
          }
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  function boxBlur(src, w, h, radius) {
    const tmp = new Uint8Array(src.length);
    const out = new Uint8Array(src.length);
    const span = 2 * radius + 1;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let sum = 0;
        for (let k = -radius; k <= radius; k++) sum += src[y * w + clamp(x + k, 0, w - 1)];
        tmp[y * w + x] = Math.floor(sum / span);
      }
    }
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let sum = 0;
        for (let k = -radius; k <= radius; k++) sum += tmp[clamp(y + k, 0, h - 1) * w + x];
        out[y * w + x] = Math.floor(sum / span);
      }
    }
    return out;
  }

  /** Unsharp mask with a 3x3 box blur. */
  function sharpen(pixels, w, h, channels, amount) {
    const src = Uint8Array.from(pixels);
    const stride = w * channels;
    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const base = y * stride + x * channels;
        for (let c = 0; c < channels; c++) {
          const i = base + c;
          const sum = src[i - stride - channels] + src[i - stride] + src[i - stride + channels] +
            src[i - channels] + src[i] + src[i + channels] +
            src[i + stride - channels] + src[i + stride] + src[i + stride + channels];
          const v = src[i] + amount * (src[i] - sum / 9);
          pixels[i] = v <= 0 ? 0 : v >= 255 ? 255 : Math.round(v);
        }
      }
    }
  }

  /** Bradley adaptive threshold: crisp text under uneven lighting. */
  function adaptiveThreshold(lum, w, h) {
    const W = w + 1;
    const integral = new Float64Array(W * (h + 1));
    for (let y = 0; y < h; y++) {
      let rowSum = 0;
      for (let x = 0; x < w; x++) {
        rowSum += lum[y * w + x];
        integral[(y + 1) * W + x + 1] = integral[y * W + x + 1] + rowSum;
      }
    }
    const radius = Math.max(6, Math.round(Math.min(w, h) / 28));
    const out = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      const ya = Math.max(0, y - radius), yb = Math.min(h - 1, y + radius);
      for (let x = 0; x < w; x++) {
        const xa = Math.max(0, x - radius), xb = Math.min(w - 1, x + radius);
        const count = (xb - xa + 1) * (yb - ya + 1);
        const sum = integral[(yb + 1) * W + xb + 1] - integral[ya * W + xb + 1] -
          integral[(yb + 1) * W + xa] + integral[ya * W + xa];
        out[y * w + x] = lum[y * w + x] * count * 100 < sum * 88 ? 0 : 255;
      }
    }
    return out;
  }

  /** Rotates clockwise by `turns` quarter turns. */
  function rotate(src, w, h, channels, turns) {
    const out = new Uint8Array(src.length);
    const ow = turns % 2 ? h : w;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let dx, dy;
        if (turns === 1) { dx = h - 1 - y; dy = x; }
        else if (turns === 2) { dx = w - 1 - x; dy = h - 1 - y; }
        else { dx = y; dy = w - 1 - x; }
        const s = (y * w + x) * channels;
        const d = (dy * ow + dx) * channels;
        for (let c = 0; c < channels; c++) out[d + c] = src[s + c];
      }
    }
    return out;
  }

  // --------------------------------------------------------- browser glue

  function makeCanvas(w, h) {
    if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(w, h);
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    return canvas;
  }

  function canvasToBlob(canvas, type, quality) {
    if (canvas.convertToBlob) return canvas.convertToBlob({ type, quality });
    return new Promise((resolve) => canvas.toBlob(resolve, type, quality));
  }

  /** Decodes an image Blob into upright RGB no larger than WORKING_SIDE. */
  async function decodeWorking(blob) {
    const probe = await createImageBitmap(blob, { imageOrientation: 'from-image' });
    const scale = Math.min(1, WORKING_SIDE / Math.max(probe.width, probe.height));
    const w = Math.max(1, Math.round(probe.width * scale));
    const h = Math.max(1, Math.round(probe.height * scale));
    let bitmap = probe;
    if (scale < 1) {
      bitmap = await createImageBitmap(blob, {
        imageOrientation: 'from-image',
        resizeWidth: w,
        resizeHeight: h,
        resizeQuality: 'high',
      });
      probe.close();
    }
    const canvas = makeCanvas(w, h);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff'; // transparent PNGs scan as white paper
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close();
    const rgba = ctx.getImageData(0, 0, w, h).data;
    const rgb = new Uint8Array(w * h * 3);
    for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    return { rgb, width: w, height: h };
  }

  async function encode(result) {
    const { pixels, width, height, channels } = result;
    const canvas = makeCanvas(width, height);
    const ctx = canvas.getContext('2d');
    const image = ctx.createImageData(width, height);
    const data = image.data;
    for (let i = 0, j = 0; i < width * height; i++, j += channels) {
      const r = pixels[j];
      data[i * 4] = r;
      data[i * 4 + 1] = channels === 3 ? pixels[j + 1] : r;
      data[i * 4 + 2] = channels === 3 ? pixels[j + 2] : r;
      data[i * 4 + 3] = 255;
    }
    ctx.putImageData(image, 0, 0);
    return channels === 1 && result.bilevel
      ? canvasToBlob(canvas, 'image/png')
      : canvasToBlob(canvas, 'image/jpeg', JPEG_QUALITY);
  }

  /**
   * Full scan of an image Blob.
   * options: { filter: 'auto'|'grayscale'|'blackWhite'|'original',
   *            crop: true (use the detected sheet), quarterTurns: 0..3 }
   * Resolves to { blob, extension, autoDetected, width, height }.
   */
  async function scanBlob(blob, options) {
    const opts = Object.assign({ filter: 'auto', crop: true, quarterTurns: 0 }, options || {});
    const work = await decodeWorking(blob);
    const quad = opts.crop ? detectQuad(work.rgb, work.width, work.height) : null;
    const result = render(work.rgb, work.width, work.height, quad || FULL_FRAME, opts.filter, opts.quarterTurns);
    result.bilevel = opts.filter === 'blackWhite';
    const out = await encode(result);
    return {
      blob: out,
      extension: result.bilevel ? '.png' : '.jpg',
      autoDetected: !!quad,
      width: result.width,
      height: result.height,
    };
  }

  const api = {
    WORKING_SIDE, FULL_FRAME, FILTERS,
    shrink, luma, detectQuad, render, warp, enhanceDocument, flattenLighting,
    adaptiveThreshold, rotate, scanBlob,
  };
  root.DiwanScanner = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof self !== 'undefined' ? self : globalThis);
