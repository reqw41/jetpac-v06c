#!/usr/bin/env node
// Снимок Jetpac на Векторе без окна (vector06js через tools/vec_emu.js): N кадров с планом клавиш, PNG.
//   node tools/vecshot.js build/vec/jetpac.r0m <кадров> "<кадр>:<клавиша>+ <кадр>:<клавиша>- ..." [out.png]
// Клавиши — матрица Вектора (a..z, 0..9, space, vk, left, up, right, down). Картинка — 256x256 по плоскостям
// с палитрой игры (pal_vec, src/vec/main.asm), чёрная плоскость не видна.
'use strict';
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const E = require('./vec_emu');
const [ROM, NS, PLAN, OUT] = process.argv.slice(2);
const m = E.mk(ROM);
const VKEYS = { a: [4, 0x02], b: [4, 0x04], c: [4, 0x08], d: [4, 0x10], e: [4, 0x20], f: [4, 0x40], g: [4, 0x80],
  h: [5, 0x01], i: [5, 0x02], j: [5, 0x04], k: [5, 0x08], l: [5, 0x10], m: [5, 0x20], n: [5, 0x40], o: [5, 0x80],
  p: [6, 0x01], q: [6, 0x02], r: [6, 0x04], s: [6, 0x08], t: [6, 0x10], u: [6, 0x20], v: [6, 0x40], w: [6, 0x80],
  x: [7, 0x01], y: [7, 0x02], z: [7, 0x04], space: [7, 0x80],
  0: [2, 0x01], 1: [2, 0x02], 2: [2, 0x04], 3: [2, 0x08], 4: [2, 0x10], 5: [2, 0x20], 6: [2, 0x40], 7: [2, 0x80],
  8: [3, 0x01], 9: [3, 0x02], vk: [0, 0x04], left: [0, 0x10], up: [0, 0x20], right: [0, 0x40], down: [0, 0x80] };
const plan = {};
for (const it of (PLAN || '').split(/\s+/).filter(Boolean)) {
  const mm = it.match(/^(\d+):(\w+)([+-])$/); if (!mm) throw new Error('план: ' + it);
  (plan[+mm[1]] = plan[+mm[1]] || []).push([mm[2], mm[3] === '+']);
}
const N = +NS || 300;
for (let f = 0; f < N; f++) {
  for (const [k, d] of plan[f] || []) { const e = VKEYS[k]; if (d) m.keyboard.matrix[e[0]] |= e[1]; else m.keyboard.matrix[e[0]] &= ~e[1]; }
  m.frame();
}
const PAL = [0x00, 0x00, 0x38, 0x38, 0x07, 0x07, 0xF8, 0xF8, 0xFF, 0xFF, 0x3F, 0x3F, 0xC7, 0xC7, 0xC0, 0xC0];
const rgb = (c) => [(c & 7) * 255 / 7 | 0, ((c >> 3) & 7) * 255 / 7 | 0, ((c >> 6) & 3) * 255 / 3 | 0];
const W = 256, H = 256, img = Buffer.alloc(W * H * 3);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const a = ((x >> 3) << 8) | (255 - y), b = 7 - (x & 7);
  const bit = (p) => (m.rd(p + a) >> b) & 1;
  const idx = bit(0x8000) << 3 | bit(0xA000) << 2 | bit(0xC000) << 1 | bit(0xE000);
  img.set(rgb(PAL[idx]), (y * W + x) * 3);
}
const out = OUT || 'build/vecshot.png';
fs.writeFileSync(out + '.ppm', Buffer.concat([Buffer.from(`P6 ${W} ${H} 255\n`), img]));
execSync(`sips -s format png "${out}.ppm" --out "${out}" >/dev/null && rm "${out}.ppm"`);
console.log(`кадров ${N}, PC ${m.cpu.pc.toString(16)}, FRAMES ${m.rd(0x5c78) | m.rd(0x5c79) << 8}, уровень ${m.rd(0x5df0)}, жизни ${m.rd(0x5df1)}, x,y ${m.rd(0x5d01)},${m.rd(0x5d02)} -> ${out}`);
