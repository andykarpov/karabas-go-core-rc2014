# RC2014 core: Ф0 fit checks (the board builds come in Ф1).
#
#   make measure-all      XST of measure/rc2014_measure.v: T80 + Z2 512K + vdp18 + jt49 + hdf_ata + vt_term
#   make measure-vt       XST of the VT100 terminal alone (vt_term)
#   make measure-report   LUTs, FFs, block RAMs and the XST clock estimate of the measures
#   make clean            the intermediate files

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
XIL = source $(ISE_SETTINGS) > /dev/null;
prj_src = $(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' $(1) 2>/dev/null)

.PHONY: measure-all measure-vt measure-report clean

rc2014_measure.ngc: measure/rc2014_measure.xst measure/rc2014_measure.prj $(call prj_src,measure/rc2014_measure.prj)
	mkdir -p xst_measure/projnav.tmp
	$(XIL) xst -intstyle ise -ifn measure/rc2014_measure.xst -ofn rc2014_measure.syr > measure/xst_measure.log

vt_term.ngc: measure/vt_term.xst measure/vt_term.prj $(call prj_src,measure/vt_term.prj)
	mkdir -p xst_vt/projnav.tmp
	$(XIL) xst -intstyle ise -ifn measure/vt_term.xst -ofn vt_term.syr > measure/xst_vt.log

measure-all: rc2014_measure.ngc
measure-vt: vt_term.ngc

measure-report:
	@for s in rc2014_measure vt_term; do echo "== $$s"; grep -hE "Number of Slice LUTs|Number of Slice Registers|Number of Block RAM|DSP48A1s:|Maximum Frequency" $$s.syr 2>/dev/null || true; done

clean:
	rm -rf xst_measure xst_vt rc2014_measure.{ngc,ngr,syr,lso} rc2014_measure_xst.xrpt vt_term.{ngc,ngr,syr,lso} vt_term_xst.xrpt measure/xst_*.log
