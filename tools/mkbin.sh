#!/bin/sh
# Сборка build/jetpac.bin (0x5CCB..) из upstream/jetpac.skool.
# Блоки i$ (пропуск, «Old unused routines») skool2bin выбрасывает и сдвигает всё после них —
# заменяем их на defs нужной длины. -s: шрифт картриджа (ld de,$3a00 = ПЗУ картриджа) → копия в system_font.
set -e
cd "$(dirname "$0")/.."
mkdir -p build
python3 - <<'P'
import re
s=open('upstream/jetpac.skool').read().split('\n')
addr=lambda l:int(re.match(r'^.\$([0-9a-f]{4})',l).group(1),16)
out=[]
for i,l in enumerate(s):
    if re.match(r'^i\$[0-9a-f]{4}\s*$',l):
        nxt=next((addr(x) for x in s[i+1:] if re.match(r"^[a-z ]\$[0-9a-f]{4}",x)),None)
        if nxt is None: out.append(l); continue
        l=f's${addr(l):04x} defs ${nxt-addr(l):02x}'
    out.append(l)
open('build/jetpac_fixed.skool','w').write('\n'.join(out))
P
.venv/bin/skool2bin.py -w -s build/jetpac_fixed.skool build/jetpac.bin
.venv/bin/skool2asm.py -H -crs build/jetpac_fixed.skool > build/jetpac_z80.asm 2>/dev/null
