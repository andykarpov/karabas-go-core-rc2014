`timescale 1ns / 1ps
`default_nettype wire
/*
 rc2014_mem.v

 The board SRAM (two 2M x 8 chips = 2M x 16, 10 ns, asynchronous; MWR_N / MRD_N [0] = MD[7:0],
 [1] = MD[15:8]) as the byte memory of rc2014_machine (22 bits = 4 MB), and the loader of the ROM
 images of the .kg (link v2 LOAD kind 0, ld_*), as bbc_mem of core-bbc.

 The machine bus is registered in rc2014_machine and goes to the pins through one level of logic;
 the read data is registered here (mem_rdata, one clock after the pins): the Z80 takes it many
 clocks later. While a LOAD of kind 0 is open (loading) the top holds the machine in reset and each
 LD_WR byte is written in 3 clocks (address and data out, /WE low, /WE high).
*/
module rc2014_mem (
	input wire clk,

	input wire [21:0] mem_a,
	input wire mem_rd,
	input wire mem_wr,
	input wire [7:0] mem_wdata,
	output reg [7:0] mem_rdata = 8'hFF,

	input wire [1:0] ld_kind,
	input wire ld_active,
	input wire ld_wr,
	input wire [31:0] ld_addr,
	input wire [7:0] ld_data,
	output wire loading,

	output wire [20:0] MA,
	input wire [15:0] MD_I,
	output wire [15:0] MD_O,
	output wire MD_OE,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N
);

assign loading = ld_active && ld_kind == 2'd0;

reg [21:0] l_addr = 22'd0;
reg [7:0] l_data = 8'd0;
reg l_setup = 1'b0;
reg l_we = 1'b0;
always @(posedge clk) begin
	l_setup <= 1'b0;
	l_we <= l_setup;
	if (ld_wr && loading) begin
		l_addr <= ld_addr[21:0];
		l_data <= ld_data;
		l_setup <= 1'b1;
	end
end

wire [21:0] a = loading ? l_addr : mem_a;
wire lane = a[0];
wire rd = !loading && mem_rd;
wire wr = loading ? l_we : mem_wr;
wire [7:0] wdata = loading ? l_data : mem_wdata;

assign MA = a[21:1];
assign MRD_N = { !(rd && lane), !(rd && !lane) };
assign MWR_N = { !(wr && lane), !(wr && !lane) };
assign MD_O = { wdata, wdata };
assign MD_OE = wr;

always @(posedge clk)
	mem_rdata <= lane ? MD_I[15:8] : MD_I[7:0];

endmodule
