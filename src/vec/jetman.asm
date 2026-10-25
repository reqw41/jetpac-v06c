; Джетмен и лазер на i8080 (по src/model/logic.js: jetmanFly, jetmanWalk, laser*).

; --- PlayerTurnStarts + JetmanFlyThrust ---------------------------------------------------------------
player_turn_starts:
		ld	a,(begin_play_delay_counter)
		or	a
		jp	z,jetman_fly
		dec	a
		ld	(begin_play_delay_counter),a
		jp	nz,score_label_flash
		call	sfx_pickup_item
		ld	a,(current_player_number)
		or	a
		ld	hl,0x0018
		jp	z,pts1
		ld	hl,0x00D8
pts1:		call	score_label_unflash

jetman_fly:
		call	tmp_actor
		call	read_lr
		ld	b,a
		and	8
		jp	z,jf_right
		ld	a,b
		and	0x10
		jp	z,jf_left
		ld	a,(game_timer)
		and	1
		jp	z,jf_horiz
		; JetmanVelCalcX: vx += vmod - 8, не меньше 0
		ld	a,(jetman_velocity_modifier)
		sub	8
		ld	b,a
		ld	a,(ws+5)
		add	a,b
		jp	p,jf_setx
		xor	a
		jp	jf_setx
jf_right:	ld	a,(ws)
		and	0xBF
		ld	(ws),a
		ld	a,(ws+4)
		and	0x40
		jp	nz,jf_flipx
		jp	jf_incx
jf_left:	ld	a,(ws)
		or	0x40
		ld	(ws),a
		ld	a,(ws+4)
		and	0x40
		jp	z,jf_flipx
jf_incx:	ld	a,(jetman_velocity_modifier)
		cpl
		inc	a
		add	a,8
		ld	b,a
		ld	a,(ws+5)
		add	a,b
		cp	0x40
		jp	c,jf_setx
		ld	a,0x40
		jp	jf_setx
jf_flipx:	ld	a,(jetman_velocity_modifier)
		sub	8
		ld	b,a
		ld	a,(ws+5)
		add	a,b
		jp	p,jf_setx
		xor	a
		ld	(ws+5),a
		ld	a,(ws+4)
		xor	0x40
		ld	(ws+4),a
		jp	jf_horiz
jf_setx:	ld	(ws+5),a
jf_horiz:	; X: HL = vx * 8; X:actor+7 += / -= HL
		ld	a,(ws+5)
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,(ws+1)
		ld	d,a
		ld	a,(actor+7)
		ld	e,a
		ld	a,(ws+4)
		and	0x40
		jp	z,jfh_add
		ld	a,e
		sub	l
		ld	l,a
		ld	a,d
		sbc	a,h
		ld	h,a
		jp	jfh_set
jfh_add:	add	hl,de
jfh_set:	ld	a,l
		ld	(actor+7),a
		ld	a,h
		ld	(ws+1),a
		; гравитация: цифры 1–0 (или джойстик без «вверх») — висеть
		ld	a,(game_options)
		and	2
		jp	z,jfg_kb
		call	read_i2
		and	4
		jp	z,jf_vymin
		jp	jf_fall
jfg_kb:		ld	a,0xEF
		call	in_row
		and	0x1F
		cp	0x1F
		jp	nz,jf_vymin
		ld	a,0xF7
		call	in_row
		and	0x1F
		cp	0x1F
		jp	nz,jf_vymin
jf_fall:	call	read_thrust
		and	2
		jp	z,jf_thrust
		ld	a,(ws)			; не газует: вниз
		or	0x80
		ld	(ws),a
		ld	a,(ws+4)
		and	0x80
		jp	nz,jf_incy
		jp	jf_flipy
jf_thrust:	ld	a,(ws)
		and	0x7F
		ld	(ws),a
		ld	a,(ws+4)
		and	0x80
		jp	nz,jf_flipy
jf_incy:	ld	a,(jetman_velocity_modifier)
		cpl
		inc	a
		add	a,8
		ld	b,a
		ld	a,(ws+6)
		add	a,b
		cp	0x3F
		jp	c,jf_sety
		ld	a,0x3F
		jp	jf_sety
jf_flipy:	ld	a,(jetman_velocity_modifier)
		sub	8
		ld	b,a
		ld	a,(ws+6)
		add	a,b
		jp	p,jf_sety
		xor	a
		ld	(ws+6),a
		ld	a,(ws+4)
		xor	0x80
		ld	(ws+4),a
		jp	jf_vert
