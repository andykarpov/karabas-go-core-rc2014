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
   00     front panel switches: read 00 (RomWBW: primary serial console, menu boot); writes dropped
   38-3F  pageable ROM toggle (Classic)
   78-7F  Z2 page registers / paging enable (RomWBW)
   80-81  ACIA (serial = 1, Mini always) or
   80-83  SIO/2 (serial = 0): A = the terminal line, B = line b
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
	output wire tx_b,            // the second channel of the SIO/2
	input wire rx_b,

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
reg [24:0] acc_cpu = 25'd0, acc_ser = 25'd0;
reg cpu_ce = 1'b0, ser_ce = 1'b0;
always @(posedge clk) begin
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
reg [7:0] io_a = 8'd0;              // the port of the last read (the strobe comes after it)
always @(posedge clk)
	if (io_rd) io_a <= a[7:0];

wire use_acia = profile == P_MINI || serial;

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
	.tx(acia_tx), .rx(rx_a)
);

rc2014_sio sio (
	.clk(clk), .reset(reset || use_acia), .ce(ser_ce),
	.a(rd_end ? io_a[1:0] : a[1:0]), .rd_stb(rd_end && sio_rd_sel), .wr_stb(wr_stb && sio_sel),
	.din(dout), .dout(sio_do), .int_n(sio_int_n), .vector(sio_vector),
	.tx_a(sio_tx_a), .rx_a(use_acia ? 1'b1 : rx_a), .tx_b(tx_b), .rx_b(rx_b), .rts_a(), .rts_b()
);

assign tx_a = use_acia ? acia_tx : sio_tx_a;
assign int_n = use_acia ? !acia_irq : sio_int_n;

// ---------------------------------------------------------------- read data

always @(posedge clk) begin
	if (!mreq_n)
		din <= mem_rdata;
	else if (inta)
		din <= use_acia ? 8'hFF : sio_vector;
	else if (io) begin
		if (a[7:0] == 8'h00)
			din <= 8'h00;
		else if (acia_sel)
			din <= acia_do;
		else if (sio_sel)
			din <= sio_do;
		else
			din <= 8'hFF;
	end
end

assign dbg = { profile, use_acia, paging, rom_in, !int_n, !mreq_n, io };

endmodule
