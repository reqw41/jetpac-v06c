#!/bin/sh
# Сборка i8080: данные из картриджной сборки + src/vec -> build/vec/jetpac.bin, .sym
set -e
cd "$(dirname "$0")/.."
[ -f build/z80.sym ] || tools/mkbin.sh
python3 tools/mkvecdata.py >/dev/null
mkdir -p build/vec
(cd src/vec && ../../tools/sjasmplus --nologo --i8080 --sym=../../build/vec/jetpac.sym game.asm) | grep -v "^Pass\|^Errors: 0" || true
mkdir -p rom
cp build/vec/jetpac.bin rom/jetpac.r0m		# эмуляторы: образ памяти с 0x0000
cp build/vec/jetpac.bin rom/jetpac.c00		# MiSTer: .C00 грузится с 0x0000
