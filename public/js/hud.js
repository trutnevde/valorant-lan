// HUD v2: лобби с командами, закупка по категориям, командная таблица,
// миникарта (союзники/враги/дымы/шип), режим прицеливания по карте
import { WEAPONS, WEAPON_CATS, ARMOR, CHARACTERS, MAPS } from './shared.js';

const $ = (id) => document.getElementById(id);
const now = () => performance.now() / 1000;

export class HUD {
  constructor(G) {
    this.G = G;
    this.announceTimer = 0;
    this.lastDamageT = 0;
    this.abSlots = {};
    this.buildAbilitySlots();
    this.buyError = '';
    this.mapTargetCb = null;
    this.lobbyHooks = null;

    $('minimap').addEventListener('click', (e) => {
      if (!this.mapTargetCb) return;
      const rect = e.target.getBoundingClientRect();
      const px = (e.clientX - rect.left) / rect.width * this.mmW;
      const py = (e.clientY - rect.top) / rect.height * this.mmH;
      const wx = px / this.mmScaleX - this.halfW;
      const wz = py / this.mmScaleY - this.halfD;
      const cb = this.mapTargetCb;
      this.endMapTarget();
      cb(wx, wz);
    });
  }

  // ===== лобби =====
  bindLobby(hooks) {
    this.lobbyHooks = hooks;
    $('btnAddBotA').addEventListener('click', () => hooks.addBot('A'));
    $('btnAddBotB').addEventListener('click', () => hooks.addBot('B'));
    $('btnDelBotA').addEventListener('click', () => hooks.delBot('A'));
    $('btnDelBotB').addEventListener('click', () => hooks.delBot('B'));
    $('btnSwitchTeam').addEventListener('click', () => hooks.switchTeam());
    $('btnStart').addEventListener('click', () => hooks.start());
    const mb = $('mapButtons');
    mb.innerHTML = '';
    for (const [id, m] of Object.entries(MAPS)) {
      const b = document.createElement('button');
      b.textContent = m.name.toUpperCase();
      b.dataset.map = id;
      b.title = m.desc;
      b.addEventListener('click', () => hooks.setMap(id));
      mb.appendChild(b);
    }
  }

  renderLobby(data, myId) {
    const isHost = data.hostId === myId;
    $('lobbyOverlay').classList.toggle('hide-host', !isHost);
    $('mapRowGuest').classList.toggle('hidden', isHost);
    $('mapNameGuest').textContent = (MAPS[data.map] || {}).name || data.map;
    for (const b of $('mapButtons').children) b.classList.toggle('sel', b.dataset.map === data.map);

    const render = (team, el) => {
      el.innerHTML = '';
      for (const p of data.players.filter(x => x.team === team)) {
        const row = document.createElement('div');
        row.className = 'roster-row' + (p.id === myId ? ' me' : '');
        row.innerHTML = `${p.id === data.hostId ? '<span class="r-host">★</span>' : ''}${p.bot ? '🤖' : ''} <b>${esc(p.name)}</b><span class="r-char">${CHARACTERS[p.char].name.toUpperCase()}</span>`;
        el.appendChild(row);
      }
    };
    render('A', $('teamARoster'));
    render('B', $('teamBRoster'));

    const a = data.players.filter(p => p.team === 'A').length;
    const b = data.players.filter(p => p.team === 'B').length;
    $('btnStart').disabled = !(a >= 1 && b >= 1);
    $('lobbyStatus').textContent = data.inMatch
      ? 'Матч идёт — дождись конца'
      : isHost ? 'Ты хост: собери команды и жми «Начать матч»' : 'Ждём, пока хост начнёт матч';
    $('lobbyHint').textContent = isHost && (a < 1 || b < 1) ? 'В каждой команде нужен хотя бы один игрок или бот' : '';
  }

  // ===== прицеливание по карте (Вова) =====
  mapTarget(hint, cb) {
    this.mapTargetCb = cb;
    $('minimap').classList.add('targeting');
    $('mapTargetHint').textContent = hint;
    $('mapTargetHint').classList.remove('hidden');
    document.exitPointerLock && document.exitPointerLock();
  }
  endMapTarget() {
    this.mapTargetCb = null;
    $('minimap').classList.remove('targeting');
    $('mapTargetHint').classList.add('hidden');
    if (this.G.relock) this.G.relock();
  }

