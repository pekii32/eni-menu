// eni.menu renderer.
// DUI has no page->lua channel, so this file never sends anything back.
// Lua owns all state and input; we just draw whatever it pushes over
// SendDuiMessage. Row heights here MUST match the constants in menu.lua
// (section 34px, row 46px) or lua's mouse hit-testing drifts out of sync.

const app    = document.getElementById('app');
const nav    = document.getElementById('nav');
const rowsEl = document.getElementById('rows');
const title  = document.getElementById('title');
const notif  = document.getElementById('notif');
const cursor = document.getElementById('cursor');

let lastTabs = null;
let notifyTimer = null;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function renderTabs(tabs, activeIndex, hoverTab) {
    const key = tabs.join('|');
    if (key !== lastTabs) {
        nav.innerHTML = tabs.map(t => `<div class="tab-btn">${esc(t)}</div>`).join('');
        lastTabs = key;
    }
    [...nav.children].forEach((el, i) => {
        el.classList.toggle('active', i + 1 === activeIndex);
        el.classList.toggle('hover', i + 1 === hoverTab);
    });
}

function rowHtml(r, hovered) {
    if (r.t === 'section') return `<div class="sec">${esc(r.label)}</div>`;
    if (r.t === 'empty')   return `<div class="row empty">${esc(r.label)}</div>`;

    const cls = ['row'];
    if (hovered) cls.push('hover');
    if (r.danger) cls.push('danger');

    let right = '';
    if (r.t === 'toggle') {
        right = `<span class="sw ${r.on ? 'on' : ''}"></span>`;
    } else if (r.t === 'value') {
        right = `<span class="val">${esc(r.value)}</span><i class="chev"></i>`;
    } else if (r.t === 'player') {
        right = `<i class="chev"></i>`;
    } else {
        right = `<i class="chev"></i>`;
    }

    const label = r.sub
        ? `<span class="lbl"><b>${esc(r.label)}</b><em>${esc(r.sub)}</em></span>`
        : `<span class="lbl">${esc(r.label)}</span>`;

    return `<div class="${cls.join(' ')}">${label}${right}</div>`;
}

function render(d) {
    renderTabs(d.tabs || [], d.tabIndex || 0, d.hoverTab || 0);
    title.textContent = d.title || '';
    rowsEl.innerHTML = (d.rows || [])
        .map((r, i) => rowHtml(r, i + 1 === d.hoverRow))
        .join('');

    if (d.cursor) {
        cursor.style.transform = `translate(${d.cursor.x}px, ${d.cursor.y}px)`;
        cursor.classList.add('on');
    }

    if (d.notify) {
        if (notif.textContent !== d.notify) {
            notif.textContent = d.notify;
            notif.classList.add('show');
        }
        clearTimeout(notifyTimer);
        notifyTimer = setTimeout(() => notif.classList.remove('show'), 2200);
    }
}

window.addEventListener('message', (e) => {
    let d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch { return; } }
    if (!d || !d.action) return;

    if (d.action === 'visible') {
        app.classList.toggle('hidden', !d.visible);
    } else if (d.action === 'render') {
        app.classList.remove('hidden');
        render(d);
    }
});
