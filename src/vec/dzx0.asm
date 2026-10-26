; Распаковщик ZX0 (classic): DeZX/ZX0/8080/dzx0.asm, Ivan Gorodetsky (ivagor), v4 2021-02-23, ветка FORWARD,
; «Based on ZX0 z80 decoder by Einar Saukas» (ZX0 — BSD-3, tools/zx0/LICENSE). Перевод в синтаксис Z80
; (подмножество i8080) — из alien8-v06c (tools/a8_pack.py). Вход: HL = поток, BC = приёмник. Портит всё.
dzx0:			ld		de, 0xFFFF
				push	de
				inc		de
				ld		a, 0x80
dzx0_lit:		call	dzx0_elias
				call	dzx0_ldir
				add		a, a
				jp		c, dzx0_new
				call	dzx0_elias
dzx0_copy:		ex		(sp), hl
				push	hl
				add		hl, bc
				call	dzx0_ldir
				pop		hl
				ex		(sp), hl
				add		a, a
				jp		nc, dzx0_lit
dzx0_new:		call	dzx0_elias
				ld		d, a
				pop		af
				xor		a
				sub		e
				ret		z
				ld		e, d
				ld		d, a
				ld		a, e
				push	bc
				ld		b, a
				ld		a, d
				rra
				ld		d, a
				ld		a, (hl)
				rra
				ld		e, a
				ld		a, b
				pop		bc
				inc		hl
				push	de
				ld		de, 1
				call	nc, dzx0_back
				inc		de
				jp		dzx0_copy
dzx0_elias:		inc		e
dzx0_eloop:		add		a, a
				jp		nz, dzx0_eskip
				ld		a, (hl)
				inc		hl
				rla
dzx0_eskip:		ret		c
dzx0_back:		ex		de, hl
				add		hl, hl
				ex		de, hl
				add		a, a
				jp		nc, dzx0_eloop
				inc		e
				jp		dzx0_eloop
dzx0_ldir:		push	af
dzx0_ldl:		ld		a, (hl)
				ld		(bc), a
				inc		hl
				inc		bc
				dec		de
				ld		a, d
				or		e
				jp		nz, dzx0_ldl
				pop		af
				ret
dzx0_end:
