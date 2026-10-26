#!/usr/bin/env node
// Скриншоты для README (docs/screenshots/*.png, 512x512): заставка, меню, игра, GAME OVER — vector06js без окна.
//   node tools/shots.js [rom/jetpac.r0m]
'use strict';
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const E = require('./vec_emu');
const ROM = process.argv[2] || path.join(__dirname, '../rom/jetpac.r0m');
const OUT = path.join(__dirname, '../docs/screenshots');
const sym = {};
for (const l of fs.readFileSync(path.join(__dirname, '../build/vec/jetpac.sym'), 'latin1').split('\n')) {
  const q = l.match(/^(\w+):\s+EQU\s+0x([0-9A-F]+)/i); if (q) sym[q[1]] = parseInt(q[2], 16);
}
const rgb = (c) => [(c & 7) * 255 / 7 | 0, ((c >> 3) & 7) * 255 / 7 | 0, ((c >> 6) & 3) * 255 / 3 | 0];
function shot(m, name) {
  const pa = m.rd(sym.pal_ptr) | m.rd(sym.pal_ptr + 1) << 8;
  const PAL = Array.from({ length: 16 }, (_, i) => m.rd(pa + i));
  const W = 256, img = Buffer.alloc(W * W * 3);
  for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
    const a = ((x >> 3) << 8) | (255 - y), b = 7 - (x & 7), bit = (p) => (m.rd(p + a) >> b) & 1;
    img.set(rgb(PAL[bit(0x8000) << 3 | bit(0xA000) << 2 | bit(0xC000) << 1 | bit(0xE000)]), (y * W + x) * 3);
  }
  const p = path.join(OUT, name);
  fs.writeFileSync(p + '.ppm', Buffer.concat([Buffer.from(`P6 ${W} ${W} 255\n`), img]));
  execSync(`sips -s format png "${p}.ppm" --out "${p}.png" >/dev/null && rm "${p}.ppm" && sips -z 512 512 "${p}.png" >/dev/null`);
  console.log(name);
}
const m = E.mk(ROM);
const set = (r, b, d) => { if (d) m.keyboard.matrix[r] |= b; else m.keyboard.matrix[r] &= ~b; };
const run = (n, fn) => { for (let i = 0; i < n; i++) { if (fn) fn(i); m.frame(); } };
run(100); shot(m, 'title');
set(7, 0x80, 1); run(8); set(7, 0x80, 0); run(60); shot(m, 'menu');
// игра в бессмертии (F1+F3): снимок, когда в воздухе Джетмен и не меньше трёх пришельцев
set(1, 0x28, 1); run(8); set(1, 0x28, 0); run(500);
let s = 7; const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
const busy = () => { let n = 0; for (let k = 0; k < 6; k++) if (m.rd(0x5d50 + 8 * k)) n++; return n >= 3 && (m.rd(0x5d00) & 0x3f) === 1 && m.rd(0x5d02) < 150; };
const play = (n) => run(n, (i) => { if (i % 20 === 0) { set(0, 0x10, rnd() < .35); set(0, 0x40, rnd() < .35); set(0, 0x20, rnd() < .55); set(7, 0x80, rnd() < .5); } });
for (const name of ['game-1', 'game-2']) {
  play(300);
  for (let k = 0; k < 2000 && !busy(); k++) play(1);
  shot(m, name);
}
// конец игры: новая машина, старт без управления, снимок в паузе после надписи
const g = E.mk(ROM);
const gs = (r, b, d) => { if (d) g.keyboard.matrix[r] |= b; else g.keyboard.matrix[r] &= ~b; };
for (let i = 0; i < 100; i++) g.frame();
gs(7, 0x80, 1); for (let i = 0; i < 8; i++) g.frame(); gs(7, 0x80, 0); for (let i = 0; i < 60; i++) g.frame();
gs(2, 0x20, 1); for (let i = 0; i < 8; i++) g.frame(); gs(2, 0x20, 0);
for (let i = 0; i < 20000; i++) { g.frame(); if (g.cpu.pc >= sym.wait_frames && g.cpu.pc < sym.update_hiscore) { for (let k = 0; k < 10; k++) g.frame(); break; } }
shot(g, 'game-over');