  // ===== базовые значения =====
  setHp(hp, maxHp) {
    $('hpVal').textContent = Math.max(0, hp);
    const pct = Math.max(0, hp / maxHp * 100);
    $('hpBar').style.width = pct + '%';
    $('hpBar').classList.toggle('low', hp <= 30);
  }
  setArmor(v) {
    $('armorVal').textContent = v;
    $('armorBar').style.width = Math.min(100, v * 2) + '%';
  }
  setWeapon(name, mag, res) {
    $('weaponName').textContent = String(name).toUpperCase();
    $('ammoMag').textContent = mag;
    $('ammoReserve').textContent = res;
  }
  setCredits(n) {
    $('creditsHud').textContent = '¤ ' + n;
    $('creditsVal').textContent = '¤ ' + n;
  }
  setScore(mine, opp) {
    $('scoreMe').textContent = mine;
    $('scoreOpp').textContent = opp;
  }
  setRound(n) { $('roundLabel').textContent = 'РАУНД ' + n; }
  setRole(text) { $('roleLabel').textContent = text; }
  setTimer(sec, danger) {
    const s = Math.max(0, Math.ceil(sec));
    $('timer').textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
    $('timer').classList.toggle('danger', !!danger);
  }

  announce(main, sub, dur = 2.5) {
    const a = $('announce'), b = $('subAnnounce');
    if (main !== null && main !== undefined) { a.textContent = main; a.classList.toggle('show', !!main); }
    if (sub !== null && sub !== undefined) { b.textContent = sub; b.classList.toggle('show', !!sub); }
    clearTimeout(this.announceTimer);
    this.announceTimer = setTimeout(() => {
      a.classList.remove('show');
      b.classList.remove('show');
    }, dur * 1000);
  }

  killfeed(killer, weaponLabel, victim, hs) {
    const row = document.createElement('div');
    row.className = 'kf-row';
    row.innerHTML = `<b>${esc(killer)}</b><span class="kf-w">[${esc(weaponLabel)}${hs ? ' <span class="kf-hs">☠ В ГОЛОВУ</span>' : ''}]</span><b>${esc(victim)}</b>`;
    $('killfeed').prepend(row);
    setTimeout(() => row.remove(), 6000);
    while ($('killfeed').children.length > 6) $('killfeed').lastChild.remove();
  }

  hitmarker(hs) {
    const h = $('hitmarker');
    h.classList.toggle('hs', !!hs);
    h.classList.remove('show');
    void h.offsetWidth;
    h.classList.add('show');
  }

  damage() { this.lastDamageT = now(); }

  progress(label, pct) {
    if (pct < 0) { $('progressWrap').classList.add('hidden'); return; }
    $('progressWrap').classList.remove('hidden');
    $('progressLabel').textContent = label;
    $('progressFill').style.width = Math.min(100, pct * 100) + '%';
  }

  chat(name, text, color) {
    const row = document.createElement('div');
    row.className = 'chat-row';
    row.innerHTML = `<b style="color:${color || '#0ac8b9'}">${esc(name)}:</b> ${esc(text)}`;
    $('chatLog').appendChild(row);
    setTimeout(() => row.remove(), 9000);
    while ($('chatLog').children.length > 6) $('chatLog').firstChild.remove();
  }

  // ===== способности =====
  buildAbilitySlots() {
    const wrap = $('abilities');
    wrap.innerHTML = '';
    for (const k of ['C', 'Q', 'E', 'X']) {
      const d = document.createElement('div');
      d.className = 'abSlot' + (k === 'X' ? ' ult' : '');
      d.innerHTML = `<div class="k">${k}</div><div class="n"></div><div class="c"></div>`;
      wrap.appendChild(d);
      this.abSlots[k] = d;
    }
  }
  updateAbilities(state) {
    for (const k of ['C', 'Q', 'E', 'X']) {
      const s = state[k], el = this.abSlots[k];
      el.querySelector('.n').textContent = s.label;
      el.querySelector('.c').textContent = s.val;
      el.classList.toggle('empty', !s.ok && !s.passive);
      el.classList.toggle('active', !!s.active);
      el.classList.toggle('ready', !!s.ult && s.ok);
    }
  }

