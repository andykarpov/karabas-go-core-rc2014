`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_cf.v

 The RC2014 Compact Flash module (IDE registers at 10-17, 8-bit bus) on hdf_ata of
 karabas-go-modules (an ATA disk on an SD image of the file mounter, slot 4 = device 0).

 The card of the module has only D7..D0 on the bus: the software puts it into 8-bit mode
 (SET FEATURES 01h, RomWBW IDEMODE_RC, the RC2014 CP/M BIOS). Here the data register is always 8
 bits wide: hdf_ata keeps a 16-bit data register (the first byte of a sector word = D7..D0), so
 - read, even byte: a 16-bit read of hdf_ata, the low byte to the CPU, the high byte kept;
   odd byte: the kept byte, hdf_ata is not touched;
 - write, even byte: kept; odd byte: a 16-bit write of { this byte, kept byte }.
 A write of the command register starts again at the even byte. The other registers are D7..D0.

 Bus: io_rd / io_wr are levels (the I/O read / write of the Z80, port in a), rd_end / wr_end one
 clock after them; hdf_ata does a register access at the end of its strobe.
*/
module rc2014_cf (
	input wire clk,
	input wire reset,          // power on
	input wire bus_reset,      // the machine reset

	input wire [7:0] a,
	input wire io_rd,
	input wire io_wr,
	input wire rd_end,
	input wire wr_end,
	input wire [7:0] din,
	output wire [7:0] dout,
	output wire sel,           // a is 10-17

	// the file mounter (kg_mcu2 SDC_*), hdf_ata slots 4 / 5
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
	output wire led
);

assign sel = a[7:3] == 5'b00010;
wire data_reg = a[2:0] == 3'd0;

reg odd = 1'b0;            // the next data register access is the high byte
reg [7:0] hi = 8'd0;       // read: the high byte of the word; write: the low byte waiting
reg sel_q = 1'b0, data_q = 1'b0;
always @(posedge clk) begin
	if (io_rd || io_wr) begin
		sel_q <= sel;
		data_q <= data_reg;
	end
end

wire [15:0] hdf_dout;
wire pass_rd = io_rd && sel && !(data_reg && odd);
wire pass_wr = io_wr && sel && !(data_reg && !odd);

always @(posedge clk) begin
	if (reset || bus_reset)
		odd <= 1'b0;
	else begin
		// read, even byte: keep the high byte while the strobe is on (hdf_ata moves on at its end)
		if (io_rd && sel && data_reg && !odd)
			hi <= hdf_dout[15:8];
		if (io_wr && sel && data_reg && !odd)
			hi <= din;
		if ((rd_end || wr_end) && sel_q && data_q)
			odd <= !odd;
		if (io_wr && sel && a[2:0] == 3'd7)
			odd <= 1'b0;
	end
end

assign dout = (data_reg && odd) ? hi : hdf_dout[7:0];

hdf_ata #(.ENABLE_RDB(0)) ata (
	.clk(clk), .reset(reset), .ata_reset(bus_reset), .dev0_en(1'b1), .dev(), .dev1_here(),
	.a(a[2:0]), .cs_n({ 1'b1, !sel }),
	.rd_n(!pass_rd), .wr_n(!pass_wr),
	.din(data_reg ? { din, hi } : { 8'h00, din }), .dout(hdf_dout),
	.img_mounted(img_mounted), .img_size(img_size),
	.sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.led(led)
);

endmodule
