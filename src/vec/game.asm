; Jetpac для Вектора-06Ц: сборка (docs/LOGIC_PLAN.md). Синтаксис Z80, только команды i8080.
;   python3 tools/mkvecdata.py && (cd src/vec && ../../tools/sjasmplus --i8080 game.asm)
; Раскладка: 0x0000 загрузчик и RST 38h; 0x0100 код; стек вниз от 0x5B00; 0x5B00 r_buf (ld a,r);
; 0x5C78 FRAMES; 0x5CCB..0x5FFF переменные и буферы спрайтов как в ZX; 0x6000 данные; 0x8000 экран.
		DEVICE	NOSLOT64K
		INCLUDE	"gen/vars.asm"
r_buf		equ	0x5B00
STACK_TOP	equ	0x5B00

		ORG	0x0000
		di
		ld	sp,STACK_TOP
		jp	boot
		ORG	0x0038
		jp	isr

		ORG	0x0100
zx_kb:		db	0x1F,0x1F,0x1F,0x1F,0x1F,0x1F,0x1F,0x1F	; ряды ZX (бит = 0 — нажата)
		INCLUDE	"render.asm"
		INCLUDE	"common.asm"
		INCLUDE	"objects.asm"
		INCLUDE	"jetman.asm"
		INCLUDE	"loop.asm"
		INCLUDE	"main.asm"
code_end:
		ASSERT	code_end < STACK_TOP - 0x100

		ORG	0x6000
		INCLUDE	"gen/data.asm"
data_end:
		ASSERT	data_end <= 0x8000

		SAVEBIN	"../../build/vec/jetpac.bin", 0, data_end
