// Ядро JS-модели Jetpac (docs/LOGIC_PLAN.md, этап 1).
//
// Память — 64 КБ в раскладке ZX (ПЗУ 0x0000..0x3FFF только читается: генератор случайных чисел берёт байты
// 0x0000..0x00FF, ld a,(0x0244)); экран 0x4000..0x57FF и атрибуты моделируются — лазер читает экран.
// Адреса обработчика прерывания (owned: FRAMES) читаются из очередей эталона по порядку; кончилась — последнее
// значение. Порты (`in a,($fe)`) — из очереди `inq` или функции `inFn`; `ld a,r` — из `rq`.
//
// Регистры: модель местами (вывод спрайтов, `exx`) повторяет код буквально — общий регистровый файл `r`
// (a, b, c, d, e, h, l) и теневой `r_`; `exx()` меняет b..l, `exaf()` — a. Флаги — локально в коде.
'use strict';
const { SYM: S } = require('../../tools/sym');

class Mem {
  constructor(ram) {
    this.ram = ram;                    // Uint8Array(0x10000), владеет вызывающий
    this.owned = null;                 // Set адресов прерывания
    this.q = new Map();                // адрес -> [значения]
    this.inq = [];                     // [порт, байт] по порядку
    this.inFn = null;                  // (порт) -> байт, если очереди нет
    this.rq = [];                      // ld a,r
    this.rFn = null;
    this.snd = [];                     // [имя, a, b, c, d, e, h, l]
    this.writes = null;                // Set записанных адресов (для сверки)
    this.r = { a: 0, b: 0, c: 0, d: 0, e: 0, h: 0, l: 0 };
    this.r_ = { a: 0, b: 0, c: 0, d: 0, e: 0, h: 0, l: 0 };
  }
  rd(a) {
    a &= 0xffff;
    if (this.owned && this.owned.has(a)) {
      const q = this.q.get(a);
      if (q && q.length) { const v = q.length > 1 ? q.shift() : q[0]; this.ram[a] = v; return v; }
    }
    return this.ram[a];
  }
  wr(a, v) { a &= 0xffff; if (a < 0x4000) return; this.ram[a] = v & 0xff; if (this.writes) this.writes.add(a); }
  rd16(a) { return this.rd(a) | this.rd(a + 1) << 8; }
  wr16(a, v) { this.wr(a, v); this.wr(a + 1, v >> 8); }
  inp(port) {
    if (this.inFn) return this.inFn(port);
    if (!this.inq.length) throw Object.assign(new Error('модель: нет значения порта ' + port.toString(16)), { noInput: true });
    const [p, v] = this.inq.shift();
    if (p !== port) throw new Error(`модель: порт ${port.toString(16)}, в эталоне ${p.toString(16)}`);
    return v;
  }
  ldar() {
    if (this.rFn) return this.rFn();
    if (!this.rq.length) throw new Error('модель: нет значения ld a,r');
    return this.rq.shift();
  }
  sound(name) { const r = this.r; this.snd.push([name, r.a, r.b, r.c, r.d, r.e, r.h, r.l]); }
  exx() { const r = this.r, s = this.r_; for (const k of 'bcdehl') { const t = r[k]; r[k] = s[k]; s[k] = t; } }
  exaf() { const t = this.r.a; this.r.a = this.r_.a; this.r_.a = t; }
  get hl() { return this.r.h << 8 | this.r.l; }
  set hl(v) { this.r.h = (v >> 8) & 0xff; this.r.l = v & 0xff; }
  get de() { return this.r.d << 8 | this.r.e; }
  set de(v) { this.r.d = (v >> 8) & 0xff; this.r.e = v & 0xff; }
  get bc() { return this.r.b << 8 | this.r.c; }
  set bc(v) { this.r.b = (v >> 8) & 0xff; this.r.c = v & 0xff; }
}

// исключение: игра ушла в меню (конец игры) — шаг не моделируется дальше
class GameOver extends Error { constructor() { super('конец игры'); this.gameOver = true; } }

const neg = (a) => (-a) & 0xff;
const rlc = (a) => ((a << 1) | (a >> 7)) & 0xff;
const rrc = (a) => ((a >> 1) | (a << 7)) & 0xff;

// add/adc + daa (Z80, N = 0): -> [результат, перенос]
function addDaa(a, v, cin) {
  const sum = a + v + (cin ? 1 : 0);
  const h = ((a & 0x0f) + (v & 0x0f) + (cin ? 1 : 0)) > 0x0f;
  let r = sum & 0xff, c = sum > 0xff;
  let corr = 0;
  if (h || (r & 0x0f) > 9) corr |= 0x06;
  if (c || r > 0x99) { corr |= 0x60; c = true; }
  r = (r + corr) & 0xff;
  return [r, c];
}

module.exports = { S, Mem, GameOver, neg, rlc, rrc, addDaa };
