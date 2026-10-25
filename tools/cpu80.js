// Запуск подпрограмм i8080 (ядро vector06js, такты Вектора) на плоской памяти 64 КБ — для сверки логики.
'use strict';
const fs = require('fs'), vm = require('vm'), path = require('path');
const base = process.env.V06JS || path.join(require('os').homedir(), 'projects/vector06js');
const g = { console: { log() {}, debug() {}, warn() {}, error() {}, info() {} } }; g.window = g;
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js'])
  vm.runInContext(fs.readFileSync(path.join(base, f), 'utf8'), ctx, { filename: f });

class CPU80 {
  constructor() {
    this.mem = new Uint8Array(0x10000);
    this.onWrite = null;
    const self = this;
    this.memory = {
      read: (a) => self.mem[a & 0xffff],
      write: (a, v) => { a &= 0xffff; if (self.onWrite) self.onWrite(a, v); self.mem[a] = v & 0xff; },
    };
    this.io = { input: () => 0xff, output: () => {}, commit: () => {} };
    this.cpu = new ctx.I8080(this.memory, this.io);
  }
  // регистры: { a, b, c, d, e, h, l } ; вызов addr с возвратом на SENTINEL; -> такты
  call(addr, regs, maxT) {
    const c = this.cpu, R = c.regs, SENT = 0xfffe;
    regs = regs || {};
    const idx = { b: 0, c: 1, d: 2, e: 3, h: 4, l: 5, a: 7 };
    for (const k of Object.keys(idx)) if (regs[k] !== undefined) R[idx[k]] = regs[k] & 0xff;
    c.sp = 0xfff0;
    this.mem[0xffef] = SENT >> 8; this.mem[0xffee] = SENT & 0xff; c.sp = 0xffee;
    c.pc = addr;
    let t = 0; const lim = maxT || 5e7;
    while (c.pc !== SENT) { c.instruction(); t += c.vcycles; if (t > lim) throw new Error('i8080: не вернулась ' + addr.toString(16) + ' pc ' + c.pc.toString(16)); }
    return t;
  }
  reg(k) { const idx = { b: 0, c: 1, d: 2, e: 3, h: 4, l: 5, a: 7 }; return this.cpu.regs[idx[k]]; }
}
module.exports = CPU80;
