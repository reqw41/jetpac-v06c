#!/usr/bin/env python3
"""Сверка build/jetpac.bin (skool2bin, с 0x5CCB) с образами оригинала: .z80 (через SkoolKit) и .sp."""
import sys
from skoolkit.snapshot import Snapshot

def load_sp(path):
    d = open(path, 'rb').read()
    assert d[:2] == b'SP'
    length = d[2] | d[3] << 8
    start = d[4] | d[5] << 8
    mem = bytearray(65536)
    mem[start:start + length] = d[38:38 + length]
    regs = dict(zip('bc de hl af ix iy bc_ de_ hl_ af_ r_i sp pc'.split(),
                    [d[i] | d[i + 1] << 8 for i in range(6, 32, 2)]))
    return mem, regs

def load(path):
    if path.lower().endswith('.sp'):
        return load_sp(path)
    s = Snapshot.get(path)
    return bytearray(s.ram(-1)) if hasattr(s, 'ram') else bytearray(s), {}

ref = open('build/jetpac.bin', 'rb').read()
base = 0x5CCB
lo, hi = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x6000, int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x7FB3
mem, regs = load(sys.argv[1])
if len(mem) == 49152:
    mem = bytearray(16384) + mem
if regs:
    print('regs', {k: hex(v) for k, v in regs.items()})
diff = [a for a in range(lo, hi) if mem[a] != ref[a - base]]
print(f'{sys.argv[1]}: {hi-lo} Б, различий {len(diff)}')
runs, prev = [], None
for a in diff:
    if prev is not None and a == prev + 1:
        runs[-1][1] = a
    else:
        runs.append([a, a])
    prev = a
for a, b in runs[:60]:
    print(f'  {a:04X}-{b:04X}  ref {ref[a-base:b-base+1].hex()}  orig {mem[a:b+1].hex()}')
