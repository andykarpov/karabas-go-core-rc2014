#!/bin/bash
# Builds the Z80 test programs of src/sim/tests with uz80as (of the RomWBW tools:
# tools/rc2014_romwbw.sh, or RomWBW/Tools/unix/uz80as by hand). UZ80AS=<path> overrides.
#   sim/tests/build.sh   -> sim/build/tests/<name>.bin
set -e
cd "$(dirname "$0")"
U=${UZ80AS:-$HOME/work/rc2014/RomWBW/Tools/Linux/uz80as}
mkdir -p ../build/tests
for f in *.asm; do
	"$U" -t z80 "$f" "../build/tests/${f%.asm}.bin" "../build/tests/${f%.asm}.lst"
done
