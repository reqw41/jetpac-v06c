#!/bin/sh
# Эталон ZX без окна: снимок картриджной сборки и PNG экрана через N тактов.
#   tools/zxshot.sh menu 70000000      — меню
#   tools/zxshot.sh game 150000000     — игра (старт с NewGame из состояния меню)
set -e
cd "$(dirname "$0")/.."
V=.venv/bin
[ -f build/jetpac.bin ] || tools/mkbin.sh
$V/bin2sna.py -o 0x5CCB -s 0x6000 build/jetpac.bin build/cart0.z80
case "$1" in
  menu) $V/trace.py -M "${2:-70000000}" build/cart0.z80 build/zx_menu.png ;;
  game) $V/trace.py -M 70000000 build/cart0.z80 build/menu.z80 >/dev/null
        $V/trace.py -s 0x62fe -M "${2:-150000000}" build/menu.z80 build/zx_game.png ;;
  *) echo "usage: $0 menu|game [tstates]"; exit 1 ;;
esac
