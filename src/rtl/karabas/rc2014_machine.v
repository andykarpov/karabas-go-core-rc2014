`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_machine.v

 The RC2014 on the board: a Z80 (T80s) with the memory cards of the three profiles and the serial
 cards; the memory itself is outside (the board SRAM, rc2014_mem), as a byte bus of 22 bits.

 Clocks: everything on clk (50 MHz) with clock enables from phase accumulators: the Z80 at
 7.3728 MHz (turbo: 14.7456 MHz) and the serial clock of the ACIA / SIO at 7.3728 MHz (the RC2014
 clock: /64 = 115200 bps), on average exact, each enable one clock of clk.

 Profiles (the memory map; the ROM images are loaded from the .kg to the addresses below):
   0 RomWBW 512K: the 512K ROM + 512K RAM module (Z2): ports 78-7B the page (0-31 ROM, 32-63 RAM)
     of the 16K windows 0000 / 4000 / 8000 / C000, port 7C bit 0 paging on; paging off (reset):
     ROM page 0 in every window. Byte address { page, a[13:0] } = 0x000000-0x0FFFFF (ROM image
     romwbw.rom at 0x000000).
   1 Classic: the pageable ROM module + 64K RAM: the ROM (16K window 0000-3FFF, ROM image bank 2 of
     the 64K image at 0x100000 = 24886009: SCM) until a write to 38-3F toggles it out (and in again);
     reset = ROM in. RAM 64K at 0x120000.
   2 Mini: ROM 8K at 0000-7FFF (mirrored; bank 0 of the image at 0x110000 = R0000009: BASIC for the
     ACIA), RAM 32K at 8000-FFFF (0x120000 + a).
 ROM is never written (the write is dropped).

 I/O (A7..A0, the RC2014 decodes 8 bits):
   00     front panel switches: read fp_sw (RomWBW: 00 the serial console, 80 SW_CRT the console on
          the TMS9918; menu boot); writes dropped
   01, 02 joystick module: joystick 1 / 2, active low (0 up, 1 down, 2 left, 3 right, 4 fire 1,
          5 fire 2)
   10-17  CF module (rc2014_cf, 8-bit IDE)
   60, 64 8242 PS/2 keyboard controller (rc2014_kbd8242, RomWBW TMSMODE_MSXKBD), only with kbd_en
   98, 99 TMS9918A (vdp18; VRAM 16K in block RAM), its frame interrupt on INT_n
   D8, D0 YM2149 (jt49, Ed Brindley module: D8 write register select / read data, D0 write data;
          3.579545 MHz / 2); port A in = the joystick of port B bit 6 (MSX style, for MSX8)
   C0     DS1302 RTC (rc2014_ds1302)
   38-3F  pageable ROM toggle (Classic)
   78-7F  Z2 page registers / paging enable (RomWBW)
   80-81  ACIA (serial = 1, Mini always) or
   80-83  SIO/2 (serial = 0): A = the terminal line, B = the USB serial port (a byte stream)
   other  read FF (an empty bus)
 The serial card of the terminal line is the ACIA for the Mini profile (its BASIC knows the ACIA
 only), else by `serial` (0 SIO/2, 1 ACIA).

 Interrupts: the ACIA IRQ / SIO INT on INT_n (IM1 of RomWBW); an IM2 acknowledge reads the SIO
 vector. NMI unused.

 The memory bus (registered toward the SRAM, the read data comes back registered: the Z80 reads it
 two Z80 clocks after MREQ, many clocks of clk later):
   mem_a byte address, mem_rd / mem_wr levels (mem_wr only for RAM), mem_wdata.
*/
module rc2014_machine (
	input wire clk,
	input wire reset,            // the machine reset (power on, OSD Reset, profile change, ROM load)
	input wire [1:0] profile,
	input wire serial,           // 0 SIO/2, 1 ACIA (Classic / RomWBW)
	input wire turbo,            // Z80 at 14.7456 MHz

	output reg [21:0] mem_a = 22'd0,
	output reg mem_rd = 1'b0,
	output reg mem_wr = 1'b0,
	output reg [7:0] mem_wdata = 8'd0,
	input wire [7:0] mem_rdata,

	output wire tx_a,            // the terminal line
	input wire rx_a,
	input wire hold_a,           // the terminal asks to wait (its RTS): the ACIA / SIO A start no new frame
	// the second channel of the SIO/2: bytes of the USB serial port (kg_mcu2 port 0)
	input wire [7:0] rxb_data,
	input wire rxb_wr,
	output wire rxb_ready,
	output wire [7:0] txb_data,
	output wire txb_wr,
	input wire txb_full,

	input wire [7:0] fp_sw,      // the front panel switches (port 00)
	input wire [5:0] joy1,       // the joysticks: 0 up, 1 down, 2 left, 3 right, 4 fire 1, 5 fire 2 (1 = pressed)
	input wire [5:0] joy2,
	input wire [7:0] kbd_code,   // the keyboard of the 8242: PS/2 set 2 bytes
	input wire kbd_wr,
	input wire kbd_en,           // the 8242 is on the bus (Console = TMS9918); off: 60 / 64 read FF

	// the TMS9918 picture (msx_video of the top): the pixel enable, the active area, the colour
	output wire vdp_ce_pix,
	output wire vdp_hor_active,
	output wire vdp_vert_active,
	output wire [3:0] vdp_col,
	output wire [9:0] psg_sound, // the YM2149, its three channels mixed

	// the CF module (rc2014_cf: hdf_ata on the file mounter, slot 4 = device 0)
	input wire [1:0] img_mounted,
	input wire [63:0] img_size,
	output wire [1:0] sdc_rd,
	output wire [1:0] sdc_wr,
	output wire [31:0] sdc_sector,
	input wire sdc_busy,
	input wire sdc_done,
	input wire sdc_error,
	input wire sdc_byte_in_strobe,
	input wire [8:0] sdc_byte_addr,
	input wire [7:0] sdc_byte_in_data,
	output wire [7:0] sdc_byte_out_data,
	output wire cf_led,
	input wire power_reset,      // the power-on reset (the CF forgets its image only then)
	input wire cf_card,          // 1: the CF card of the board (its IDE bus) instead of the image

	// the IDE bus of the board (a real CF card in 8-bit mode)
	output reg [2:0] ide_a = 3'd0,
	output reg ide_cs0_n = 1'b1,
	output reg ide_rd_n = 1'b1,
	output reg ide_wr_n = 1'b1,
	output reg ide_rst_n = 1'b0,
	output reg [7:0] ide_dout = 8'd0,
	output reg ide_oe = 1'b0,
	input wire [7:0] ide_din,

	// the DS1302 (rc2014_ds1302) on the RTC RAM of kg_mcu2 (rtc_mode 1, DS1307)
	output wire [7:0] rtc_a,
	input wire [7:0] rtc_do,
	output wire [7:0] rtc_di,
	output wire rtc_cs,
	output wire rtc_wr_n,

	output wire [15:0] cpu_a,
	output wire [7:0] cpu_do,        // the simulation: the bus of the Z80
	output wire [7:0] cpu_di,
	output wire cpu_wr,
	output wire [7:0] dbg
);

localparam P_ROMWBW = 2'd0, P_CLASSIC = 2'd1, P_MINI = 2'd2;

// ---------------------------------------------------------------- clock enables

// 7.3728 / 50 * 2^24 = 2473901.4
localparam [23:0] INC = 24'd2473901;
reg [24:0] acc_cpu = 25'd0, acc_ser = 25'd0, acc_vdp = 25'd0, acc_psg = 25'd0;
reg cpu_ce = 1'b0, ser_ce = 1'b0, vdp_ce = 1'b0, psg_ce = 1'b0;
// the TMS9918: 10.738635 MHz; the YM2149: 3.579545 MHz (its divider by 2: 1.7897725 MHz, RomWBW AY_CLK)
localparam [23:0] INC_VDP = 24'd3603288, INC_PSG = 24'd1201096;
always @(posedge clk) begin
	acc_vdp <= { 1'b0, acc_vdp[23:0] } + { 1'b0, INC_VDP };
	vdp_ce <= acc_vdp[24];
	acc_psg <= { 1'b0, acc_psg[23:0] } + { 1'b0, INC_PSG };
	psg_ce <= acc_psg[24];
	acc_cpu <= { 1'b0, acc_cpu[23:0] } + (turbo ? { INC, 1'b0 } : { 1'b0, INC });
	cpu_ce <= acc_cpu[24];
	acc_ser <= { 1'b0, acc_ser[23:0] } + { 1'b0, INC };
	ser_ce <= acc_ser[24];
end

// ---------------------------------------------------------------- Z80

wire m1_n, mreq_n, iorq_n, rd_n, wr_n;
wire [15:0] a;
wire [7:0] dout;
reg [7:0] din = 8'hFF;
wire int_n;

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) cpu (
	.RESET_n(!reset), .CLK(clk), .CEN(cpu_ce), .WAIT_n(1'b1), .INT_n(int_n), .NMI_n(1'b1),
	.BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
	.RFSH_n(), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(a), .DI(din), .DO(dout)
);
assign cpu_a = a;
assign cpu_do = dout;
assign cpu_di = din;
assign cpu_wr = !wr_n;

// ---------------------------------------------------------------- I/O strobes

wire io = !iorq_n && m1_n;
wire io_rd = io && !rd_n;
wire io_wr = io && !wr_n;
wire inta = !iorq_n && !m1_n;
reg io_rd_q = 1'b0, io_wr_q = 1'b0;
always @(posedge clk) begin
	io_rd_q <= io_rd;
	io_wr_q <= io_wr;
end
wire rd_end = io_rd_q && !io_rd;   // the end of a read (side effects of the read)
wire wr_stb = io_wr && !io_wr_q;    // the start of a write (DO is valid from T1)
wire wr_end = io_wr_q && !io_wr;    // the end of a write
reg [7:0] io_a = 8'd0;              // the port of the last read (the strobe comes after it)
always @(posedge clk)
	if (io_rd) io_a <= a[7:0];

wire use_acia = profile == P_MINI || serial;

reg [1:0] hold_s = 2'b00;
always @(posedge clk)
	hold_s <= { hold_s[0], hold_a };

// ---------------------------------------------------------------- memory cards

reg [5:0] page [0:3];
reg paging = 1'b0;
reg rom_in = 1'b1;
initial begin
	page[0] = 6'd0; page[1] = 6'd0; page[2] = 6'd0; page[3] = 6'd0;
end

always @(posedge clk) begin
	if (reset) begin
		paging <= 1'b0;
		rom_in <= 1'b1;
		page[0] <= 6'd0; page[1] <= 6'd0; page[2] <= 6'd0; page[3] <= 6'd0;
	end
	else if (wr_stb) begin
		if (profile == P_ROMWBW && a[7:2] == 6'b011110) page[a[1:0]] <= dout[5:0];
		if (profile == P_ROMWBW && a[7:2] == 6'b011111) paging <= dout[0];
		if (profile == P_CLASSIC && a[7:3] == 5'b00111) rom_in <= !rom_in;
	end
end

reg [21:0] phys;
reg is_rom;
always @* begin
	case (profile)
		P_ROMWBW: begin
			phys = { 2'b00, paging ? page[a[15:14]] : 6'd0, a[13:0] };
			is_rom = !paging || !page[a[15:14]][5];
		end
		P_CLASSIC: begin
			is_rom = rom_in && a[15:14] == 2'b00;
			phys = is_rom ? { 8'h10, 2'b01, a[13:0] } : { 6'h12, a };
		end
		default: begin
			is_rom = !a[15];
			phys = is_rom ? { 9'h088, a[12:0] } : { 6'h12, a };   // Mini ROM: 0x110000 + a[12:0]
		end
	endcase
end

always @(posedge clk) begin
	mem_a <= phys;
	mem_rd <= !mreq_n && !rd_n;
	mem_wr <= !mreq_n && !wr_n && !is_rom && !reset;
	mem_wdata <= dout;
end

// ---------------------------------------------------------------- serial cards

wire acia_sel = use_acia && a[7:1] == 7'b1000000;
wire sio_sel = !use_acia && a[7:2] == 6'b100000;
wire acia_rd_sel = use_acia && io_a[7:1] == 7'b1000000;
wire sio_rd_sel = !use_acia && io_a[7:2] == 6'b100000;

wire [7:0] acia_do, sio_do, sio_vector;
wire acia_irq, sio_int_n;
wire acia_tx, sio_tx_a;

rc2014_acia acia (
	.clk(clk), .reset(reset || !use_acia), .ce(ser_ce),
	.a0(rd_end ? io_a[0] : a[0]), .rd_stb(rd_end && acia_rd_sel), .wr_stb(wr_stb && acia_sel),
	.din(dout), .dout(acia_do), .irq(acia_irq),
	.tx(acia_tx), .rx(rx_a), .hold(hold_s[1])
);

rc2014_sio sio (
	.clk(clk), .reset(reset || use_acia), .ce(ser_ce),
	.a(rd_end ? io_a[1:0] : a[1:0]), .rd_stb(rd_end && sio_rd_sel), .wr_stb(wr_stb && sio_sel),
	.din(dout), .dout(sio_do), .int_n(sio_int_n), .vector(sio_vector),
	.tx_a(sio_tx_a), .rx_a(use_acia ? 1'b1 : rx_a),
	.rxb_data(rxb_data), .rxb_wr(rxb_wr && !use_acia), .rxb_ready(sio_rxb_ready), .txb_data(txb_data), .txb_wr(sio_txb_wr), .txb_full(txb_full),
	.rts_a(), .rts_b(), .hold_a(hold_s[1])
);
wire sio_rxb_ready, sio_txb_wr;
assign rxb_ready = sio_rxb_ready && !use_acia;
assign txb_wr = sio_txb_wr && !use_acia;

assign tx_a = use_acia ? acia_tx : sio_tx_a;
assign int_n = (use_acia ? !acia_irq : sio_int_n) && vdp_int_n;

// ---------------------------------------------------------------- TMS9918A, YM2149, 8242, joysticks

wire vdp_sel = a[7:1] == 7'b1001100;          // 98 / 99
wire [7:0] vdp_do;
wire vdp_int_n;
wire [13:0] vram_a;
wire [7:0] vram_do, vram_di;
wire vram_we;
kg_spram #(.DW(8), .AW(14), .WRITE_FIRST(1)) vram (
	.clk(clk), .en(1'b1), .we(vram_we), .addr(vram_a), .din(vram_do), .dout(vram_di)
);
vdp18_core #(.compat_rgb_g(0)) vdp (
	.clk_i(clk), .clk_en_10m7_i(vdp_ce), .reset_n_i(!reset),
	.csr_n_i(!(io_rd && vdp_sel)), .csw_n_i(!(io_wr && vdp_sel)), .mode_i(a[0]),
	.int_n_o(vdp_int_n), .cd_i(dout), .cd_o(vdp_do),
	.vram_we_o(vram_we), .vram_a_o(vram_a), .vram_d_o(vram_do), .vram_d_i(vram_di),
	.border_i(1'b1), .is_pal_i(1'b0), .col_o(vdp_col),
	.rgb_r_o(), .rgb_g_o(), .rgb_b_o(), .hsync_n_o(), .vsync_n_o(), .blank_n_o(),
	.hblank_o(), .vblank_o(), .comp_sync_n_o(),
	.clk_en_5m37_o(vdp_ce_pix), .hor_active_o(vdp_hor_active), .vert_active_o(vdp_vert_active)
);

// the YM2149: D8 write = register select (BDIR BC1 11), D0 write = data (10), D8 read = data (01)
wire psg_rd = io_rd && a[7:0] == 8'hD8;
wire psg_wr_a = io_wr && a[7:0] == 8'hD8;
wire psg_wr_d = io_wr && a[7:0] == 8'hD0;
wire [7:0] psg_do, psg_iob;
// MSX style joystick on port A (for MSX8): port B bit 6 picks joystick 1 / 2; 0 up 1 down 2 left
// 3 right 4 trigger A 5 trigger B, active low, bits 6 / 7 high
wire [5:0] psg_joy = psg_iob[6] ? joy2 : joy1;
jt49_bus psg (
	.rst_n(!reset), .clk(clk), .clk_en(psg_ce),
	.bdir(psg_wr_a || psg_wr_d), .bc1(psg_wr_a || psg_rd), .din(dout), .sel(1'b0),
	.dout(psg_do), .sound(psg_sound), .A(), .B(), .C(), .sample(),
	.IOA_in({ 2'b11, ~psg_joy }), .IOA_out(), .IOB_in(8'hFF), .IOB_out(psg_iob)
);

// only with the TMS console: else Fuzix finds the keyboard and moves its console to the TMS
wire kbd_sel = kbd_en && (a[7:0] == 8'h60 || a[7:0] == 8'h64);
wire kbd_rd_sel = kbd_en && (io_a == 8'h60 || io_a == 8'h64);
wire [7:0] kbd_do;
rc2014_kbd8242 kbd (
	.clk(clk), .reset(reset),
	.a2(rd_end ? io_a[2] : a[2]), .rd_stb(rd_end && kbd_rd_sel), .wr_stb(wr_stb && kbd_sel),
	.din(dout), .dout(kbd_do), .kbd_code(kbd_code), .kbd_wr(kbd_wr)
);

// ---------------------------------------------------------------- CF, DS1302

wire [7:0] cf_do;
wire cf_sel;
rc2014_cf cf (
	.clk(clk), .reset(power_reset), .bus_reset(reset),
	.a(rd_end ? io_a : a[7:0]), .io_rd(io_rd && !cf_card), .io_wr(io_wr && !cf_card), .rd_end(rd_end && !cf_card), .wr_end(wr_end && !cf_card),
	.din(dout), .dout(cf_do), .sel(cf_sel),
	.img_mounted(img_mounted), .img_size(img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.led(cf_led)
);

// a real CF card (cf_card): the bus of the board, registered. CS / address follow the port decode
// (the Z80 holds A over the whole cycle: hold after the strobe), the strobes one clock after the
// I/O cycle, the write data held two clocks after the write strobe
reg [1:0] ide_wr_q = 2'b00;
reg [7:0] ide_q = 8'hFF;
always @(posedge clk) begin
	ide_a <= a[2:0];
	ide_cs0_n <= !(cf_card && a[7:3] == 5'b00010);
	ide_rd_n <= !(cf_card && io_rd && a[7:3] == 5'b00010);
	ide_wr_n <= !(cf_card && io_wr && a[7:3] == 5'b00010);
	ide_wr_q <= { ide_wr_q[0], !ide_wr_n };
	ide_oe <= cf_card && ((io_wr && a[7:3] == 5'b00010) || !ide_wr_n || ide_wr_q[0]);
	if (io_wr) ide_dout <= dout;
	ide_rst_n <= !reset;
	ide_q <= ide_din;
end

wire [7:0] rtc_port;
rc2014_ds1302 ds1302 (
	.clk(clk), .reset(reset),
	.wr_stb(wr_stb && a[7:0] == 8'hC0), .din(dout), .dout(rtc_port),
	.rtc_a(rtc_a), .rtc_do(rtc_do), .rtc_di(rtc_di), .rtc_cs(rtc_cs), .rtc_wr_n(rtc_wr_n)
);

// ---------------------------------------------------------------- read data

always @(posedge clk) begin
	if (!mreq_n)
		din <= mem_rdata;
	else if (inta)
		din <= use_acia ? 8'hFF : sio_vector;
	else if (io) begin
		if (a[7:0] == 8'h00)
			din <= fp_sw;
		else if (a[7:0] == 8'h01)
			din <= { 2'b11, ~joy1 };
		else if (a[7:0] == 8'h02)
			din <= { 2'b11, ~joy2 };
		else if (vdp_sel)
			din <= vdp_do;
		else if (a[7:0] == 8'hD8)
			din <= psg_do;
		else if (kbd_sel)
			din <= kbd_do;
		else if (acia_sel)
			din <= acia_do;
		else if (sio_sel)
			din <= sio_do;
		else if (cf_sel)
			din <= cf_card ? ide_q : cf_do;
		else if (a[7:0] == 8'hC0)
			din <= rtc_port;
		else
			din <= 8'hFF;
	end
end

assign dbg = { profile, use_acia, paging, rom_in, !int_n, !mreq_n, io };

endmodule
