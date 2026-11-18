`timescale 1ns / 1ps
`default_nettype none

/*
 rc2014_measure.v

 Ф0 fit check: the blocks we take for the RC2014 core, wired on a Z80 bus as the core will have
 them, every output on a port so that XST keeps the logic (-iobuf NO). Not a working machine:
 - T80s (Z80), the Z2 512K memory manager (ports 78-7B page selects, 7C enable) on the SRAM
   ports, the pageable ROM latch (38);
 - vdp18 TMS9918A at 98 / 99 with its 16K VRAM in block RAM;
 - jt49 YM2149 at D8 (register select) / D0 (data);
 - hdf_ata (modules) as the CF card at 10-17 (8-bit bus, upper byte unused);
 - vt_term (the pdp2011 vt10x VT100 terminal) on a serial line of the measure ports;
 - the ACIA / SIO/2 / CTC / DS1302 / 8242 are not written yet: estimated in PLAN.md.
*/

module rc2014_measure (
	input wire clk,          // the system clock (Z80 / VDP enables from it)
	input wire clk50,        // vt10x VGA timing
	input wire clk10,        // vt10x PDP-11
	input wire reset_n,
	input wire cpu_en,
	input wire vdp_en,
	input wire psg_en,

	// SRAM (ROM 512K + RAM 512K)
	output wire [19:0] sram_a,
	output wire [7:0] sram_do,
	input wire [7:0] sram_di,
	output wire sram_we_n,
	output wire sram_oe_n,

	// other I/O of the Z80 bus (the cards not written yet)
	input wire [7:0] io_di,
	input wire int_n,
	output wire [7:0] io_addr,
	output wire io_wr,
	output wire io_rd,
	output wire [7:0] cpu_do,

	// video / audio
	output wire [7:0] vdp_r,
	output wire [7:0] vdp_g,
	output wire [7:0] vdp_b,
	output wire vdp_hs,
	output wire vdp_vs,
	output wire vdp_int_n,
	output wire [9:0] psg_snd,
	output wire vt_hs,
	output wire vt_vs,
	output wire vt_fb,
	output wire vt_ht,
	output wire vt_blank,

	// terminal serial line and keyboard
	input wire vt_rx,
	output wire vt_tx,
	input wire ps2_c,
	input wire ps2_d,

	// SD image (CF)
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
	output wire cf_led
);

// Z80
wire m1_n, mreq_n, iorq_n, rd_n, wr_n;
wire [15:0] a;
wire [7:0] dout;
reg [7:0] din;

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) cpu (
	.RESET_n(reset_n), .CLK(clk), .CEN(cpu_en), .WAIT_n(1'b1), .INT_n(int_n & vdp_int_n), .NMI_n(1'b1),
	.BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
	.RFSH_n(), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(a), .DI(din), .DO(dout)
);

wire io = ~iorq_n & m1_n;
wire io_w = io & ~wr_n;
wire io_r = io & ~rd_n;

// Z2 memory manager: 4 banks of 16K, page 0-31 ROM, 32-63 RAM
reg [5:0] page [0:3];
reg paging = 1'b0;
reg rom_off = 1'b0;
reg io_w_q = 1'b0;
always @(posedge clk) begin
	io_w_q <= io_w;
	if (!reset_n) begin
		paging <= 1'b0;
		rom_off <= 1'b0;
	end else if (io_w && !io_w_q) begin
		if (a[7:2] == 6'b011110) page[a[1:0]] <= dout[5:0];
		if (a[7:0] == 8'h7C) paging <= dout[0];
		if (a[7:0] == 8'h38) rom_off <= dout[0];
	end
end

wire [5:0] pg = paging ? page[a[15:14]] : {1'b0, rom_off, 4'd0} | {4'd0, a[15:14]};
assign sram_a = {pg, a[13:0]};
assign sram_do = dout;
assign sram_we_n = mreq_n | wr_n | ~pg[5];
assign sram_oe_n = mreq_n | rd_n;

// TMS9918A, VRAM in block RAM
wire vdp_cs = io && a[7:1] == 7'b1001100;
wire [0:7] vdp_do;
wire vram_we;
wire [0:13] vram_a;
wire [0:7] vram_do;
reg [7:0] vram [0:16383];
reg [7:0] vram_q;
always @(posedge clk) begin
	if (vram_we) vram[vram_a] <= vram_do;
	vram_q <= vram[vram_a];
end

vdp18_core vdp (
	.clk_i(clk), .clk_en_10m7_i(vdp_en), .reset_n_i(reset_n),
	.csr_n_i(~(vdp_cs & ~rd_n)), .csw_n_i(~(vdp_cs & ~wr_n)), .mode_i(a[0]), .int_n_o(vdp_int_n),
	.cd_i(dout), .cd_o(vdp_do),
	.vram_we_o(vram_we), .vram_a_o(vram_a), .vram_d_o(vram_do), .vram_d_i(vram_q),
	.border_i(1'b1), .is_pal_i(1'b1), .col_o(),
	.rgb_r_o(vdp_r), .rgb_g_o(vdp_g), .rgb_b_o(vdp_b),
	.hsync_n_o(vdp_hs), .vsync_n_o(vdp_vs), .blank_n_o(), .hblank_o(), .vblank_o(), .comp_sync_n_o(),
	.clk_en_5m37_o(), .hor_active_o(), .vert_active_o()
);

// YM2149: D8 register select, D0 data
reg [3:0] psg_reg = 4'd0;
always @(posedge clk) if (io_w && a[7:0] == 8'hD8) psg_reg <= dout[3:0];
wire [7:0] psg_do;
jt49 psg (
	.rst_n(reset_n), .clk(clk), .clk_en(psg_en), .addr(psg_reg), .cs_n(~(io && a[7:0] == 8'hD0)),
	.wr_n(wr_n), .din(dout), .sel(1'b1), .dout(psg_do), .sound(psg_snd), .A(), .B(), .C(), .sample(),
	.IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out()
);

// CF at 10-17
wire cf_cs = io && a[7:3] == 5'b00010;
wire [15:0] cf_do;
hdf_ata cf (
	.clk(clk), .reset(~reset_n), .ata_reset(~reset_n), .dev0_en(1'b1), .dev(), .dev1_here(),
	.a(a[2:0]), .cs_n({1'b1, ~cf_cs}), .rd_n(rd_n), .wr_n(wr_n), .din({8'h00, dout}), .dout(cf_do),
	.img_mounted(img_mounted), .img_size(img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.led(cf_led)
);

// read mux
always @(*) begin
	if (!mreq_n) din = sram_di;
	else if (vdp_cs) din = vdp_do;
	else if (io && a[7:0] == 8'hD8) din = psg_do;
	else if (cf_cs) din = cf_do[7:0];
	else din = io_di;
end

assign io_addr = a[7:0];
assign io_wr = io_w;
assign io_rd = io_r;
assign cpu_do = dout;

// VT100 terminal
vt_term vt (
	.cpuclk(clk10), .clk50mhz(clk50), .reset(~reset_n), .rx(vt_rx), .tx(vt_tx), .ps2k_c(ps2_c), .ps2k_d(ps2_d),
	.vga_hsync(vt_hs), .vga_vsync(vt_vs), .vga_fb(vt_fb), .vga_ht(vt_ht), .vga_blank(vt_blank), .vtbell()
);

endmodule
