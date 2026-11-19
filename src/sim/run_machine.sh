#!/bin/bash
# Builds the verilator model of rc2014_machine (T80s through ghdl, sim_machine.cpp: the SRAM, the
# terminal line) and runs it with the given arguments (see sim_machine.cpp). Build in src/sim/build.
#   sim/run_machine.sh --profile 2 --rom 0x110000:roms/kg/mini.rom --ms 300 --keys "500:PRINT 2+2|"
set -e
cd "$(dirname "$0")"
SIM=$(pwd)
SRC=$(cd .. && pwd)
B=$SIM/build
mkdir -p $B/v
VLOG="$SRC/rtl/karabas/rc2014_machine.v $SRC/rtl/karabas/rc2014_ser.v $SRC/rtl/karabas/rc2014_acia.v $SRC/rtl/karabas/rc2014_sio.v $SRC/rtl/karabas/rc2014_cf.v $SRC/rtl/karabas/rc2014_ds1302.v $SRC/../modules/rtl/mcu/hdf_ata.v $SRC/rtl/karabas/rc2014_kbd8242.v $SRC/../modules/rtl/mem/kg_spram.v $(ls $SRC/rtl/jt49/jt49*.v)"
if [ ! -f $B/vhdl_ghdl.v ] || [ -n "$(find $SRC/rtl/T80 $SRC/rtl/vdp18 vhdl2v.sh -newer $B/vhdl_ghdl.v 2>/dev/null)" ]; then
	./vhdl2v.sh $B > $B/ghdl.log 2>&1 || { grep -v -i warning $B/ghdl.log | tail -30; exit 1; }
fi
BIN=$B/obj/Vrc2014_machine
if [ ! -x $BIN ] || [ -n "$(find $B/vhdl_ghdl.v $VLOG sim_machine.cpp fixcase.py run_machine.sh -newer $BIN 2>/dev/null)" ]; then
	rm -f $B/v/*.v
	python3 -I fixcase.py $B/vhdl_ghdl.v $B/v $VLOG
	verilator -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-COMBDLY -Wno-UNOPTFLAT \
		--no-timing +1364-2005ext+v --top-module rc2014_machine -Mdir $B/obj --cc $B/v/*.v \
		--exe $SIM/sim_machine.cpp -CFLAGS "-std=c++17 -O2" -o Vrc2014_machine > $B/verilator.log 2>&1 \
		|| { grep -E '%Error' $B/verilator.log | head -30; exit 1; }
	make -s -j8 -C $B/obj -f Vrc2014_machine.mk > $B/make.log 2>&1 || { tail -30 $B/make.log; exit 1; }
fi
cd $SRC
exec $BIN "$@"
