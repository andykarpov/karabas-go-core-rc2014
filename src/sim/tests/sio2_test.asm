; sio2_test.asm: the second SIO/2 (84-87) set up as Fuzix does it (rc2014.s: the KIO probe writes
; 43 to 84-87, then sio_setup to 84 and 86), IM1, an ISR that polls like Fuzix tty_pollirq
; (RR0 bit 1 of each A channel, bit 0 of A and B: read the data, bit 1: reset ext/status) and
; reads the TMS status. Counts the interrupts for ~0.1 s and prints the count (hex, 16 bits) on
; SIO A of the first SIO: a few (TMS frames) is right, thousands = an interrupt that never clears.
; Profile Classic (sim/run_sio2.sh).

	.org	$0000
	di
	ld	sp,$FF00
	jp	start
	.fill	$0038-$,$FF
	; IM1
	push	af
	push	bc
	ld	hl,(count)
	inc	hl
	ld	(count),hl
	in	a,($99)		; TMS status
	ld	c,$80
	call	poll
	ld	c,$84
	call	poll
	pop	bc
	pop	af
	ei
	reti

; poll the chip at C (A control) as Fuzix sio_intr / sio_intrb
poll:	in	a,(c)
	bit	1,a
	ret	z
	call	pollb
	inc	c
	inc	c
pollb:	in	a,(c)
	bit	0,a
	jr	z,pb1
	inc	c
	in	b,(c)		; the data
	dec	c
pb1:	bit	1,a
	ret	z
	ld	a,$40		; reset ext / status interrupts (2 << 5)
	out	(c),a
	ret

start:
	; the first SIO as RomWBW leaves it (A and B: WR1 18)
	ld	hl,setup
	ld	bc,$0A80
	otir
	ld	hl,setup
	ld	bc,$0A82
	otir
	; the KIO probe of Fuzix at 84
	ld	a,$43
	out	($84),a
	out	($85),a
	out	($86),a
	out	($87),a
	; the second SIO
	ld	hl,setup
	ld	bc,$0A84
	otir
	ld	hl,setup
	ld	bc,$0A86
	otir
	ld	hl,0
	ld	(count),hl
	im	1
	ei
	ld	bc,0
	ld	d,1
wt:	dec	bc		; 65536 x 26 T = 0.23 s at 7.37 MHz
	ld	a,b
	or	c
	jr	nz,wt
	dec	d
	jr	nz,wt
	di
	ld	a,(count+1)
	call	puthex
	ld	a,(count)
	call	puthex
	ld	a,'.'
	call	putc
halt:	jr	halt

putc:	push	af
pw:	in	a,($80)
	bit	2,a
	jr	z,pw
	pop	af
	out	($81),a
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

setup:	.db	$00,$18,$04,$C4,$01,$18,$03,$E1,$05,$EA

count	.equ	$8000
	.end
