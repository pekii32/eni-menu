const params = new URLSearchParams(location.search);
const RESOURCE = params.get('resource');
const MODE = RESOURCE ? 'nui' : 'http';
let API = params.get('api') || localStorage.getItem('eniApi') || 'http://localhost:8765';

const endpoint = (name) => MODE === 'nui'
    ? `https://${RESOURCE}/${name}`
    : `${API}/${name}`;

const notif = document.getElementById('notif');
const connDot = document.getElementById('connDot');
const connText = document.getElementById('connText');
const targetHint = document.getElementById('targetHint');

const post = (name, data = {}) =>
    fetch(endpoint(name), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).then(r => r.json()).catch(e => ({ ok: false, error: e.message }));

const get = (name) =>
    fetch(endpoint(name)).then(r => r.json()).catch(() => null);

function notify(text, ok = true) {
    notif.textContent = text;
    notif.classList.toggle('err', !ok);
    notif.classList.add('show');
    clearTimeout(notify._t);
    notify._t = setTimeout(() => notif.classList.remove('show'), 2200);
}

document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const t = btn.dataset.tab;
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b === btn));
        document.querySelectorAll('.tab').forEach(s => s.classList.toggle('active', s.dataset.tab === t));
        document.getElementById('tabTitle').textContent = btn.textContent;
        if (t === 'players') refreshPlayers();
        if (t === 'exec' || t === 'settings') loadResources();
    });
});

document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    const payload = btn.dataset.payload ? JSON.parse(btn.dataset.payload) : {};
    post(action, payload).then(r => {
        if (r && r.ok === false) notify(r.error || 'failed', false);
    });
});

document.querySelectorAll('[data-toggle]').forEach(cb => {
    cb.addEventListener('change', () => {
        post('toggle', { key: cb.dataset.toggle, value: cb.checked }).then(r => {
            if (r && r.ok === false) { cb.checked = !cb.checked; notify(r.error || 'toggle failed', false); }
        });
    });
});

document.getElementById('tpCoordsBtn').onclick = () => {
    post('tpCoords', {
        x: parseFloat(document.getElementById('tpx').value) || 0,
        y: parseFloat(document.getElementById('tpy').value) || 0,
        z: parseFloat(document.getElementById('tpz').value) || 100,
    });
};

document.getElementById('spawnVehBtn').onclick = () => {
    post('spawnVehicle', { model: document.getElementById('vehModel').value || 'adder' });
};

const timeSlider = document.getElementById('timeSlider');
const timeVal = document.getElementById('timeVal');
timeSlider.addEventListener('input', () => { timeVal.textContent = timeSlider.value; });
timeSlider.addEventListener('change', () => post('setTime', { hour: timeSlider.value }));

async function refreshPlayers() {
    const list = document.getElementById('playerList');
    list.innerHTML = '<li>loading...</li>';
    const players = await post('getPlayers');
    if (!Array.isArray(players)) { list.innerHTML = '<li>no data — check API</li>'; return; }
    if (players.length === 0) { list.innerHTML = '<li>no players yet (bootstrap needs ~2s after inject)</li>'; return; }
    list.innerHTML = '';
    players.forEach(p => {
        const li = document.createElement('li');
        li.innerHTML = `
            <div>
                <div class="pname">${escapeHtml(p.name)} <span class="pmeta">#${p.serverId}</span></div>
                <div class="pmeta">${p.distance}m · ${p.health}hp</div>
            </div>
            <div class="pactions">
                <button data-a="tpToPlayer">TP</button>
                <button data-a="explodePlayer">Boom</button>
                <button data-a="firePlayer">Fire</button>
                <button data-a="rainCars">Rain</button>
                <button data-a="spectate">Spec</button>
            </div>`;
        li.querySelectorAll('.pactions button').forEach(b => {
            b.onclick = () => post(b.dataset.a, { id: p.serverId });
        });
        list.appendChild(li);
    });
}
document.getElementById('refreshPlayers').onclick = refreshPlayers;

function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

async function loadResources() {
    const rs = await get('resources');
    if (!Array.isArray(rs)) return;
    for (const id of ['execResource', 'targetResource']) {
        const sel = document.getElementById(id);
        const cur = sel.value;
        sel.innerHTML = rs.map(r => `<option value="${escapeHtml(r)}">${escapeHtml(r)}</option>`).join('');
        if (cur && rs.includes(cur)) sel.value = cur;
    }
}
document.getElementById('loadResources').onclick = loadResources;

document.getElementById('execRun').onclick = async () => {
    const code = document.getElementById('execCode').value;
    const resource = document.getElementById('execResource').value;
    const r = await post('exec', { code, resource });
    notify(r.ok ? 'executed' : (r.error || 'failed'), r.ok);
};
document.getElementById('execClear').onclick = () => {
    document.getElementById('execCode').value = '';
};

document.getElementById('apiUrl').value = API;
document.getElementById('saveApi').onclick = () => {
    const v = document.getElementById('apiUrl').value.trim().replace(/\/$/, '');
    if (!v) return;
    API = v;
    localStorage.setItem('eniApi', v);
    notify('API URL saved');
    checkConn();
};

document.getElementById('saveTarget').onclick = async () => {
    const r = await post('target', { resource: document.getElementById('targetResource').value });
    notify(r.ok ? 'target set' : (r.error || 'failed'), r.ok);
    checkConn();
};

document.getElementById('rebootstrap').onclick = async () => {
    const r = await post('target', { resource: document.getElementById('targetResource').value || 'spawnmanager' });
    notify(r.ok ? 're-bootstrapped' : (r.error || 'failed'), r.ok);
};

async function checkConn() {
    if (MODE === 'nui') {
        // In NUI mode the visibility comes from lua via postMessage.
        connDot.classList.add('online');
        connText.textContent = `nui: ${RESOURCE}`;
        targetHint.textContent = `mode: red engine`;
        return;
    }
    const r = await get('status');
    if (r && r.ok) {
        connDot.classList.add('online');
        connText.textContent = `${API.replace(/^https?:\/\//, '')}`;
        targetHint.textContent = `target: ${r.target || '—'}`;
    } else {
        connDot.classList.remove('online');
        connText.textContent = 'disconnected';
        targetHint.textContent = 'target: —';
    }
}

// NUI visibility bridge (Red Engine executor path)
if (MODE === 'nui') {
    document.getElementById('app').classList.add('hidden');
    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'setVisible') {
            document.getElementById('app').classList.toggle('hidden', !d.visible);
        }
        if (d.action === 'notify' && d.text) notify(d.text);
    });
    document.addEventListener('keyup', (e) => {
        if (e.key === 'Escape') post('close');
    });
}

setInterval(checkConn, 4000);
checkConn();
if (MODE === 'http') loadResources();
