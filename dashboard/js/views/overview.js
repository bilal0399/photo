/* نظرة عامة — headline numbers and simple single-series charts. */
(function () {
  'use strict';
  const { h, icon, fmtNum, fmtDate } = window.U;

  const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

  function kpi(label, value, iconName, hint, onClick) {
    return h('div', { class: `card kpi ${onClick ? 'link' : ''}`, onclick: onClick, role: onClick ? 'button' : null, tabindex: onClick ? 0 : null },
      h('div', { class: 'label' }, icon(iconName), label),
      h('div', { class: 'value num' }, fmtNum(value)),
      hint ? h('div', { class: 'hint' }, hint) : null);
  }

  /** Vertical bars for the last 12 months (one series, direct labels on hover). */
  function monthlyChart(docs) {
    const now = new Date();
    const buckets = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      buckets.push({ key: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`, label: MONTHS[d.getMonth()], year: d.getFullYear(), count: 0 });
    }
    const index = new Map(buckets.map((b) => [b.key, b]));
    for (const doc of docs) {
      const b = index.get(String(doc.doc_date || '').slice(0, 7));
      if (b) b.count++;
    }
    const max = Math.max(1, ...buckets.map((b) => b.count));
    const W = 720, H = 240, top = 20, bottom = 34, left = 8, right = 36; // y labels in the right margin
    const plotH = H - top - bottom;
    const step = (W - left - right) / buckets.length;
    const barW = Math.min(34, step - 10);
    const ticks = niceTicks(max);
    const ns = 'http://www.w3.org/2000/svg';
    const el = (tag, attrs, text) => {
      const n = document.createElementNS(ns, tag);
      for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
      if (text !== undefined) n.textContent = text;
      return n;
    };
    const svg = el('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': 'عدد الطلبات في آخر 12 شهراً' });
    for (const t of ticks) {
      const y = top + plotH - (t / ticks[ticks.length - 1]) * plotH;
      svg.append(el('line', { class: t === 0 ? 'axis' : 'grid-line', x1: left, x2: W - right, y1: y, y2: y }));
      svg.append(el('text', { x: W - right + 8, y: y + 4, 'text-anchor': 'start' }, String(t)));
    }
    const scaleMax = ticks[ticks.length - 1];
    const wrap = h('div', { class: 'chart' });
    const tip = h('div', { class: 'tooltip', hidden: true });
    buckets.forEach((b, i) => {
      // Right-to-left page: the oldest month sits on the right, the newest on the left.
      const slot = buckets.length - 1 - i;
      const x = left + slot * step + (step - barW) / 2;
      const bh = b.count === 0 ? 0 : Math.max(3, (b.count / scaleMax) * plotH);
      const y = top + plotH - bh;
      const g = el('g', {});
      // Rounded top, square base anchored to the axis.
      if (bh > 0) {
        const r = Math.min(4, bh, barW / 2);
        g.append(el('path', {
          class: 'bar',
          d: `M${x},${top + plotH} V${y + r} Q${x},${y} ${x + r},${y} H${x + barW - r} Q${x + barW},${y} ${x + barW},${y + r} V${top + plotH} Z`,
        }));
      }
      const hit = el('rect', { class: 'bar-hit', x: left + slot * step, y: top, width: step, height: plotH + bottom });
      hit.addEventListener('mouseenter', () => {
        tip.hidden = false;
        tip.textContent = `${b.label} ${b.year}: ${fmtNum(b.count)} طلب`;
        const rect = svg.getBoundingClientRect();
        tip.style.left = `${((x + barW / 2) / W) * rect.width}px`;
        tip.style.top = `${(y / H) * rect.height}px`;
        tip.style.transform = 'translate(-50%, -115%)';
      });
      hit.addEventListener('mouseleave', () => { tip.hidden = true; });
      g.append(hit);
      svg.append(g);
      svg.append(el('text', { x: x + barW / 2, y: H - 12, 'text-anchor': 'middle' }, b.label.slice(0, 3)));
      // Direct label only on the latest month and the busiest one.
      if (b.count > 0 && (i === buckets.length - 1 || b.count === max)) {
        svg.append(el('text', { class: 'value', x: x + barW / 2, y: y - 6, 'text-anchor': 'middle' }, String(b.count)));
      }
    });
    wrap.append(svg, tip);
    return wrap;
  }

  function niceTicks(max) {
    const raw = max / 4;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) || raw;
    const ticks = [];
    for (let v = 0; v <= max + step - 1e-9; v += step) ticks.push(Math.round(v));
    if (ticks.length < 2) ticks.push(step);
    return ticks;
  }

  /** Horizontal bars ranked by count; the rest folds into "أخرى". */
  function ranked(docs, column, limit, onPick) {
    const counts = new Map();
    for (const d of docs) {
      const k = d[column] || 'غير محدد';
      counts.set(k, (counts.get(k) || 0) + 1);
    }
    let rows = [...counts.entries()].sort((a, b) => b[1] - a[1]);
    if (rows.length > limit) {
      const rest = rows.slice(limit - 1).reduce((s, r) => s + r[1], 0);
      rows = rows.slice(0, limit - 1).concat([['أخرى', rest]]);
    }
    const max = Math.max(1, ...rows.map((r) => r[1]));
    if (!rows.length) return h('div', { class: 'empty-state' }, 'لا توجد بيانات بعد');
    return h('div', { class: 'hbars' }, rows.map(([name, count]) =>
      h('div', {
        class: 'hbar',
        title: `${name}: ${count}`,
        style: onPick && name !== 'أخرى' ? 'cursor:pointer' : null,
        onclick: onPick && name !== 'أخرى' ? () => onPick(name) : null,
      },
      h('span', { class: 'name' }, name),
      h('span', { class: 'track' }, h('span', { class: 'fill', style: `width:${(count / max) * 100}%;display:block` })),
      h('span', { class: 'v num' }, fmtNum(count)))));
  }

  async function render(root, app) {
    const Api = window.Api;
    const [docs, tasks] = await Promise.all([Api.documents(), Api.tasks().catch(() => [])]);
    const now = new Date();
    const thisMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const monthCount = docs.filter((d) => String(d.doc_date || '').startsWith(thisMonth)).length;
    const noAttachment = docs.filter((d) => !d.attachment_path).length;
    const pending = docs.filter((d) => d.status === Api.DEFAULT_STATUS).length;
    const outgoing = docs.filter((d) => d.direction === Api.OUTGOING).length;

    const recent = [...docs]
      .sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')))
      .slice(0, 7);

    root.append(
      h('div', { class: 'page-head' },
        h('div', {},
          h('h2', { class: 'title' }, `أهلاً ${Api.state.profile ? Api.state.profile.username : ''}`),
          h('p', { class: 'lead' }, 'ملخص الأرشيف وأدوات الإدارة في مكان واحد')),
        h('div', { class: 'actions' },
          h('a', { class: 'btn', href: '#/bulk' }, icon('images'), 'إرفاق صور جماعي'),
          h('a', { class: 'btn primary', href: '#/entry' }, icon('plus'), 'إدخال سريع'))),
      h('div', { class: 'grid kpis' },
        kpi('إجمالي الطلبات', docs.length, 'docs', `${fmtNum(outgoing)} صادر · ${fmtNum(docs.length - outgoing)} وارد`, () => app.go('#/documents')),
        kpi('هذا الشهر', monthCount, 'calendar', MONTHS[now.getMonth()]),
        kpi('بدون مرفق', noAttachment, 'image', 'اضغط لعرضها', () => app.go('#/documents?attachment=none')),
        kpi(Api.DEFAULT_STATUS, pending, 'clock', 'اضغط لعرضها', () => app.go(`#/documents?status=${encodeURIComponent(Api.DEFAULT_STATUS)}`)),
        kpi('المهمات', tasks.length, 'folder')),
      h('div', { class: 'grid two', style: 'margin-top:16px' },
        h('div', { class: 'card' },
          h('h3', {}, 'الطلبات حسب الشهر'),
          h('p', { class: 'card-sub' }, 'آخر 12 شهراً حسب تاريخ الكتاب'),
          monthlyChart(docs)),
        h('div', { class: 'card' },
          h('h3', {}, 'حسب الحالة'),
          h('p', { class: 'card-sub' }, 'اضغط على حالة لعرض طلباتها'),
          ranked(docs, 'status', 6, (v) => app.go(`#/documents?status=${encodeURIComponent(v)}`)))),
      h('div', { class: 'grid halves', style: 'margin-top:16px' },
        h('div', { class: 'card' },
          h('h3', {}, 'أكثر الجهات'),
          ranked(docs, 'requester', 7, (v) => app.go(`#/documents?party=${encodeURIComponent(v)}`))),
        h('div', { class: 'card' },
          h('h3', {}, 'آخر ما أُضيف'),
          recent.length
            ? h('div', { class: 'list' }, recent.map((d) =>
              h('div', { class: 'list-item' },
                h('span', { class: `badge ${d.direction === Api.OUTGOING ? 'info' : 'plain'}` }, d.direction || '—'),
                h('div', { class: 'grow' },
                  h('div', { class: 'title' }, `كتاب رقم `, h('span', { class: 'num' }, d.book_number || '—')),
                  h('div', { class: 'meta' }, `${fmtDate(d.doc_date)} · ${d.requester || ''} · ${d.summary || ''}`)),
                d.attachment_path ? null : h('span', { class: 'badge warn', title: 'بدون مرفق' }, 'بدون صورة'))))
            : h('div', { class: 'empty-state' }, 'لا توجد طلبات بعد'))),
    );
  }

  window.Views = window.Views || {};
  window.Views.overview = { title: 'نظرة عامة', render };
})();
