#!/bin/bash
# emu_ref.sh: the reference runs of the RC2014 profiles on Alan Cox EmulatorKit (rc2014),
# console on stdin / stdout, the output kept in sim/ref/<name>.txt for the RTL checks.
#
#   tools/emu_ref.sh <work dir>        clone + build EmulatorKit, fetch the ROMs, run all
#
# Needs: git, gh, unzip, cc, libsdl2-dev (EmulatorKit includes SDL2/SDL.h even in the noui build).
# EmulatorKit b145b90 + tools/emulatorkit-fp.patch: an unknown port (00 = front panel switches)
# reads RC_FP instead of 0x78 (0x78 = SEC + AUTO + DISK + FLOP: RomWBW moves the console to
# the second serial unit). The core reads 00 there.
# Known limit: RomWBW on SIO/2 in IM1 prints "+++ BAD INT" on input (the emulator keeps the
# SIO interrupt live until RETI); the RomWBW runs use the ACIA.
# Input is typed slowly: the emulator runs in real time and drops characters sent too fast.

set -e -o pipefail
W=${1:?work dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
REF=$HERE/sim/ref
mkdir -p "$W" "$REF"
cd "$W"

[ -d EmulatorKit ] || { git clone -q https://github.com/etchedpixels/EmulatorKit.git; git -C EmulatorKit checkout -q b145b90; git -C EmulatorKit apply "$HERE/tools/emulatorkit-fp.patch"; }
[ -x EmulatorKit/rc2014 ] || make -C EmulatorKit rc2014 makedisk CFLAGS="-Wall -g -O2" > /dev/null
[ -d RC2014 ] || git clone -q --depth 1 https://github.com/RC2014Z80/RC2014.git
if [ ! -f romwbw/Binary/RCZ80_std.rom ]; then
	mkdir -p romwbw
	gh release download -R wwarthen/RomWBW v3.6.0 -p 'RomWBW-v3.6.0-Package.zip' -D romwbw --clobber
	(cd romwbw && unzip -q -o RomWBW-v3.6.0-Package.zip 'Binary/RCZ80_std.rom' 'Binary/hd1k_combo.img')
fi
if [ ! -f cf.ide ]; then
	EmulatorKit/makedisk 1 cf.ide
	dd if=romwbw/Binary/hd1k_combo.img of=cf.ide bs=512 seek=2 conv=notrunc status=none
fi

F=RC2014/ROMs/Factory
E=EmulatorKit/rc2014
ROM=romwbw/Binary/RCZ80_std.rom
ty() { local i; for ((i = 0; i < ${#1}; i++)); do printf '%s' "${1:i:1}"; sleep 0.3; done; printf '\r'; sleep 0.5; }
# run <name> <seconds> <input function> <command...>: the input is piped in (the emulator reads
# stdin); repeated lines (a monitor prompt after the input ends) are collapsed by uniq
run() { local name=$1 t=$2 in=$3; shift 3; { $in | timeout "$t" "$@" 2>&1 || true; } | tr -d '\000' | sed 's/\r$//' | uniq > "$REF/$name.txt"; echo "$name: $(wc -l < "$REF/$name.txt") lines"; }

in_mini() { sleep 2; printf '\r'; sleep 1; printf '\r'; sleep 1; ty 'PRINT 2+2'; sleep 2; }
in_classic() { sleep 3; ty '?'; sleep 3; }
in_rom() { sleep 10; ty c; sleep 8; ty 'dir b:'; sleep 5; }
in_cf() { sleep 10; ty 2; sleep 10; ty dir; sleep 6; }

# Mini: BASIC 32K on the ACIA (bank 0 of R0000009)
run mini 12 in_mini $E -a -r $F/R0000009.BIN -e 0
# Classic: SCM (bank 2 of 24886009) on the SIO/2
run classic 10 in_classic $E -s -r $F/24886009.BIN -e 2
# RomWBW 512K: loader, CP/M 2.2 from the ROM disk
run romwbw_rom 35 in_rom env RC_FP=0 $E -b -a -R -r $ROM
# RomWBW 512K: CP/M 2.2 from the CF (hd1k_combo, slice 0)
run romwbw_cf 40 in_cf env RC_FP=0 $E -b -a -R -i cf.ide -r $ROM