jf_vymin:	xor	a
jf_sety:	ld	(ws+6),a
jf_vert:	; Y: HL = vy * 8; Y:fly_counter += / -= HL
		ld	a,(ws+6)
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,(ws+2)
		ld	d,a
		ld	a,(jetman_fly_counter)
		ld	e,a
		ld	a,(ws+4)
		and	0x80
		jp	nz,jfv_add
		ld	a,e
		sub	l
		ld	l,a
		ld	a,d
		sbc	a,h
		ld	h,a
		jp	jfv_set
jfv_add:	add	hl,de
jfv_set:	ld	a,l
		ld	(jetman_fly_counter),a
		ld	a,h
		ld	(ws+2),a
		cp	0xC0
		jp	nc,jfv_bottom
		cp	0x2A
		jp	nc,jf_plat
		ld	a,(ws+4)		; потолок: вниз, скорость пополам
		or	0x80
		ld	(ws+4),a
		ld	a,(ws+6)
		and	a
		rra
		jp	z,jf_plat
		ld	(ws+6),a
		jp	jf_plat
jfv_bottom:	ld	a,(ws+4)
		and	0x7F
		ld	(ws+4),a
jf_plat:	call	pcca
		ld	a,e
		and	4
		jp	z,jetman_redraw
		ld	a,e
		and	0x80
		jp	nz,jf_lands
		ld	a,e
		and	0x10
		jp	nz,jf_bump
		ld	a,e
		xor	0x40
		and	0x40
		ld	b,a
		ld	a,(ws+4)
		and	0xBF
		or	b
		ld	(ws+4),a
		jp	jetman_redraw
jf_bump:	ld	a,(ws+4)
		or	0x80
		ld	(ws+4),a
		jp	jetman_redraw
jf_lands:	ld	a,(ws+4)
		and	0x7F
		ld	(ws+4),a
		ld	a,(ws)
		and	0xC0
		or	2
		ld	(ws),a
		xor	a
		ld	(ws+5),a
		ld	(ws+6),a
jetman_redraw:
		call	update_and_erase_actor
		call	colourize_sprite
		call	read_fire
		and	1
		ret	nz
		jp	laser_new_if_free

; --- JetmanWalk ---------------------------------------------------------------------------------------
jetman_walk:
		call	tmp_actor
		call	read_lr
		ld	b,a
		and	8
		jp	z,jw_right
		ld	a,b
		and	0x10
		jp	z,jw_left
		xor	a
		ld	(ws+5),a
		jp	jw0
jw_right:	ld	hl,ws+1
		inc	(hl)
		ld	a,(ws)
		and	0xBF
		ld	(ws),a
		ld	a,(ws+4)
		and	0xBF
		ld	(ws+4),a
		jp	jw_v
jw_left:	ld	hl,ws+1
		dec	(hl)
		ld	a,(ws)
		or	0x40
		ld	(ws),a
		ld	a,(ws+4)
		or	0x40
		ld	(ws+4),a
jw_v:		ld	a,0x20
		ld	(ws+5),a
jw0:		call	read_thrust
		and	2
		jp	z,jw_leave
		call	pcca
		ld	a,e
		and	4
		jp	z,jw_leave
		ld	a,e
		and	8
		jp	z,jetman_redraw
		ld	a,(ws+5)
		or	a
		jp	nz,jetman_redraw
		ld	a,(ws)
		and	0x40
		jp	z,jw1
		ld	hl,ws+1
		dec	(hl)
		jp	jetman_redraw
jw1:		ld	hl,ws+1
		inc	(hl)
		ld	a,0x20
		ld	(ws+5),a
		jp	jetman_redraw
jw_leave:	ld	a,(ws)
		and	0xC0
		or	1
		ld	(ws),a
		ld	a,(jetman_thruster_anim_state)
		or	a
		jp	nz,jw2
		ld	a,3
		ld	(jetman_thruster_anim_state),a
		ld	hl,(ws+1)
		ld	(jetman_thruster_anim_state+1),hl
		ld	hl,jetman_thruster_anim_state
		call	anim_reset_hl
jw2:		ld	hl,ws+2
		dec	(hl)
		dec	(hl)
		jp	jetman_redraw

; --- лазер ----------------------------------------------------------------------------------------------
laser_new_if_free:
		ld	a,(FRAMES)
		and	3
		ret	nz
		ld	hl,laser_beam_params
		ld	de,8
		ld	b,4
lnf0:		ld	a,(hl)
		or	a
		jp	z,laser_init
		add	hl,de
		dec	b
		jp	nz,lnf0
		ret
laser_init:					; HL = свободный лазер; Джетмен — текущий объект (ws)
		ld	(hl),0x10
		inc	hl
		ld	a,(ws+1)
		and	0xF8
		or	5
		ld	c,a
		ld	a,(ws)
		and	0x40
		jp	z,li_right
		ld	a,c
		sub	8
		ld	c,a
		jp	li_draw
li_right:	ld	a,(ws+1)
		and	7
		ld	a,c
		jp	z,li_r0
		add	a,8
