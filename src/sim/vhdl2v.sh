#!/bin/bash
# T80s and vdp18_core (VHDL) as a Verilog netlist for verilator: ghdl --synth with the generics of its instance in
# rc2014_machine (Mode 0, T2Write 1, IOWait 1). Run from anywhere.
#   sim/vhdl2v.sh <out dir>   -> <out dir>/vhdl_ghdl.v
set -eu
OUT=$(mkdir -p "${1:?output dir}" && cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/.." && pwd)
cd "$SRC"
G="--std=08 -fsynopsys -frelaxed --workdir=$OUT/ghdl"
mkdir -p "$OUT/ghdl" "$OUT/vhd"
rm -f "$OUT"/ghdl/work-obj08.cf
# instance labels renamed where ghdl makes a net name of label_port that is also a signal
# (T80: label alu, port Q -> alu_q = the signal ALU_Q)
for f in T80_Pack T80_ALU T80_MCode T80_Reg T80 T80s; do
	sed -e 's/^\tmcode : T80_MCode/\tu_mcode : T80_MCode/' -e 's/^\talu : T80_ALU/\tu_alu : T80_ALU/' \
		-e 's/^\tRegs : T80_Reg/\tu_regs : T80_Reg/' "rtl/T80/$f.vhd" > "$OUT/vhd/$f.vhd"
	ghdl -a $G "$OUT/vhd/$f.vhd"
done
ghdl --synth $G --out=verilog -gMode=0 -gT2Write=1 -gIOWait=1 T80s > "$OUT/vhdl_ghdl.v"
# vdp18 (the TMS9918A of rc2014_machine, compat_rgb_g 0)
for f in vdp18_pack-p vdp18_col_pack-p vdp18_clk_gen vdp18_hor_vert vdp18_ctrl vdp18_cpuio vdp18_addr_mux \
	vdp18_pattern vdp18_sprite vdp18_col_mux vdp18_core; do
	ghdl -a $G "rtl/vdp18/$f.vhd"
done
ghdl --synth $G --out=verilog -gcompat_rgb_g=0 vdp18_core >> "$OUT/vhdl_ghdl.v"
wc -l "$OUT/vhdl_ghdl.v"