  // ===== закупка =====
  buildBuy(onBuy) {
    const grid = $('buyGrid');
    grid.innerHTML = '';
    const addCard = (id, title, price, statHtml) => {
      const d = document.createElement('div');
      d.className = 'buy-item';
      d.dataset.item = id;
      d.innerHTML = `<div class="bi-name">${title}</div><div class="bi-price">${price ? '¤ ' + price : 'БЕСПЛАТНО'}</div><div class="bi-stat">${statHtml}</div>`;
      d.addEventListener('click', () => onBuy(id));
      grid.appendChild(d);
    };
    for (const cat of WEAPON_CATS) {
      const label = document.createElement('div');
      label.className = 'buy-cat';
      label.textContent = cat.name.toUpperCase();
      grid.appendChild(label);
      for (const [id, w] of Object.entries(WEAPONS)) {
        if (w.cat !== cat.key) continue;
        const extra = w.pellets ? `${w.pellets} ДРОБИН · ` : '';
        addCard(id, w.name, w.price, `${extra}УРОН ${w.dmg}/${w.head}<br>${w.rpm} ВЫСТР/МИН${w.scope ? ' · ПРИЦЕЛ' : ''}`);
      }
    }
    const label = document.createElement('div');
    label.className = 'buy-cat';
    label.textContent = 'БРОНЯ';
    grid.appendChild(label);
    for (const [id, a] of Object.entries(ARMOR)) {
      addCard(id, a.name, a.price, `+${a.value} БРОНИ<br>ПОГЛОЩАЕТ 66% УРОНА`);
    }
  }
  refreshBuy() {
    const G = this.G;
    for (const d of $('buyGrid').children) {
      if (!d.dataset.item) continue;
      const id = d.dataset.item;
      const price = WEAPONS[id] ? WEAPONS[id].price : ARMOR[id].price;
      const owned = WEAPONS[id]
        ? (G.weapons.loadout.primary === id || G.weapons.loadout.sidearm === id)
        : G.me.armor >= ARMOR[id].value;
      d.classList.toggle('owned', owned);
      d.classList.toggle('cant', !owned && price > G.me.credits);
    }
  }
  openBuy() {
    this.G.buyOpen = true;
    $('buyMenu').classList.remove('hidden');
    this.refreshBuy();
    document.exitPointerLock && document.exitPointerLock();
  }
  closeBuy() {
    this.G.buyOpen = false;
    $('buyMenu').classList.add('hidden');
  }

  // ===== таблица =====
  scoreboard(show) {
    const G = this.G;
    $('scoreboard').classList.toggle('hidden', !show);
    if (!show) return;
    const rows = [];
    const mk = (p, stats, me) => `<tr${me ? ' style="color:#0ac8b9"' : ''}>
      <td>${p.team === G.myTeam ? '🟦' : '🟥'} ${p.bot ? '🤖 ' : ''}${esc(p.name)}</td>
      <td>${CHARACTERS[p.char].name}</td><td>${stats.kills}</td><td>${stats.deaths}</td>
      <td>${p.id === G.myId ? G.me.ult : '—'}</td></tr>`;
    const sorted = [...G.players.values()].sort((a, b) => (a.team === G.myTeam ? 0 : 1) - (b.team === G.myTeam ? 0 : 1));
    for (const p of sorted) {
      rows.push(mk(p, G.stats[p.id] || { kills: 0, deaths: 0 }, p.id === G.myId));
    }
    $('sbRows').innerHTML = rows.join('');
  }

  // ===== конец матча =====
  endScreen(win, scoreText, statsText) {
    $('endOverlay').classList.remove('hidden');
    const t = $('endTitle');
    t.textContent = win ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ';
    t.className = win ? 'win' : 'lose';
    $('endScore').textContent = scoreText;
    $('endStats').innerHTML = statsText;
    document.exitPointerLock && document.exitPointerLock();
  }
  hideEnd() { $('endOverlay').classList.add('hidden'); }

