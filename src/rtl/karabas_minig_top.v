`timescale 1ns / 1ps
`default_nettype wire

/*
 RC2014 core for Karabas Mini rev.G (HDMI, PCM5102): a Z80 RC2014 (rc2014_machine: the memory
 cards of three profiles, ACIA / SIO/2) with a built-in VT100 terminal on the serial line, and the
 board glue of karabas-go-modules.

 Clocks (rc2014_clocks, one PLL): clk_50 (the machine, the SRAM, the MCU link, the DAC, the video
 timing of the terminal), clk_25 (640 x 480 pixels, the OSD, HDMI), clk_125 / clk_125_n (the
 serialiser), clk_10 (the PDP-11 of the terminal), clk_8 (FT_CLK_OUT).

 Memory (rc2014_mem): the 4 MB SRAM as the byte memory of the machine; the ROM images (roms/kg,
 tools/rc2014_roms.sh) are loaded from the .kg when the core starts, the machine is held in reset
 while they load:
   0x000000 romwbw.rom (512K, RomWBW RCZ80_std)   0x100000 classic.rom (64K, 24886009: SCM)
   0x110000 mini.rom (64K, R0000009: BASIC)         0x080000 / 0x120000 RAM

 Terminal: vt100_top (pdp2011 vt10x, the tsybulin/karabas-go-core-pdp2026 version: keyboard
 scan codes straight in, 640 x 480 at 60 Hz) on the terminal line of the machine (ACIA or SIO/2 A,
 115200 8N1); its keyboard = the PS/2 set 2 bytes of kg_mcu2. Its picture is one bit (vgao), drawn
 in the colour of the OSD item (amber / green / white, the pdp2026 colours). The pixels of the
 terminal change on every other clk_50 edge (its own 25 MHz): registered on clk_50, then on clk_25
 (in phase with clk_50 from the PLL).

 Audio: the bell of the terminal to the PCM5102 and HDMI (48 kHz).

 Soft switches (the index of the item in the osd of core.json):
   0 Profile (RomWBW 512K / Classic / Mini)   1 Serial (SIO/2 / ACIA: Classic and RomWBW; Mini is
   always ACIA)   2 CPU (7.37 / 14.75 MHz)   3 Colour (Amber / Green / White)   4 Reset
 A change of Profile or Serial (or the Reset item, or a ROM load) resets the machine.
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP32_SPI_CS_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;
assign MIDI_TX = 1'b1;
assign TAPE_OUT = 1'b0;

// SD2: not used yet
assign SD_CS_N = 1'b1;
assign SD_CLK = 1'b0;
assign SD_DI = 1'b1;

// SDRAM: not used (NOP: RAS / CAS / WE high)
assign SDR_BA = 2'b00;
assign SDR_A = 13'd0;
assign SDR_CLK = 1'b0;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

// FLASH_CS_N (T3) is the SDRAM /CS of Mini G2 (rev G: tied low on the board): always selected
assign FLASH_CS_N = 1'b0;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

// ------------------------------------------------------------------ clocks

wire clk_50, clk_125, clk_125_n, clk_25, clk_10, clk_8, pll_locked;
rc2014_clocks clocks (
	.clk_in(CLK_50MHZ),
	.clk_50(clk_50),
	.clk_125(clk_125),
	.clk_125_n(clk_125_n),
	.clk_25(clk_25),
	.clk_10(clk_10),
	.clk_8(clk_8),
	.locked(pll_locked)
);
(* KEEP = "TRUE" *) wire areset_async = ~pll_locked;
wire areset, areset_25;
kg_sync #(.W(1), .STAGES(2), .INIT(1'b1)) sync_areset (.clk(clk_50), .d(areset_async), .q(areset));
kg_sync #(.W(1), .STAGES(2), .INIT(1'b1)) sync_areset_25 (.clk(clk_25), .d(areset_async), .q(areset_25));

// the clock of the FT812
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

// karabas: MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire [1:0] ld_kind;
wire [7:0] ld_data, ld_slot;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire [8*8-1:0] sw;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on;
wire [15:0] dbg_addr;
reg [15:0] dbg_data = 16'd0;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;

// the image files of the mcu (the CF: slot 4 = device 0 of hdf_ata, slot 5 = device 1)
wire [7:0] sdc_img_mounted, sdc_byte_in_data;
wire [63:0] sdc_img_size;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [1:0] hdf_rd, hdf_wr;
wire [31:0] hdf_sector;
wire [7:0] hdf_out_data;
wire hdf_own = sdc_slot[2:1] == 2'b10;
wire cf_led;

// the RTC RAM of kg_mcu2 (rtc_mode 1: DS1307 registers, BCD) <-> the DS1302 of the machine
wire [7:0] rtc_a, rtc_di, rtc_do;
wire rtc_cs, rtc_wr_n;

kg_mcu2 #(
	.SW_N(8),
	.CS_FILTER(3),
	.CAPS(16'h0000),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),
	.IMG_OUT_LATENCY(3), // the address register of kg_l2_img, the buffer RAM of hdf_ata, its output register
	.ENABLE_AUX(1),      // DEBUG_*: the state of the core (AT+KARABAS=debug:1, kg_board.py log)
	.ENABLE_FT(1),
	.ENABLE_SD2(0)
) mcu (
	.CLK(clk_50),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(1'b1),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(),
	.PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(), .JOY_R(), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(ld_slot), .LD_SIZE(), .LD_EXT(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size), .SDC_RD({ 2'b00, hdf_rd, 4'b0000 }),
	.SDC_WR({ 2'b00, hdf_wr, 4'b0000 }), .SDC_SECTOR(hdf_sector), .SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done),
	.SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot), .SDC_BYTE_IN_STROBE(sdc_byte_in_strobe),
	.SDC_BYTE_ADDR(sdc_byte_addr), .SDC_BYTE_IN_DATA(sdc_byte_in_data),
	.SDC_BYTE_OUT_DATA(hdf_out_data), .IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),
	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_CS(rtc_cs), .RTC_WR_N(rtc_wr_n), .MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(dbg_addr), .DEBUG_DATA(dbg_data), .RTC_DO(rtc_do),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b1), .SD2_CS_N()
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;

// ------------------------------------------------------------------ soft switches, reset

wire [1:0] sw_profile = sw[0*8 +: 2];
wire sw_serial = sw[1*8];
wire sw_turbo = sw[2*8];
wire [1:0] sw_colour = sw[3*8 +: 2];
wire sw_reset = sw[4*8];

wire loading;

// the profile and the serial card are taken while the machine is in reset; a change of either (or
// the Reset item, or a ROM load) resets the machine for about 1.3 ms (16 bits of clk_50)
reg [1:0] profile = 2'd0;
reg serial = 1'b0;
reg [15:0] rst_cnt = 16'd0;
reg machine_reset = 1'b1;
always @(posedge clk_50) begin
	if (areset || loading || sw_reset || sw_profile != profile || sw_serial != serial) begin
		rst_cnt <= 16'd0;
		profile <= sw_profile == 2'd3 ? 2'd0 : sw_profile;
		serial <= sw_serial;
	end
	else if (!rst_cnt[15])
		rst_cnt <= rst_cnt + 16'd1;
	machine_reset <= !rst_cnt[15];
end

// ------------------------------------------------------------------ the machine

wire [21:0] mem_a;
wire mem_rd, mem_wr;
wire [7:0] mem_wdata, mem_rdata;
wire term_tx, term_rx;     // the terminal side of the line
wire term_rts;             // the terminal: 1 = wait (its receive silo is filling up)
wire host_rx, term_xoff;   // the terminal line after rc2014_xonxoff: XOFF / XON taken out
wire [7:0] xoff_count;
rc2014_xonxoff xonxoff (
	.clk(clk_50),
	.reset(areset),
	.term_tx(term_tx),
	.host_rx(host_rx),
	.xoff(term_xoff),
	.xoff_count(xoff_count)
);
wire [15:0] cpu_a;
wire [7:0] mach_dbg;

rc2014_machine machine (
	.clk(clk_50),
	.reset(machine_reset),
	.profile(profile),
	.serial(serial),
	.turbo(sw_turbo),
	.mem_a(mem_a),
	.mem_rd(mem_rd),
	.mem_wr(mem_wr),
	.mem_wdata(mem_wdata),
	.mem_rdata(mem_rdata),
	.tx_a(term_rx),
	.rx_a(host_rx),
	.hold_a(term_rts || term_xoff),
	.tx_b(),
	.rx_b(1'b1),
	.img_mounted(sdc_img_mounted[5:4]),
	.img_size(sdc_img_size),
	.sdc_rd(hdf_rd),
	.sdc_wr(hdf_wr),
	.sdc_sector(hdf_sector),
	.sdc_busy(sdc_busy && hdf_own),
	.sdc_done(sdc_done && hdf_own),
	.sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe && hdf_own),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(hdf_out_data),
	.cf_led(cf_led),
	.power_reset(areset),
	.rtc_a(rtc_a),
	.rtc_do(rtc_do),
	.rtc_di(rtc_di),
	.rtc_cs(rtc_cs),
	.rtc_wr_n(rtc_wr_n),
	.cpu_a(cpu_a),
	.cpu_do(),
	.cpu_di(),
	.cpu_wr(),
	.dbg(mach_dbg)
);

wire [15:0] sram_md_o;
wire sram_md_oe;
rc2014_mem mem (
	.clk(clk_50),
	.mem_a(mem_a),
	.mem_rd(mem_rd),
	.mem_wr(mem_wr),
	.mem_wdata(mem_wdata),
	.mem_rdata(mem_rdata),
	.ld_kind(ld_kind),
	.ld_active(ld_active),
	.ld_wr(ld_wr),
	.ld_addr(ld_addr),
	.ld_data(ld_data),
	.loading(loading),
	.MA(MA),
	.MD_I(MD),
	.MD_O(sram_md_o),
	.MD_OE(sram_md_oe),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N)
);
assign MD = sram_md_oe ? sram_md_o : 16'bz;

// ------------------------------------------------------------------ the terminal

wire vt_o, vt_hs, vt_vs, vt_blank, vt_bell;
vt100_top terminal (
	.clkin(clk_50),
	.c0(clk_10),
	.resetbtn(~areset),
	.tx(term_tx),
	.rx(term_rx),
	.rts(term_rts),
	.vgao(vt_o),
	.vgah(vt_hs),
	.vgav(vt_vs),
	.vgaclk(),
	.vga_blank(vt_blank),
	.ps2k_upd(ps2_wr && !ps2_kind),
	.ps2k_dat(ps2_code),
	.audio(vt_bell)
);

// the picture: clk_50 -> clk_25 (both registered; the terminal holds a pixel for two clk_50)
reg [3:0] vt_q = 4'b1100;
always @(posedge clk_50)
	vt_q <= { vt_hs, vt_vs, vt_blank, vt_o };
reg [3:0] vt_p = 4'b1100;
always @(posedge clk_25)
	vt_p <= vt_q;

//                    Amber            Green            White
wire [23:0] fg = sw_colour == 2'd0 ? 24'hFFB700 : sw_colour == 2'd1 ? 24'h33FF33 : 24'hFFFFFF;
reg [23:0] vid_rgb = 24'd0;
reg vid_hs = 1'b0, vid_vs = 1'b0, vid_de = 1'b0;
always @(posedge clk_25) begin
	vid_rgb <= (vt_p[0] && !vt_p[1]) ? fg : 24'd0;
	vid_hs <= !vt_p[3];     // positive inside, negative to HDMI
	vid_vs <= !vt_p[2];
	vid_de <= !vt_p[1];
end

// the bitmap OSD of link v2 (kg_l2_osd_overlay): centred in de, 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_50),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_25),
	.rgb_i(vid_rgb), .hs_i(vid_hs), .vs_i(vid_vs), .de_i(vid_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the bell: a square wave of the terminal, a quarter of full scale
wire [15:0] audio = vt_bell ? 16'h1000 : 16'hF000;

kg_pcm5102 #(.DIV_BITS(3)) dac (  // bck 3.1 MHz, 97.7 kHz
	.clk(clk_50),
	.reset(areset),
	.left(audio),
	.right(audio),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// 48 kHz for HDMI: a phase accumulator on clk_50 (48000 / 50e6 * 2^20 = 1006.6), the sample held
// and taken in clk_25 on the toggle (clk_25 is synchronous to clk_50, stable for ~1000 clocks)
reg [20:0] aud_acc = 21'd0;
reg aud_tgl = 1'b0;
reg [15:0] aud_s = 16'd0;
always @(posedge clk_50) begin
	aud_acc <= { 1'b0, aud_acc[19:0] } + 21'd1007;
	if (aud_acc[20]) begin
		aud_s <= audio;
		aud_tgl <= ~aud_tgl;
	end
end

reg [1:0] aud_tgl_s = 2'b00;
reg aud_stb = 1'b0;
reg [23:0] hdmi_a = 24'd0;
always @(posedge clk_25) begin
	aud_tgl_s <= { aud_tgl_s[0], aud_tgl };
	aud_stb <= aud_tgl_s[1] ^ aud_tgl_s[0];
	if (aud_tgl_s[1] ^ aud_tgl_s[0])
		hdmi_a <= { aud_s, 8'd0 };
end

// ------------------------------------------------------------------ HDMI

reg dvi_only_p = 1'b0;
always @(posedge clk_25)
	dvi_only_p <= dvi_only;

// negative syncs
reg hdmi_hs = 1'b1, hdmi_vs = 1'b1, hdmi_de = 1'b0;
reg [23:0] hdmi_rgb = 24'd0;
always @(posedge clk_25) begin
	hdmi_hs <= ~osd_hs;
	hdmi_vs <= ~osd_vs;
	hdmi_de <= osd_de;
	hdmi_rgb <= osd_rgb;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_25),
	.sclk(clk_125),
	.sclk_n(clk_125_n),
	.reset(areset_25),
	.rgb(hdmi_rgb),
	.vsync(hdmi_vs),
	.hsync(hdmi_hs),
	.de(hdmi_de),
	.audio_en(~dvi_only_p),
	.audio_l(hdmi_a),
	.audio_r(hdmi_a),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

// ------------------------------------------------------------------ debug

// DEBUG_ADDR: the address of the Z80; DEBUG_DATA: { loading, reset, profile, serial, turbo, xoff, rts, XOFF count }
assign dbg_addr = cpu_a;
always @(posedge clk_50)
	dbg_data <= { loading, machine_reset, profile, serial, sw_turbo, term_xoff, term_rts, xoff_count };

endmodule
