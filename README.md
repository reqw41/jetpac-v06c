# Jetpac для Вектора-06Ц

Порт JETPAC (Ultimate Play the Game, 1983, ZX Spectrum 16K) на ванильный Вектор-06Ц.
Основа — дизассемблер картриджной версии Майкла Кука
([mrcook/jetpac-disassembly](https://github.com/mrcook/jetpac-disassembly)), подключён
подмодулем в `upstream/`.

Статус: разведка, порта ещё нет. План и факты — `docs/NEXT-SESSION.md`.

## Сборка исходника Z80

    git submodule update --init
    python3 -m venv .venv && .venv/bin/pip install skoolkit
    .venv/bin/skool2asm.py -H -crs upstream/jetpac.skool > build/jetpac_z80.asm
    .venv/bin/skool2bin.py upstream/jetpac.skool build/jetpac.bin

## Права

JETPAC © 1983 Ultimate Play the Game / Ashby Computers & Graphics Ltd.
Дизассемблер и комментарии © 2020 Michael R. Cook.
