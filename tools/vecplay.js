#!/usr/bin/env node
// Случайная игра на Векторе без окна (vector06js): старт «5», каждые 25 кадров случайные стрелки/пробел,
// жизни подкачиваются; снимки экрана в заданных кадрах (PNG, палитра игры).
//   node tools/vecplay.js rom/jetpac.r0m <seed> <выход-префикс> <кадр> [<кадр> ...]
'use strict';
const fs = require('fs'), { execSync } = require('child_process');
const E = require('./vec_emu');
const [ROM, SEED, OUT, ...CAPS] = process.argv.slice(2);
const caps = CAPS.map(Number), last = Math.max(...caps);
const m = E.mk(ROM);
const K = { left: [0, 0x10], right: [0, 0x40], up: [0, 0x20], space: [7, 0x80], five: [2, 0x20] };
let s = +SEED || 1;
const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
const set = (k, d) => { const e = K[k]; if (d) m.keyboard.matrix[e[0]] |= e[1]; else m.keyboard.matrix[e[0]] &= ~e[1]; };
let PAL = [0, 0, 0x38, 0x38, 7, 7, 0xF8, 0xF8, 0xFF, 0xFF, 0x3F, 0x3F, 0xC7, 0xC7, 0xC0, 0xC0];
try {
  const sm = fs.readFileSync(require('path').join(__dirname, '../build/vec/jetpac.sym'), 'latin1').match(/^pal_ptr:\s+EQU\s+0x([0-9A-F]+)/im);
  if (sm) { const pp = parseInt(sm[1], 16), pa = m.rd(pp) | m.rd(pp + 1) << 8; PAL = Array.from({ length: 16 }, (_, i) => m.rd(pa + i)); }
} catch (e) { /* без палитры из образа */ }
const rgb = (c) => [(c & 7) * 255 / 7 | 0, ((c >> 3) & 7) * 255 / 7 | 0, ((c >> 6) & 3) * 255 / 3 | 0];
for (let f = 0; f <= last; f++) {
  if (f === 100) set('five', 1); if (f === 110) set('five', 0);
  if (f > 300 && f % 25 === 0) for (const k of ['left', 'right', 'up', 'space']) set(k, rnd() < 0.4);
  if (m.rd(0x5df1) < 2) m.wr(0x5df1, 4);
  m.frame();
  if (caps.includes(f)) {
    const img = Buffer.alloc(256 * 256 * 3);
    for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) {
      const a = ((x >> 3) << 8) | (255 - y), b = 7 - (x & 7), bit = (p) => (m.rd(p + a) >> b) & 1;
      img.set(rgb(PAL[bit(0x8000) << 3 | bit(0xA000) << 2 | bit(0xC000) << 1 | bit(0xE000)]), (y * 256 + x) * 3);
    }
    const p = `${OUT}${f}`;
    fs.writeFileSync(p + '.ppm', Buffer.concat([Buffer.from('P6 256 256 255\n'), img]));
    execSync(`sips -s format png "${p}.ppm" --out "${p}.png" >/dev/null && rm "${p}.ppm"`);
  }
}
console.log('уровень', m.rd(0x5df0), 'счёт', [0, 1, 2].map((i) => m.rd(0x5cf4 + i).toString(16).padStart(2, '0')).join(''));
