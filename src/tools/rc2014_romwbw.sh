#!/bin/bash
# rc2014_romwbw.sh: our RomWBW ROM (roms/romwbw/RCZ80_kg.asm = RCZ80_std + TMS9918 / 8242 / YM2149)
# from the RomWBW v3.6.0 sources, built on Linux (the RomWBW tools are built first).
#   needs: gcc, make, srecord (srec_cat), libncurses-dev (cpmtools fsed.cpm)
#   tools/rc2014_romwbw.sh <work dir>    -> roms/kg/romwbw.rom (512K); then `make minig-core` etc.
#   (the ROM is a part of the .kg only: no new bitstream is needed)
set -e -o pipefail
W=${1:?work dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
for t in srec_cat gcc make; do
	command -v $t > /dev/null || { echo "missing $t (apt: srecord / build-essential)"; exit 1; }
done
[ -f /usr/include/ncurses.h ] || { echo "missing ncurses.h (apt: libncurses-dev)"; exit 1; }
mkdir -p "$W" "$HERE/roms/kg"
cd "$W"
# zxcc asks stdin for a key (FIONREAD): a file or /dev/null gives garbage and LINK aborts; an
# empty fifo open both ways never has a byte
[ -p stdin.fifo ] || mkfifo stdin.fifo
exec 0<>stdin.fifo
[ -d RomWBW ] || git clone -q --depth 1 --branch v3.6.0 https://github.com/wwarthen/RomWBW.git
# always from a clean tree: a failed run leaves generated files behind that make takes as done (a
# missing bin2asm left an empty font6x8u.asm: the TMS had no font)
git -C RomWBW clean -fdxq
git -C RomWBW checkout -q .
cp "$HERE/roms/romwbw/RCZ80_kg.asm" RomWBW/Source/HBIOS/Config/RCZ80_kg.asm
make -C RomWBW tools
make -C RomWBW/Source shared bp ROM_PLATFORM=RCZ80 ROM_CONFIG=kg
make -C RomWBW/Source/HBIOS ROM_PLATFORM=RCZ80 ROM_CONFIG=kg
[ -s RomWBW/Source/HBIOS/font6x8u.asm ] || { echo "the 6x8 font of the TMS is empty"; exit 1; }
cp RomWBW/Binary/RCZ80_kg.rom "$HERE/roms/kg/romwbw.rom"
(cd "$HERE/roms/kg" && sha1sum romwbw.rom)