  // ===== миникарта =====
  prepMinimap(def) {
    this.halfW = def.SIZE.w / 2 + 1;
    this.halfD = def.SIZE.d / 2 + 1;
    const cv = $('minimap');
    cv.width = 220;
    cv.height = Math.round(220 * (this.halfD / this.halfW));
    this.mmW = cv.width; this.mmH = cv.height;
    this.mmScaleX = this.mmW / (this.halfW * 2);
    this.mmScaleY = this.mmH / (this.halfD * 2);
    const off = document.createElement('canvas');
    off.width = this.mmW; off.height = this.mmH;
    const c = off.getContext('2d');
    c.fillStyle = 'rgba(30,42,54,0.9)';
    c.fillRect(0, 0, this.mmW, this.mmH);
    const rect = ([cx, cz, w, d]) => {
      c.fillRect((cx - w / 2 + this.halfW) * this.mmScaleX, (cz - d / 2 + this.halfD) * this.mmScaleY, w * this.mmScaleX, d * this.mmScaleY);
    };
    c.fillStyle = '#5a6b7a';
    def.walls.forEach(rect);
    c.fillStyle = '#4a5866';
    def.crates.forEach(rect);
    c.fillStyle = 'rgba(255,70,85,0.18)';
    for (const s of Object.values(def.sites)) {
      c.fillRect((s.x - s.w / 2 + this.halfW) * this.mmScaleX, (s.z - s.d / 2 + this.halfD) * this.mmScaleY, s.w * this.mmScaleX, s.d * this.mmScaleY);
    }
    c.fillStyle = 'rgba(255,70,85,0.8)';
    c.font = '700 13px Arial';
    for (const [k, s] of Object.entries(def.sites)) {
      c.fillText(k, (s.x + this.halfW) * this.mmScaleX - 4, (s.z + this.halfD) * this.mmScaleY + 5);
    }
    this.mmStatic = off;
  }

  mmPt(x, z) { return [(x + this.halfW) * this.mmScaleX, (z + this.halfD) * this.mmScaleY]; }

  drawMinimap() {
    const G = this.G;
    if (!this.mmStatic) return;
    const c = $('minimap').getContext('2d');
    const t = now();
    c.drawImage(this.mmStatic, 0, 0);
    // дымы
    for (const s of G.abilities.smokes) {
      if (t > s.until) continue;
      const [sx, sy] = this.mmPt(s.pos.x, s.pos.z);
      c.fillStyle = 'rgba(160,175,190,0.55)';
      c.beginPath(); c.arc(sx, sy, s.r * this.mmScaleX, 0, 7); c.fill();
    }
    // шип
    if (G.spikePos) {
      const [sx, sy] = this.mmPt(G.spikePos[0], G.spikePos[2]);
      c.fillStyle = (t % 0.8 < 0.4) ? '#ff2233' : '#881122';
      c.beginPath(); c.arc(sx, sy, 4, 0, 7); c.fill();
    }
    // игроки
    for (const [pid, r] of G.remotes) {
      const info = G.players.get(pid);
      if (!info || !r.alive) continue;
      const [ox, oy] = this.mmPt(r.pos.x, r.pos.z);
      if (info.team === G.myTeam) {
        c.fillStyle = '#0ac8b9';
        c.beginPath(); c.arc(ox, oy, 3, 0, 7); c.fill();
      } else {
        const spotted = t < (G.spottedUntil.get(pid) || 0) || t < G.xrayUntil || t < (G.revealed.get(pid) || 0);
        if (spotted) {
          c.fillStyle = '#ff4655';
          c.beginPath(); c.arc(ox, oy, 4, 0, 7); c.fill();
        }
      }
    }
    // я
    const [mx, my] = this.mmPt(G.player.pos.x, G.player.pos.z);
    const a = -G.player.yaw - Math.PI / 2;
    c.fillStyle = 'rgba(10,200,185,0.25)';
    c.beginPath();
    c.moveTo(mx, my);
    c.arc(mx, my, 16, a - 0.5, a + 0.5);
    c.closePath(); c.fill();
    c.fillStyle = '#0ac8b9';
    c.beginPath(); c.arc(mx, my, 4, 0, 7); c.fill();
  }

  // ===== кадровые оверлеи =====
  frame() {
    const G = this.G;
    const t = now();
    const blind = Math.max(0, G.blindUntil - t);
    const fo = $('flashOverlay');
    fo.style.opacity = Math.min(1, blind / 0.5);
    fo.style.background = G.blindStink ? '#9bb86a' : '#fff';
    $('blindHint').style.opacity = blind > 0.3 ? 1 : 0;
    $('blindHint').textContent = blind > 0.3 ? 'ОСЛЕПЛЁН' : '';
    const dmg = Math.max(0, 1 - (t - this.lastDamageT) / 0.5);
    $('dmgVignette').style.opacity = dmg * 0.9;
    this.drawMinimap();
  }
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}
