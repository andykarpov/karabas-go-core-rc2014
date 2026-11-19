#!/bin/bash
# rc2014_fuzix.sh: the Fuzix disk image of the RC2014 core (EtchedPixels/FUZIX, platform rc2014: the
# 512K ROM / RAM card, SIO / ACIA, CF at 10, TMS9918A as the timer and a console with the PS/2
# controller at 60 / 64), built from the sources:
#   - SDCC 3.8 with the Fuzix patches (EtchedPixels/sdcc280, the z80 / z180 ports only): the kernel
#     (--external-banker; the SDCC 4.2 of the distribution does not take it) -> <work>/sdcc-fuzix
#   - Fuzix-Bintools + Fuzix-Compiler-Kit (fcc, the user programs) -> /opt/fcc (cc.c has the path
#     built in: mkdir /opt/fcc owned by the user first)
#   - FUZIX `make TARGET=rc2014 diskimage` -> FUZIX/Images/rc2014/disk.img
# needs: gcc, g++, make, autoconf, texinfo, bison, flex, libboost-dev, libbsd-dev, byacc, sdcc (the distribution one
# is not used for the kernel), a writable /opt/fcc
#   tools/rc2014_fuzix.sh <work dir>    -> roms/fuzix/rc2014_fuzix.img.xz (+ the commits in .txt)
set -e -o pipefail
W=${1:?work dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
[ -w /opt/fcc ] || { echo "/opt/fcc must exist and be writable (sudo mkdir /opt/fcc; sudo chown $USER /opt/fcc)"; exit 1; }
mkdir -p "$W"
cd "$W"
for r in FUZIX Fuzix-Bintools Fuzix-Compiler-Kit sdcc280; do
	[ -d $r ] || git clone -q --depth 1 https://github.com/EtchedPixels/$r.git
done

# SDCC with the Fuzix patches (its configure is older than configure.ac: no sdas/asz280/Makefile,
# autoconf makes it again)
if [ ! -x sdcc-fuzix/bin/sdcc ]; then
	grep -q asz280 sdcc280/sdcc/configure || (cd sdcc280/sdcc && autoconf)
	(cd sdcc280/sdcc && ./configure --prefix="$W/sdcc-fuzix" \
		--disable-mcs51-port --disable-r2k-port --disable-r3ka-port --disable-gbz80-port \
		--disable-tlcs90-port --disable-ez80_z80-port --disable-ds390-port --disable-ds400-port \
		--disable-pic14-port --disable-pic16-port --disable-hc08-port --disable-s08-port \
		--disable-stm8-port --disable-pdk13-port --disable-pdk14-port --disable-pdk15-port \
		--disable-ucsim --disable-sdcdb --disable-non-free \
		&& make -j8 && make install)
fi
export PATH="$W/sdcc-fuzix/bin:/opt/fcc/bin:$PATH"

# the Fuzix tools in /opt/fcc
[ -x /opt/fcc/bin/as8080 ] || (cd Fuzix-Bintools && make -j8 && make install)
[ -x /opt/fcc/bin/fcc ] || (cd Fuzix-Compiler-Kit && make bootstrap && make install)

# Fuzix (the kernel always from clean: objects of another sdcc break binprep)
make -C FUZIX TARGET=rc2014 kclean
make -C FUZIX TARGET=rc2014 diskimage
mkdir -p "$HERE/roms/fuzix"
xz -9 -c FUZIX/Images/rc2014/disk.img > "$HERE/roms/fuzix/rc2014_fuzix.img.xz"
{
	echo "Fuzix disk image of the RC2014 core: write rc2014_fuzix.img (unxz) as the CF card image."
	for r in FUZIX Fuzix-Bintools Fuzix-Compiler-Kit sdcc280; do
		echo "$r $(git -C $r rev-parse HEAD) https://github.com/EtchedPixels/$r"
	done
} > "$HERE/roms/fuzix/rc2014_fuzix.txt"
ls -la "$HERE/roms/fuzix"
