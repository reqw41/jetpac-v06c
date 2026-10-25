; Загрузка, прерывание, игра (заготовка: этап 3 — палитра, клавиатура, джойстик «П», звук, меню).
boot:
		call	clear_screen
		ld	a,1
		ld	(game_options+0),a	; заглушка
		ei
		jp	$
isr:
		push	af
		push	hl
		ld	a,(frame_ticked)	; во вложенном проходе кадр не считается (ZX: DI)
		or	a
		jp	nz,isr1
		ld	hl,(FRAMES)
		inc	hl
		ld	(FRAMES),hl
isr1:		pop	hl
		pop	af
		ei
		ret
