; Вывод Jetpac на Векторе (docs/LOGIC_PLAN.md, этап 2/3). Синтаксис Z80, только команды i8080 (--i8080).
;
; Экран: плоскости 0x80xx, 0xA0xx, 0xC0xx — цвет INK (сочетание — ink_planes), 0xE0xx — «чёрная» плоскость
; (предметы цвета 0; палитра её не показывает). Адрес точки ZX (x, y): H = 0x80 + x/8, L = 223 - y
; (строка выше = L + 1). Объединение четырёх плоскостей = экран ZX байт в байт (лазер читает экран;
; сверка с моделью — по объединению).
;
; Спрайт вывода (vs_*, буферы): [смещение X, ширина, высота], затем столбцы снизу вверх, высота столбца
; дополнена до чётной (h2). Стирание — AND NOT во всех 4 плоскостях; рисование — OR в плоскостях цвета,
; откладывается до ColourizeSprite (цвет известен только там). Блиттер читает данные через POP (SP = данные,
; прерывания запрещены на одну плоскость).

PL_C0		equ	0x80

; --- Coord2Scr: H = Y, L = X -> HL = адрес в плоскости 0 -------------------------------------------
coord2scr:
		ld	a,l
		rrca
		rrca
		rrca
		and	0x1F
		or	PL_C0
		ld	l,a
		ld	a,h
		cpl
		sub	32
		ld	h,l
		ld	l,a
		ret

; --- блиттер -------------------------------------------------------------------------------------------
bl_scr:		dw	0		; адрес кадра в плоскости 0
bl_dat:		dw	0		; данные (столбцы подряд)
bl_w:		db	0		; столбцов
bl_h2:		db	0		; байт на столбец (чётное)
bl_sp:		dw	0

; кадр bl_* в одной плоскости: A = база плоскости (0x80/0xA0/0xC0/0xE0); вход блока — bl_jmp
blit_plane:
		ld	b,a
		ld	hl,(bl_scr)
		ld	a,h
		and	0x1F
		or	b
		ld	h,a
		ld	c,l			; C — строка начала столбца
		ld	a,(bl_w)
		ld	b,a			; B — столбцов
		di
		ex	de,hl
		ld	hl,0
		add	hl,sp
		ld	(bl_sp),hl
		ld	hl,(bl_dat)
		ld	sp,hl
		ex	de,hl
bl_jmp:		jp	0			; -> вход в развёрнутый блок (патчится)
bl_next:					; конец столбца: следующий (31 -> 0 в той же плоскости)
		ld	l,c
		inc	h
		ld	a,h
		and	0x1F
		jp	nz,bl_n1
		ld	a,h
		sub	0x20
		ld	h,a
bl_n1:		dec	b
bl_jmp2:	jp	nz,0			; тот же вход
		ld	hl,(bl_sp)
		ld	sp,hl
		ei
		ret

; развёрнутые блоки по 2 строки (12 пар — высота до 24)
		MACRO	OPOR
		pop	de
		ld	a,(hl)
		or	e
		ld	(hl),a
		inc	l
		ld	a,(hl)
		or	d
		ld	(hl),a
		inc	l
		ENDM
		MACRO	OPAN
		pop	de
		ld	a,e
		cpl
		and	(hl)
		ld	(hl),a
		inc	l
		ld	a,d
		cpl
		and	(hl)
		ld	(hl),a
		inc	l
		ENDM
op_or:
		REPT	12
		OPOR
		ENDR
op_or_end:	jp	bl_next
op_an:
		REPT	12
		OPAN
		ENDR
op_an_end:	jp	bl_next

; вход блока: A = h2, HL = конец блока, DE = размер пары -> bl_jmp, bl_jmp2
bl_setup:
		rrca
		and	0x7F
		jp	z,bl_s1
bl_s0:		push	af
		ld	a,l
		sub	e
		ld	l,a
		ld	a,h
		sbc	a,0
		ld	h,a
		pop	af
		dec	a
		jp	nz,bl_s0
bl_s1:		ld	(bl_jmp+1),hl
		ld	(bl_jmp2+1),hl
		ret

; кадр bl_*: стирание во всех 4 плоскостях
blit_erase:
		ld	a,(bl_h2)
		or	a
		ret	z
		ld	hl,op_an_end
		ld	de,11
		call	bl_setup
		ld	a,0x80
		call	blit_plane
		ld	a,0xA0
		call	blit_plane
		ld	a,0xC0
		call	blit_plane
		ld	a,0xE0
		jp	blit_plane

