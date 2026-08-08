const RESOURCE = new URLSearchParams(location.search).get('resource') || 'unknown';
const app = document.getElementById('app');
const notif = document.getElementById('notif');

const post = (name, data = {}) =>
    fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).then(r => r.json()).catch(() => ({}));

const notify = (text) => {
    notif.textContent = text;
    notif.classList.add('show');
    clearTimeout(notify._t);
    notify._t = setTimeout(() => notif.classList.remove('show'), 2000);
};

document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const t = btn.dataset.tab;
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b === btn));
        document.querySelectorAll('.tab').forEach(s => s.classList.toggle('active', s.dataset.tab === t));
        document.getElementById('tabTitle').textContent = btn.textContent;
        if (t === 'players') refreshPlayers();
    });
});

document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    const payload = btn.dataset.payload ? JSON.parse(btn.dataset.payload) : {};
    post(action, payload);
});

document.querySelectorAll('[data-toggle]').forEach(cb => {
    cb.addEventListener('change', () => {
        post('toggle', { key: cb.dataset.toggle, value: cb.checked });
    });
});

document.getElementById('closeBtn').onclick = () => post('close');

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
    if (!Array.isArray(players)) { list.innerHTML = '<li>none</li>'; return; }
    list.innerHTML = '';
    players.forEach(p => {
        const li = document.createElement('li');
        li.innerHTML = `
            <div>
                <div class="pname">${p.name} <span class="pmeta">#${p.serverId}</span></div>
                <div class="pmeta">${p.distance}m · ${p.health}hp</div>
            </div>
            <div class="pactions">
                <button data-a="tpToPlayer">TP</button>
                <button data-a="explodePlayer">Boom</button>
                <button data-a="firePlayer">Fire</button>
                <button data-a="rainCars">Rain</button>
                <button data-a="spectate">Spec</button>
            </div>
        `;
        li.querySelectorAll('.pactions button').forEach(b => {
            b.onclick = () => post(b.dataset.a, { id: p.serverId });
        });
        list.appendChild(li);
    });
}
document.getElementById('refreshPlayers').onclick = refreshPlayers;

window.addEventListener('message', (e) => {
    const d = e.data;
    if (d.action === 'setVisible') {
        app.classList.toggle('hidden', !d.visible);
        if (d.visible && d.state) {
            document.querySelectorAll('[data-toggle]').forEach(cb => {
                if (d.state[cb.dataset.toggle] !== undefined) cb.checked = d.state[cb.dataset.toggle];
            });
        }
    }
    if (d.action === 'notify') notify(d.text);
});

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') post('close');
});
