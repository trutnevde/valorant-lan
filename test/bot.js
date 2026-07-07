// Бот-болванчик: подключается вторым игроком и стоит на своём спавне.
// Использование: node test/bot.js [ws://host:port]
import WebSocket from 'ws';

const url = process.argv[2] || 'ws://127.0.0.1:27015';
const ws = new WebSocket(url);
let myId = 0, role = 'defend';
const spawns = { attack: [0, 0, 19.5], defend: [0, 0, -19.5] };

ws.on('open', () => {
  ws.send(JSON.stringify({ t: 'join', name: 'Денис-бот', char: 'denis' }));
  console.log('Бот подключился к', url);
});
ws.on('message', (raw) => {
  const m = JSON.parse(raw);
  if (m.t === 'welcome') myId = m.id;
  if (m.t === 'roundStart') {
    role = m.roles[myId];
    console.log(`Раунд ${m.round}, бот ${role === 'attack' ? 'атакует' : 'защищает'}`);
  }
  if (m.t === 'matchEnd') console.log('Матч окончен', m.score);
});
ws.on('close', () => { console.log('Бот отключён'); process.exit(0); });

setInterval(() => {
  if (ws.readyState !== 1) return;
  const p = spawns[role];
  const wobble = Math.sin(Date.now() / 700) * 1.5; // слегка ходит, чтобы было видно движение
  ws.send(JSON.stringify({ t: 'state', p: [p[0] + wobble, p[1], p[2]], yaw: role === 'attack' ? 0 : Math.PI, pitch: 0, crouch: false }));
}, 50);
