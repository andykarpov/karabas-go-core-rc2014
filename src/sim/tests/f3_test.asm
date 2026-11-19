; f3_test.asm: the cards of Ф3 in the simulation (profile Classic: the ROM window 0000-3FFF,
; SIO/2 at 80-83). Built by sim/tests/build.sh (uz80as of the RomWBW tools), run by sim/run_f3.sh.
; Prints on SIO A:
;   T<vram>   the TMS9918 VRAM read back (expect T5A)
;   A<r0>     YM2149 register 0 read back (expect A40)
;   J<a><1><2> the joystick of YM2149 port A, ports 01 / 02
;   K<self test><kbd bytes...>  the 8242 (expect K55 then the scan codes)
;   I<n>      VDP frame interrupts counted (IM1)
;   B         then echoes SIO B upper case back to SIO B
; and leaves the TMS in text mode with "HELLO RC2014" on the screen.

SIOA_C	.equ	$80
SIOA_D	.equ	$81
SIOB_C	.equ	$82
SIOB_D	.equ	$83
VDP_D	.equ	$98
VDP_C	.equ	$99
AY_SEL	.equ	$D8
AY_DAT	.equ	$D0
KB_D	.equ	$60
KB_S	.equ	$64

	.org	$0000
	di
	ld	sp,$FF00
	jp	start

	.fill	$0038-$,$FF	; (uz80as leaves the gap of an .org out of the binary)
	; IM1: the VDP frame interrupt (the status read clears it)
	push	af
	in	a,(VDP_C)
	ld	a,(icount)
	inc	a
	ld	(icount),a
	pop	af
	ei
	reti

start:
	; SIO A and B: x64 (115200), 8N1, Rx / Tx on, no interrupts
	ld	hl,sioinit
	ld	b,sioinit_e-sioinit
	ld	c,SIOA_C
	otir
	ld	hl,sioinit
	ld	b,sioinit_e-sioinit
	ld	c,SIOB_C
	otir

	; ---- TMS9918: text mode, name table 0000, patterns 0800
	ld	hl,vdpregs
	ld	b,8
	ld	c,$80
vr:	ld	a,(hl)
	out	(VDP_C),a
	ld	a,c
	out	(VDP_C),a
	inc	hl
	inc	c
	djnz	vr
	; clear the name table (960 bytes of space = 20h)
	ld	de,$0000
	call	vwaddr
	ld	bc,960
cl:	ld	a,$20
	out	(VDP_D),a
	dec	bc
	ld	a,b
	or	c
	jr	nz,cl
	; patterns: every char 8 lines of $5A, then space blank
	ld	de,$0800
	call	vwaddr
	ld	bc,256*8
pt:	ld	a,$5A
	out	(VDP_D),a
	dec	bc
	ld	a,b
	or	c
	jr	nz,pt
	; space blank: pattern 20h = 0900-0907
	ld	de,$0900
	call	vwaddr
	ld	b,8
	xor	a
sp1:	out	(VDP_D),a
	djnz	sp1
	; the text at row 2
	ld	de,$0000+80
	call	vwaddr
	ld	hl,hello
tx:	ld	a,(hl)
	or	a
	jr	z,txe
	out	(VDP_D),a
	inc	hl
	jr	tx
txe:
	; read back a pattern byte
	ld	de,$0808
	call	vraddr
	in	a,(VDP_D)
	ld	b,a
	ld	a,'T'
	call	putc
	ld	a,b
	call	puthex

	; ---- YM2149
	ld	a,7
	out	(AY_SEL),a
	ld	a,$B8		; tone A B C, port A in, port B out
	out	(AY_DAT),a
	ld	a,0
	out	(AY_SEL),a
	ld	a,$40
	out	(AY_DAT),a
	ld	a,8
	out	(AY_SEL),a
	ld	a,$0F
	out	(AY_DAT),a
	ld	a,0
	out	(AY_SEL),a
	in	a,(AY_SEL)
	ld	b,a
	ld	a,'A'
	call	putc
	ld	a,b
	call	puthex

	; ---- joysticks: port A with port B bit 6 = 0 (joystick 1), ports 01 / 02
	ld	a,15
	out	(AY_SEL),a
	xor	a
	out	(AY_DAT),a
	ld	a,14
	out	(AY_SEL),a
	in	a,(AY_SEL)
	ld	b,a
	ld	a,'J'
	call	putc
	ld	a,b
	call	puthex
	in	a,($01)
	call	puthex
	in	a,($02)
	call	puthex

	; ---- 8242: self test, then 3 bytes of the keyboard
	ld	a,$AA
	out	(KB_S),a
	call	kget
	ld	b,a
	ld	a,'K'
	call	putc
	ld	a,b
	call	puthex
	ld	b,3
kb:	push	bc
	call	kget
	call	puthex
	pop	bc
	djnz	kb

	; ---- VDP interrupt: IE on (R1 = F0), IM1, count for a while
	ld	a,$F0
	out	(VDP_C),a
	ld	a,$81
	out	(VDP_C),a
	xor	a
	ld	(icount),a
	im	1
	ei
	ld	bc,0
wt:	dec	bc		; ~ 0.2 s at 7.37 MHz
	ld	a,b
	or	c
	jr	nz,wt
	di
	ld	a,'I'
	call	putc
	ld	a,(icount)
	call	puthex

	; ---- SIO B echo
	ld	a,'B'
	call	putc
eb:	in	a,(SIOB_C)
	bit	0,a
	jr	z,eb
	in	a,(SIOB_D)
	cp	'a'
	jr	c,eb1
	cp	'z'+1
	jr	nc,eb1
	sub	$20
eb1:	ld	b,a
ebw:	in	a,(SIOB_C)
	bit	2,a
	jr	z,ebw
	ld	a,b
	out	(SIOB_D),a
	jr	eb

; the 8242 data byte (waits for OBF)
kget:	in	a,(KB_S)
	bit	0,a
	jr	z,kget
	in	a,(KB_D)
	ret

; the VRAM write / read address DE
vwaddr:	ld	a,e
	out	(VDP_C),a
	ld	a,d
	or	$40
	out	(VDP_C),a
	ret
vraddr:	ld	a,e
	out	(VDP_C),a
	ld	a,d
	out	(VDP_C),a
	ret

putc:	push	af
pw:	in	a,(SIOA_C)
	bit	2,a
	jr	z,pw
	pop	af
	out	(SIOA_D),a
	ret

puthex:	push	af
	rrca
	rrca
	rrca
	rrca
	call	nib
	pop	af
nib:	and	$0F
	add	a,'0'
	cp	'9'+1
	jr	c,putc
	add	a,7
	jr	putc

sioinit:
	.db	$18		; channel reset
	.db	$04,$C4		; WR4: x64, 1 stop
	.db	$03,$C1		; WR3: Rx 8 bits, on
	.db	$05,$EA		; WR5: DTR, Tx 8 bits, Tx on, RTS
	.db	$01,$00		; WR1: no interrupts
sioinit_e:

vdpregs:
	.db	$00,$D0,$00,$00,$01,$00,$00,$F4

hello:	.db	"HELLO RC2014",0

icount	.equ	$8000

	.end