; кадр bl_*: OR в плоскостях цвета A (биты 0..2 — INK ZX)
blit_draw:
		and	7
		ld	c,a
		ld	a,(bl_h2)
		or	a
		ret	z
		push	bc
		ld	hl,op_or_end
		ld	de,9
		call	bl_setup
		pop	bc
		ld	b,0
		ld	hl,ink_planes
		add	hl,bc
		ld	a,(hl)			; биты плоскостей: 1 = 0x80, 2 = 0xA0, 4 = 0xC0, 8 = 0xE0
		rrca
		jp	nc,bd_p1
		push	af
		ld	a,0x80
		call	blit_plane
		pop	af
bd_p1:		rrca
		jp	nc,bd_p2
		push	af
		ld	a,0xA0
		call	blit_plane
		pop	af
bd_p2:		rrca
		jp	nc,bd_p3
		push	af
		ld	a,0xC0
		call	blit_plane
		pop	af
bd_p3:		rrca
		ret	nc
		ld	a,0xE0
		jp	blit_plane

; INK ZX -> плоскости: белый, красный, зелёный — по одной (частые цвета), чёрный — плоскость 0xE0
ink_planes:	db	8, 7, 2, 3, 4, 6, 5, 1

; --- кадры актёра --------------------------------------------------------------------------------------
of_scr:		dw	0		; старый кадр (по actor) — стирается
of_dat:		dw	0
of_w:		db	0
of_h2:		db	0
nf_scr:		dw	0		; новый кадр (по объекту) — рисуется в ColourizeSprite
nf_dat:		dw	0
nf_w:		db	0
nf_h2:		db	0
nf_pend:	db	0		; 1 — новый кадр ждёт цвета

; DE -> спрайт, HL = Y,X: X += смещение, кадр в bl_*; выход: A = высота, B = ширина, DE -> данные
frame_of:
		ld	a,(de)
		inc	de
		add	a,l
		ld	l,a
		call	coord2scr
		ld	(bl_scr),hl
		ld	a,(de)
		inc	de
		ld	(bl_w),a
		ld	b,a
		ld	a,(de)
		inc	de
		ld	c,a
		inc	a
		and	0xFE
		ld	(bl_h2),a
		ex	de,hl
		ld	(bl_dat),hl
		ex	de,hl
		ld	a,c
		ret

; ActorGetSpriteAddress: A = направление, C = X & 6 -> DE = спрайт вывода
actor_get_sprite:
		ld	b,a
		and	0x40
		jp	z,ags1
		ld	a,c
		or	8
		ld	c,a
ags1:		ld	a,b
		dec	a
		add	a,a
		add	a,a
		add	a,a
		add	a,a
		or	c
		ld	e,a
		ld	d,0
		ld	hl,vs_jetman_sprite_table
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ret

; старый кадр по actor (ActorFindPosDir + GetActorLocation + GetSpritePosition) -> of_*, actor+5
old_frame_actor:
		ld	a,(actor)
		and	6
		ld	c,a
		ld	a,(actor+2)
		call	actor_get_sprite
; старый кадр спрайта DE в позиции actor (GetActorLocation + GetSpritePosition)
old_frame_de:
		ld	hl,(actor)
old_frame_hl:					; HL = Y,X (GetSpritePosition)
		call	frame_of
		ld	(actor+5),a
save_of:	ld	hl,(bl_scr)
		ld	(of_scr),hl
		ld	hl,(bl_dat)
		ld	(of_dat),hl
		ld	hl,(bl_w)		; bl_w, bl_h2 подряд
		ld	(of_w),hl
		ret

; новый кадр объекта ws (ActorMoveSprite + ActorUpdate) -> nf_*, actor_coords, actor+3/4/6
new_frame_obj:
		ld	a,(ws+1)
		and	6
		ld	c,a
		ld	a,(ws)
		call	actor_get_sprite
new_frame_de:					; ActorUpdate со спрайтом DE
		ld	hl,(ws+1)		; L = X, H = Y
		ld	a,(de)
		add	a,l
		ld	(actor_coords),a
		ld	a,h
		ld	(actor_coords+1),a
		call	frame_of
		ld	(actor+6),a
		ld	(actor+3),a
		ld	a,b
		ld	(actor+4),a
		ld	hl,(bl_scr)
		ld	(nf_scr),hl
		ld	hl,(bl_dat)
		ld	(nf_dat),hl
		ld	hl,(bl_w)
		ld	(nf_w),hl
		ld	a,1
		ld	(nf_pend),a
		ret