li_r0:		add	a,0x10
		and	0xFE
		ld	c,a
li_draw:	ld	a,(ws+2)
		sub	0x0D
		ld	(hl),a			; +1 Y
		inc	hl
		ld	(hl),c			; +2 импульс 1
		ld	a,c
		and	0xFB
		inc	hl
		ld	(hl),a
		inc	hl
		ld	(hl),a
		inc	hl
		ld	(hl),a			; +3..+5
		inc	hl
		ld	a,(random_number)
		and	0x38
		or	0x84
		ld	(hl),a			; +6 длина
		inc	hl
		ex	de,hl
		ld	a,(random_number)
		and	3
		ld	c,a
		ld	b,0
		ld	hl,laser_beam_colours
		add	hl,bc
		ld	a,(hl)
		ld	(de),a			; +7 цвет
		ld	a,3
		jp	sound_ev

; рисует байт 0xFF в плоскости цвета A (остальные 0), HL = адрес (как ld (hl),$ff + атрибут ZX)
put_ff:
		push	hl
		and	7
		jp	nz,pf_c
		ld	a,1
		ld	(k_used),a
		xor	a
pf_c:
		ld	c,a
		ld	b,0
		push	hl
		ld	hl,ink_planes
		add	hl,bc
		ld	b,(hl)
		pop	hl
		ld	c,4
pf0:		ld	a,b
		rrca
		ld	b,a
		sbc	a,a			; 0xFF при переносе
		ld	(hl),a
		ld	a,h
		add	a,0x20
		ld	h,a
		dec	c
		jp	nz,pf0
		pop	hl
		ret
; AND NOT A во всех 4 плоскостях, HL = адрес
and_not4:
		cpl
		ld	c,a
		push	hl
		ld	b,4
an0:		ld	a,(hl)
		and	c
		ld	(hl),a
		ld	a,h
		add	a,0x20
		ld	h,a
		dec	b
		jp	nz,an0
		pop	hl
		ret

laser_animate:
		ld	a,(ws+2)
		ld	l,a
		and	4
		jp	z,la3
		ld	a,l
		and	1
		ld	a,8
		jp	z,la0
		ld	a,0xF8
la0:		add	a,l
		ld	(la_e),a
		ld	a,(ws+1)
		ld	h,a
		call	coord2scr		; Y, старый X
		ld	a,(ws+1)
		cp	0x80
		jp	nc,la1
		call	scr_any
		jp	nz,la2
la1:		ld	a,(la_e)
		ld	(ws+2),a
		ld	a,(ws+7)
		call	put_ff
		ld	a,(ws+6)
		sub	8
		ld	(ws+6),a
		and	0xF8
		jp	nz,la3
la2:		ld	a,(ws+2)
		and	0xFB
		ld	(ws+2),a
la3:		ld	hl,0x1C03		; маски 03, 1C, E0 по очереди
		ld	(la_mask),hl
		ld	a,0xE0
		ld	(la_mask+2),a
		ld	a,3
		ld	(la_cnt),a
		ld	hl,ws+3
la4:		ld	a,(ws+2)
		xor	(hl)
		and	0xF8
		jp	nz,la6
		call	la_rot
		inc	hl
		ld	a,(la_cnt)
		dec	a
		ld	(la_cnt),a
		jp	nz,la4
		xor	a
		ld	(ws),a
		ret
la6:		ld	a,(hl)
		and	4
		jp	nz,la7
		ld	a,(ws+6)		; dec (ix+6)
		dec	a
		ld	(ws+6),a
		ld	b,a
		and	7
		ret	nz
		ld	a,(random_number)
		and	3
		or	4
		or	b
		ld	(ws+6),a
		ld	a,(hl)
		or	4
		ld	(hl),a
		ret
la7:		ld	a,(hl)
		ld	c,a
		and	1
		ld	a,8
		jp	z,la8
		ld	a,0xF8
la8:		add	a,c
		ld	(hl),a
		push	hl
		ld	l,c			; Y, старый X
		ld	a,(ws+1)
		ld	h,a
		call	coord2scr
		call	la_rot
		call	and_not4
		pop	hl
		inc	hl
		ld	a,(la_cnt)
		dec	a
		ld	(la_cnt),a
		jp	nz,la4
		ret
la_rot:						; A = маска[0]; сдвиг очереди (exx; ld a,b; ld b,c; ld c,e)
		ld	a,(la_mask+1)
		ld	b,a
		ld	a,(la_mask+2)
		ld	(la_mask+1),a
		ld	a,(la_mask)
		push	af
		ld	a,b
		ld	(la_mask),a
		pop	af
		ret
la_e:		db	0
la_cnt:		db	0
la_mask:	ds	3
