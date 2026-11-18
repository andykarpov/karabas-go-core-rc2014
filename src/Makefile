# RC2014 core: the ISE 14.7 flow of the boards (as core-bbc) and the Ф0 fit checks.
#
#   make minig            a board: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report     LUTs, slices, block RAMs and the timing result of the last build
#   make roms             the ROM images of the .kg (tools/rc2014_roms.sh <work dir>, in git)
#   make measure-all      XST of measure/rc2014_measure.v: T80 + Z2 512K + vdp18 + jt49 + hdf_ata + vt100_top
#   make       XST of the VT100 terminal alone (vt_term)
#   make measure-report   LUTs, FFs, block RAMs and the XST clock estimate of the measures
#   make clean            the intermediate files

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
XIL = source $(ISE_SETTINGS) > /dev/null;
prj_src = $(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' $(1) 2>/dev/null)

PART = xc6slx25-ftg256-2
BOARDS = minig
KG = rc2014.kg
JSON = core.json
ROMS = roms/kg/romwbw.rom roms/kg/classic.rom roms/kg/mini.rom
ROM_WORK ?= /tmp/rc2014-roms

# map / par options (cost table 2 by default, the rule of all the cores)
MAP_T_go ?= 2
MAP_T_mini ?= 2
MAP_T_minig ?= 2
MAP = -logic_opt off -ol high -xe n -xt 3 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc auto -power off
PAR = -ol high -xe c -mt 4

INCLUDES = $(wildcard ../modules/rtl/mcu/*.vh)

.NOTPARALLEL:

define board
SRC_$(1) := $$(call prj_src,karabas_$(1).prj)

karabas_$(1).ngc: karabas_$(1).prj karabas_$(1).xst $$(SRC_$(1)) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn karabas_$(1).xst -ofn karabas_$(1).syr

karabas_$(1).bin: karabas_$(1).ngc karabas_$(1).ucf karabas_$(1).ut
	$(XIL) ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc karabas_$(1).ucf -p $(PART) karabas_$(1).ngc karabas_$(1).ngd
	$(XIL) map -intstyle ise -p $(PART) -w $(MAP) -t $(MAP_T_$(1)) -o karabas_$(1)_map.ncd karabas_$(1).ngd karabas_$(1).pcf
	$(XIL) par -w -intstyle ise $(PAR) karabas_$(1)_map.ncd karabas_$(1).ncd karabas_$(1).pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml karabas_$(1).twx karabas_$(1).ncd -o karabas_$(1).twr karabas_$(1).pcf -ucf karabas_$(1).ucf
	$(XIL) bitgen -intstyle ise -f karabas_$(1).ut karabas_$(1).ncd

kg_$(1).stamp: karabas_$(1).bin $(JSON) $(ROMS)
	python3 tools/check_osd.py $(JSON)
	python3 make_core.py $(JSON) $(KG) --boards $(1)
	touch $$@

$(1): kg_$(1).stamp
$(1)-xst: karabas_$(1).ngc
$(1)-impl: karabas_$(1).bin
$(1)-core: kg_$(1).stamp
$(1)-report:
	@grep -E "Number of (Slice LUTs|occupied Slices|RAMB16BWERs|RAMB8BWERs|DSP48A1s):" karabas_$(1)_map.mrp
	@grep -E "constraints? (was|were) met|constraints? not met|Timing Score" karabas_$(1).par | sort -u
endef

$(foreach b,$(BOARDS),$(eval $(call board,$(b))))

roms:
	tools/rc2014_roms.sh $(ROM_WORK)

.PHONY: all roms measure-all measure-report clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report)

rc2014_measure.ngc: measure/rc2014_measure.xst measure/rc2014_measure.prj $(call prj_src,measure/rc2014_measure.prj)
	mkdir -p xst_measure/projnav.tmp
	$(XIL) xst -intstyle ise -ifn measure/rc2014_measure.xst -ofn rc2014_measure.syr > measure/xst_measure.log

measure-all: rc2014_measure.ngc

measure-report:
	@for s in rc2014_measure; do echo "== $$s"; grep -hE "Number of Slice LUTs|Number of Slice Registers|Number of Block RAM|DSP48A1s:|Maximum Frequency" $$s.syr 2>/dev/null || true; done

clean:
	rm -rf xst _ngo xlnx_auto_0_xdb _xmsgs iseconfig
	rm -f $(foreach b,$(BOARDS),$(addprefix karabas_$(b),.ngc .ngr .syr .lso _xst.xrpt .ngd .pcf _map.ncd _map.map _map.mrp _map.ngm .ncd .par .pad .twr .twx .bgn .bit .drc .ptwx .unroutes .xpi _pad.csv _pad.txt _summary.xml _usage.xml _bitgen.xwbt _ngdbuild.xrpt) kg_$(b).stamp)
	rm -rf xst_measure rc2014_measure.{ngc,ngr,syr,lso} rc2014_measure_xst.xrpt measure/xst_*.log
