;
;==================================================================================================
;   ROMWBW BUILD SETTINGS OF THE KARABAS RC2014 CORE (karabas-go-core-rc2014)
;==================================================================================================
;
; RCZ80_std (the official RCBus Z80 build) plus the cards of the core that std leaves off:
;   TMS9918A at 98 / 99 with the PS/2 keyboard of an 8242 at 60 / 64 (TMSMODE_MSXKBD),
;   its frame interrupt as the system timer (IM1),
;   YM2149 at D8 / D0 (AYMODE_RC2014, 1.7897725 MHz).
; The console starts on the serial port; the front panel port 00 reads SW_CRT (0x80) when the
; OSD item Console = TMS9918, and HBIOS moves the console to the TMS then.
;
; Built by tools/rc2014_romwbw.sh (RomWBW v3.6.0 on Linux).
;
#DEFINE PLATFORM_NAME "RC2014 Karabas", " [", CONFIG, "]"
#DEFINE	BOOT_DEFAULT	"H"		; DEFAULT BOOT LOADER CMD FOR EMPTY CMD LINE
#DEFINE AUTO_CMD	""		; AUTO CMD WHEN BOOT_TIMEOUT IS ENABLED
;
#INCLUDE "Config/RCZ80_std.asm"		; INHERIT FROM OFFICIAL BUILD SETTINGS
;
TMSENABLE	.SET	TRUE		; TMS: ENABLE TMS9918 VIDEO/KBD DRIVER (TMS.ASM)
TMSMODE		.SET	TMSMODE_MSXKBD	; TMS: STD MSX PORTS + PS2 KEYBOARD (8242 AT 60 / 64)
TMSTIMENABLE	.SET	TRUE		; TMS: ENABLE TIMER INTERRUPTS (REQUIRES IM1)
AY38910ENABLE	.SET	TRUE		; AY: ENABLE AY-3-8910 / YM2149 SOUND DRIVER
AYMODE		.SET	AYMODE_RC2014	; AY: D8 REGISTER SELECT, D0 DATA