load_of:	ld	hl,(of_scr)
		ld	(bl_scr),hl
		ld	hl,(of_dat)
		ld	(bl_dat),hl
		ld	hl,(of_w)
		ld	(bl_w),hl
		ret
load_nf:	ld	hl,(nf_scr)
		ld	(bl_scr),hl
		ld	hl,(nf_dat)
		ld	(bl_dat),hl
		ld	hl,(nf_w)
		ld	(bl_w),hl
		ret

; конец любой перерисовки (ActorUpdateSize): actor+5 = actor+6 = 0
actor_size0:
		xor	a
		ld	(actor+5),a
		ld	(actor+6),a
		ret

; UpdateAndEraseActor: стереть кадр по actor; новый кадр объекта — ждёт цвета
update_and_erase_actor:
		call	new_frame_obj
		call	old_frame_actor
		call	load_of
		call	blit_erase
		jp	actor_size0

; ActorUpdatePosition: DE = спрайт; старый кадр — тот же спрайт в позиции actor
actor_update_position:
		push	de
		call	old_frame_de
		pop	de
		call	new_frame_de
		call	load_of
		call	blit_erase
		jp	actor_size0

; ActorEraseAnimSprite: DE = спрайт; только новый кадр (без стирания)
actor_erase_anim_sprite:
		call	new_frame_de
		jp	actor_size0

; ActorDestroy: DE = спрайт в позиции actor — стереть
actor_destroy:
		call	old_frame_de
; ActorEraseDestroyed: стереть старый кадр (of_*)
actor_erase_destroyed:
		xor	a
		ld	(actor+3),a
		call	load_of
		call	blit_erase
		jp	actor_size0
; ActorFindDestroy: спрайт по actor — стереть
actor_find_destroy:
		call	old_frame_actor
		jp	actor_erase_destroyed

; ColourizeSprite: новый кадр — в плоскости цвета ws+3
colourize_sprite:
		ld	a,(nf_pend)
		or	a
		ret	z
		xor	a
		ld	(nf_pend),a
		call	load_nf
		ld	a,(ws+3)
		jp	blit_draw

; --- текст и тайлы: байты пишутся целиком (ld (hl),a ZX) в плоскости по цвету --------------------------
; draw_cell: HL = адрес верхней строки (плоскость 0), DE -> 8 байт (сверху вниз), A = цвет; выход: HL —
; следующее знакоместо по X (H + 1), DE -> за символом
draw_cell:
		push	bc
		and	7
		push	hl
		ld	c,a
		ld	b,0
		ld	hl,ink_planes
		add	hl,bc
		ld	b,(hl)			; маска плоскостей
		pop	hl
		push	hl
		ld	c,8
dc_row:		ld	a,(de)
		inc	de
		push	hl
		push	bc
		ld	c,a
		ld	a,b
		rrca
		ld	b,a
		ld	a,c
		jp	c,dc0
		xor	a
dc0:		ld	(hl),a			; 0x80
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,b
		rrca
		ld	b,a
		ld	a,c
		jp	c,dc1
		xor	a
dc1:		ld	(hl),a			; 0xA0
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,b
		rrca
		ld	b,a
		ld	a,c
		jp	c,dc2
		xor	a
dc2:		ld	(hl),a			; 0xC0
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,b
		rrca
		ld	a,c
		jp	c,dc3
		xor	a
dc3:		ld	(hl),a			; 0xE0
		pop	bc
		pop	hl
		dec	l			; строка ниже
		dec	c
		jp	nz,dc_row
		pop	hl
		inc	h			; следующее знакоместо (ZX: inc l)
		pop	bc
		ret

; scr_any: HL = адрес (плоскость 0) -> A = объединение 4 плоскостей (флаг Z — пусто)
scr_any:
		push	hl
		ld	a,(hl)
		ld	b,a
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,(hl)
		or	b
		ld	b,a
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,(hl)
		or	b
		ld	b,a
		ld	a,h
		add	a,0x20
		ld	h,a
		ld	a,(hl)
		or	b
		pop	hl
		ret
