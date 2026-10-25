#!/bin/sh
# Сборка i8080: данные из картриджной сборки + src/vec -> build/vec/jetpac.bin, .sym
set -e
cd "$(dirname "$0")/.."
[ -f build/z80.sym ] || tools/mkbin.sh
python3 tools/mkvecdata.py >/dev/null
mkdir -p build/vec
(cd src/vec && ../../tools/sjasmplus --nologo --i8080 --sym=../../build/vec/jetpac.sym game.asm) | grep -v "^Pass\|^Errors: 0" || true
