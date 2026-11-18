#!/bin/bash
# rc2014_roms.sh: the ROM images of the .kg (roms/kg, kept in git):
#   romwbw.rom  RomWBW v3.6.0 RCZ80_std.rom (512K)          -> SRAM 0x000000
#   classic.rom RC2014 Factory 24886009.BIN (64K, SCM)       -> SRAM 0x100000
#   mini.rom    RC2014 Factory R0000009.BIN (64K, BASIC)     -> SRAM 0x110000
#   tools/rc2014_roms.sh <work dir>   (the work dir of tools/emu_ref.sh can be reused)
set -e -o pipefail
W=${1:?work dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$W" "$HERE/roms/kg"
cd "$W"
[ -d RC2014 ] || git clone -q --depth 1 https://github.com/RC2014Z80/RC2014.git
if [ ! -f romwbw/Binary/RCZ80_std.rom ]; then
	mkdir -p romwbw
	gh release download -R wwarthen/RomWBW v3.6.0 -p 'RomWBW-v3.6.0-Package.zip' -D romwbw --clobber
	(cd romwbw && unzip -q -o RomWBW-v3.6.0-Package.zip 'Binary/RCZ80_std.rom')
fi
cp romwbw/Binary/RCZ80_std.rom "$HERE/roms/kg/romwbw.rom"
cp RC2014/ROMs/Factory/24886009.BIN "$HERE/roms/kg/classic.rom"
cp RC2014/ROMs/Factory/R0000009.BIN "$HERE/roms/kg/mini.rom"
(cd "$HERE/roms/kg" && sha1sum romwbw.rom classic.rom mini.rom)
