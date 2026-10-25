// zx48.js — минимальная модель ZX Spectrum 48K для эталонных прогонов Jetpac (docs/LOGIC_PLAN.md, этап 0).
//
// Z80 (tools/vendor/Z80.js, MIT; копия из aticatac-v06c), ПЗУ 48K (ref/48.rom из SkoolKit), 48 КБ ОЗУ,
// порт 0xFE: клавиатура (строка — старший байт адреса порта), бит 4 записи — бипер.
// Кадр 69888 тактов; INT держится 32 такта от начала кадра — при DI прерывание теряется (как на ZX).
// Задержки по спорной памяти не моделируются.
//
// Игра — картриджная сборка из skool (build/jetpac.bin с 0x5CCB, tools/mkbin.sh), старт с 0x6000.
'use strict';
const fs = require('fs');
const path = require('path');
const Z80 = require('./vendor/Z80.js');

const ROOT = path.join(__dirname, '..');
const T_FRAME = 69888, INT_LEN = 32;

// клавиши: имя -> [строка (0..7 по битам старшего байта порта), бит]
const ROWS = ['^ZXCV', 'ASDFG', 'QWERT', '12345', '09876', 'POIUY', 'nLKJH', ' sMNB'];
const KEYS = {};
ROWS.forEach((r, i) => [...r].forEach((ch, b) => { KEYS[ch] = [i, b]; }));
KEYS.SHIFT = KEYS['^']; KEYS.ENTER = KEYS.n; KEYS.SPACE = KEYS[' ']; KEYS.SYM = KEYS.s;

class ZX48 {
  constructor() {
    this.mem = new Uint8Array(0x10000);
    this.mem.set(fs.readFileSync(path.join(ROOT, 'ref/48.rom')));
    this.kb = new Uint8Array(8).fill(0x1f);
    this.t = 0; this.total = 0; this.frames = 0;
    this.intLine = true;                       // INT активен (начало кадра)
    this.inIsr = false; this.isrRet = -1; this.isrSp = -1;
    this.onRead = null; this.onWrite = null; this.onIn = null; this.onOut = null;
    this.beeper = 0;
    const self = this;
    this.cpu = new Z80({
      mem_read: (a) => { const v = self.mem[a]; if (self.onRead) self.onRead(a, v, self.inIsr); return v; },
      mem_write: (a, v) => {
        if (a < 0x4000) return;
        if (self.onWrite) self.onWrite(a, v, self.inIsr);
        self.mem[a] = v & 0xff;
      },
      io_read: (p) => { const v = self._in(p & 0xffff); if (self.onIn) self.onIn(p & 0xffff, v, self.inIsr); return v; },
      io_write: (p, v) => { if (self.onOut) self.onOut(p & 0xffff, v & 0xff); if ((p & 1) === 0) self.beeper = (v >> 4) & 1; },
    });
  }

  loadGame(file) {
    const d = fs.readFileSync(file || path.join(ROOT, 'build/jetpac.bin'));
    this.mem.set(d, 0x5ccb);
    this.cpu.set_imode(1);
    this.cpu.set_sp(0x5cf0);
    this.cpu.set_pc(0x6000);
    return this;
  }

  _in(p) {
    if (p & 1) return 0xff;
    const hi = p >> 8;
    let v = 0x1f;
    for (let r = 0; r < 8; r++) if (!(hi & (1 << r))) v &= this.kb[r];
    return v | 0xe0;
  }

  keyDown(n) { const k = KEYS[n]; if (!k) throw new Error('клавиша ' + n); this.kb[k[0]] &= ~(1 << k[1]); }
  keysOnly(names) { this.kb.fill(0x1f); for (const n of names) this.keyDown(n); }

  get pc() { return this.cpu.get_pc(); }
  peek(a) { return this.mem[a & 0xffff]; }
  poke(a, v) { this.mem[a & 0xffff] = v & 0xff; }

  // готово ли прерывание на этой границе команды
  intReady() { return this.t < INT_LEN && this.cpu.get_iff1(); }

  step() {
    const cpu = this.cpu;
    if (this.intLine && this.intReady()) {
      this.intLine = false;
      this.isrSp = cpu.get_sp(); this.isrRet = cpu.get_pc(); this.inIsr = true;
      cpu.interrupt(false, 0xff);
      this._tick(13); return 13;
    }
    const c = cpu.run_instruction();
    if (this.inIsr && cpu.get_pc() === this.isrRet && cpu.get_sp() === this.isrSp) this.inIsr = false;
    this._tick(c);
    return c;
  }

  _tick(c) {
    this.t += c; this.total += c;
    if (this.t >= INT_LEN) this.intLine = false;
    if (this.t >= T_FRAME) { this.t -= T_FRAME; this.frames++; this.intLine = true; }
  }

  runFrames(n) { const f = this.frames + n; while (this.frames < f) this.step(); }
  runUntilPc(pc, maxT) {
    const lim = this.total + (maxT || T_FRAME * 500);
    while (this.total < lim) { if (this.pc === pc && !this.inIsr) return true; this.step(); }
    return false;
  }

  // экран ZX -> PGM/PPM с атрибутами (для глаз)
  ppm() {
    const W = 256, H = 192, out = Buffer.alloc(W * H * 3);
    const pal = [[0, 0, 0], [0, 0, 205], [205, 0, 0], [205, 0, 205], [0, 205, 0], [0, 205, 205], [205, 205, 0], [205, 205, 205]];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const a = 0x4000 | ((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3);
      const at = this.mem[0x5800 + (y >> 3) * 32 + (x >> 3)];
      const on = (this.mem[a] >> (7 - (x & 7))) & 1;
      let c = pal[on ? at & 7 : (at >> 3) & 7];
      if (at & 0x40) c = c.map((v) => (v ? 255 : 0));
      out.set(c, (y * W + x) * 3);
    }
    return Buffer.concat([Buffer.from(`P6 ${W} ${H} 255\n`), out]);
  }
}

ZX48.T_FRAME = T_FRAME;
ZX48.KEYS = KEYS;
ZX48.ROOT = ROOT;
module.exports = ZX48;
