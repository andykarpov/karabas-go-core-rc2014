; sn_test.asm: the SN76489 module in the simulation (profile Classic, sim/run_sn.sh): a tone on
; channel 0 of the left chip (FF), noise on the right chip (FB), the other channels silent.
SN_L	.equ	$FF
SN_R	.equ	$FB

	.org	$0000
	di
	ld	sp,$FF00
	; all channels off (attenuation 15) on both chips
	ld	hl,silent
	ld	b,4
s1:	ld	a,(hl)
	out	(SN_L),a
	out	(SN_R),a
	inc	hl
	djnz	s1
	; left: tone 0 = 0x08F (3579545 / 32 / 143 = 782 Hz), loud
	ld	a,$8F
	out	(SN_L),a
	ld	a,$08
	out	(SN_L),a
	ld	a,$90
	out	(SN_L),a
	; right: white noise, N/512, loud
	ld	a,$E4
	out	(SN_R),a
	ld	a,$F0
	out	(SN_R),a
loop:	jr	loop

silent:	.db	$9F,$BF,$DF,$FF
	.end
