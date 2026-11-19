`timescale 1ns / 1ps
`default_nettype wire

/*
 RC2014 core for Karabas Go (VGA, PCM5102). Made by tools/mktops.py from
 karabas_minig_top.v (do not edit: change that one and run it): the same except the pins, the MCU
 link (MCU_SCK not on a clock pin) and the video: 24 bit RGB to the VGA DAC with its pixel clock on
 V_CLK (clk_25), the FT812 off that bus (FT_OE_N = 1), no HDMI. The floppy connector is not used
 (its outputs 0).
 A Z80 RC2014 (rc2014_machine: the memory
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

 TMS9918A (Console = TMS9918): its picture through the frame buffer of msx_video (256 x 192 as
 512 x 384 in 640 x 480 at 60 Hz, the same timing as the terminal), the keyboard to the 8242 of
 the machine instead of the terminal, and the front panel port 00 reads 80 (SW_CRT: RomWBW moves
 its console to the TMS at boot). A change of Console resets the machine.

 Wi-Fi (OSD, Off by default): the ESP module of the board (its AT firmware, 115200, CTS) on the
 second SIO/2, channel A (84-87: RomWBW SIO2, Fuzix tty3).

 USB serial port (kg_mcu2 port 0, the clean CDC "Karabas core serial" of the firmware): channel B
 of the SIO/2, byte for byte (RomWBW unit SIO1: XM, a second console).

 Joysticks: the two pads of the MCU on the joystick module (ports 01 / 02) and on the YM2149 port A
 (MSX style).

 Audio: the YM2149 (both channels), the SN76489 module (its left / right chips) and the bell of the
 terminal to the PCM5102 and HDMI (48 kHz), stereo.

 Soft switches (the index of the item in the osd of core.json):
   5 CF source (Image / Card: the CF card of the board)
   0 Profile (RomWBW 512K / Classic / Mini)   1 Serial (SIO/2 / ACIA: Classic and RomWBW; Mini is
   always ACIA)   6 Console (Terminal / TMS9918)   7 Wi-Fi (Off / On)   2 CPU (7.37 / 14.75 MHz)
   3 Colour (Amber / Green / White)   4 Reset
 A change of Profile, Serial, Console or CF source (or the Reset item, or a ROM load) resets the
 machine.
*/

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

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

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] INT of link v2 (firmware IO1, GPIO2), [1] unused (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

// the IDE bus of the board (WA / WCS_N / WRD_N / WWR_N / WRESET_N / WD): a real CF card, 8-bit
// (rc2014_machine, OSD CF source = Card)
wire [2:0] ide_a;
wire ide_cs0_n, ide_rd_n, ide_wr_n, ide_rst_n, ide_oe;
wire [7:0] ide_dout;
assign WA = ide_a;
assign WCS_N = { 1'b1, ide_cs0_n };
assign WRD_N = ide_rd_n;
assign WWR_N = ide_wr_n;
assign WRESET_N = ide_rst_n;
assign WD = { 8'bz, ide_oe ? ide_dout : 8'bz };

// the ESP module (UART_*): the second SIO/2 of the machine, channel A, with OSD Wi-Fi = On; UART_CTS
// low = the module may send (the RTS of the channel). Off: the line is not connected (CTS high, the
// receiver idle): an AT module echoes all it gets, and Fuzix echoes back on its tty3 (closed or
// not): the two keep the line busy at full speed and Fuzix crawls
wire esp_tx, esp_rts;
wire sw_wifi;        // OSD Wi-Fi (below)
assign UART_RX = 1'bz;
assign UART_TX = esp_tx;
assign UART_CTS = !(esp_rts && sw_wifi);

assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign BEEPER = 1'b0;
assign DAC_MUTE = 1'b1;    // soft mute of the PCM5102: 1 = sound on

// the floppy connector is not used: its outputs 0 (the board inverts them: high = active)
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b0;
assign MIDI_TX = 1'b1;
assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_CLK = 1'b0;      // the SAM2695 synth: held in reset, not used
assign MIDI_RESET_N = 1'b0;
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

// the flash chip (the SDRAM /CS is hard wired on Go): not selected
assign FLASH_CS_N = 1'b1;
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

// the pixel clock of the VGA DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_25), .C1(~clk_25), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK is not on a clock pin before rev.G (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;

// karabas: MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9 (IO1 of the firmware)
assign MCU_SPI_IO[1] = 1'bz;

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

// the USB serial port (port 0) <-> SIO/2 channel B
wire [31:0] port_out_data;
wire [3:0] port_out_wr, port_in_full;
wire ser_rx_ready, ser_tx_wr;
wire [7:0] ser_tx_data;

// the pads: 1 up, 2 down, 3 left, 4 right, 6 A, 7 B -> { B, A, right, left, down, up }
wire [15:0] joy_l, joy_r;
wire [5:0] joy1 = { joy_l[7], joy_l[6], joy_l[4], joy_l[3], joy_l[2], joy_l[1] };
wire [5:0] joy2 = { joy_r[7], joy_r[6], joy_r[4], joy_r[3], joy_r[2], joy_r[1] };

kg_mcu2 #(
	.SW_N(8),
	.CS_FILTER(3),
	.CAPS(16'h0000),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),
	.IMG_OUT_LATENCY(3), // the address register of kg_l2_img, the buffer RAM of hdf_ata, its output register
	.ENABLE_RTC(1),      // the DS1302 of the machine on the clock of the board (rtc_mode 1)
	.ENABLE_AUX(1),      // DEBUG_*: the state of the core (AT+KARABAS=debug:1, kg_board.py log)
	.ENABLE_FT(1),
	.ENABLE_SD2(0),
	.ENABLE_PORTS(4'b0001) // port 0: the USB serial port (SIO/2 channel B)
) mcu (
	.CLK(clk_50),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(1'b1),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(),
	.PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(joy_l), .JOY_R(joy_r), .JOY_WR(),
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
	.PORT_OUT_DATA(port_out_data), .PORT_OUT_WR(port_out_wr), .PORT_OUT_READY({ 3'b111, ser_rx_ready }),
	.PORT_IN_DATA({ 24'd0, ser_tx_data }), .PORT_IN_WR({ 3'b000, ser_tx_wr }),
	.PORT_CFG(128'd0), .PORT_IN_FULL(port_in_full), .PORT_STAT(), .PORT_STAT_WR(),
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
wire sw_cf_card = sw[5*8];
wire sw_tms = sw[6*8];
assign sw_wifi = sw[7*8];

wire loading;

// the profile and the serial card are taken while the machine is in reset; a change of either (or
// the Reset item, or a ROM load) resets the machine for about 1.3 ms (16 bits of clk_50)
reg [1:0] profile = 2'd0;
reg serial = 1'b0;
reg cf_card = 1'b0;
reg tms = 1'b0;
reg [15:0] rst_cnt = 16'd0;
reg machine_reset = 1'b1;
always @(posedge clk_50) begin
	if (areset || loading || sw_reset || sw_profile != profile || sw_serial != serial || sw_cf_card != cf_card || sw_tms != tms) begin
		rst_cnt <= 16'd0;
		profile <= sw_profile == 2'd3 ? 2'd0 : sw_profile;
		serial <= sw_serial;
		cf_card <= sw_cf_card;
		tms <= sw_tms;
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
wire vdp_ce_pix, vdp_hor_active, vdp_vert_active;
wire [3:0] vdp_col;
wire [9:0] psg_sound;
wire signed [10:0] sn_left, sn_right;

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
	.rxb_data(port_out_data[7:0]),
	.rxb_wr(port_out_wr[0]),
	.rxb_ready(ser_rx_ready),
	.txb_data(ser_tx_data),
	.txb_wr(ser_tx_wr),
	.txb_full(port_in_full[0]),
	.esp_tx(esp_tx),
	.esp_rx(sw_wifi ? UART_RX : 1'b1),
	.esp_rts(esp_rts),
	.fp_sw(tms ? 8'h80 : 8'h00),
	.joy1(joy1),
	.joy2(joy2),
	.kbd_code(ps2_code),
	.kbd_wr(ps2_wr && !ps2_kind && tms),
	.kbd_en(tms),
	.vdp_ce_pix(vdp_ce_pix),
	.vdp_hor_active(vdp_hor_active),
	.vdp_vert_active(vdp_vert_active),
	.vdp_col(vdp_col),
	.psg_sound(psg_sound),
	.sn_left(sn_left),
	.sn_right(sn_right),
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
	.cf_card(cf_card),
	.ide_a(ide_a),
	.ide_cs0_n(ide_cs0_n),
	.ide_rd_n(ide_rd_n),
	.ide_wr_n(ide_wr_n),
	.ide_rst_n(ide_rst_n),
	.ide_dout(ide_dout),
	.ide_oe(ide_oe),
	.ide_din(WD[7:0]),
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
	.ps2k_upd(ps2_wr && !ps2_kind && !tms),
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
// the TMS9918 picture (its own 640 x 480 counters on clk_25)
wire [23:0] tms_rgb;
wire tms_hs, tms_vs, tms_de;
msx_video tms_video (
	.clk(clk_50), .ce_pix(vdp_ce_pix), .hor_active(vdp_hor_active), .vert_active(vdp_vert_active), .col(vdp_col),
	.clk_vga(clk_25), .rgb(tms_rgb), .hs(tms_hs), .vs(tms_vs), .de(tms_de)
);
reg tms_p = 1'b0;
always @(posedge clk_25)
	tms_p <= tms;

always @(posedge clk_25) begin
	if (tms_p) begin
		vid_rgb <= tms_rgb;
		vid_hs <= tms_hs;
		vid_vs <= tms_vs;
		vid_de <= tms_de;
	end
	else begin
		vid_rgb <= (vt_p[0] && !vt_p[1]) ? fg : 24'd0;
		vid_hs <= !vt_p[3];     // positive inside, negative to HDMI
		vid_vs <= !vt_p[2];
		vid_de <= !vt_p[1];
	end
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

// the YM2149 (10 bits unsigned, three channels mixed) around 0 at half of full scale, the SN76489
// (11 bits signed each, x8: a quarter of full scale) and the bell of the terminal (a square wave,
// a sixteenth of full scale); the sum stays inside 16 bits
reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
wire [15:0] ay_bell = ({ 1'b0, psg_sound, 5'd0 } - 16'h4000) + (vt_bell ? 16'h0800 : 16'hF800);
always @(posedge clk_50) begin
	audio_l <= ay_bell + { {2{sn_left[10]}}, sn_left, 3'd0 };
	audio_r <= ay_bell + { {2{sn_right[10]}}, sn_right, 3'd0 };
end

kg_pcm5102 #(.DIV_BITS(3)) dac (  // bck 3.1 MHz, 97.7 kHz
	.clk(clk_50),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);

// ------------------------------------------------------------------ VGA

// 640 x 480 at 60 Hz: negative syncs as on HDMI, black outside de (the DAC has no blank input); the
// OSD output is registered with them
reg vga_hs_o = 1'b1, vga_vs_o = 1'b1;
reg [23:0] vga_rgb_o = 24'd0;
always @(posedge clk_25) begin
	vga_hs_o <= ~osd_hs;
	vga_vs_o <= ~osd_vs;
	vga_rgb_o <= osd_de ? osd_rgb : 24'd0;
end
assign VGA_R = vga_rgb_o[23:16];
assign VGA_G = vga_rgb_o[15:8];
assign VGA_B = vga_rgb_o[7:0];
assign VGA_HS = vga_hs_o;
assign VGA_VS = vga_vs_o;

// ------------------------------------------------------------------ debug

// DEBUG_ADDR: the address of the Z80; DEBUG_DATA: { loading, reset, profile, serial, turbo, xoff, rts, XOFF count }
assign dbg_addr = cpu_a;
always @(posedge clk_50)
	dbg_data <= { loading, machine_reset, profile, serial, sw_turbo, term_xoff, term_rts, xoff_count };

endmodule
