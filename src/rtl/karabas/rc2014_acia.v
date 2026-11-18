`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_acia.v

 The MC68B50 ACIA of the RC2014 Serial I/O module (80 control / status, 81 data; the module
 decodes A0 only, 80-BF on the card, the machine passes 80-81 here), clocked by the 7.3728 MHz
 serial clock (ce): /64 = 115200 bps, /16 = 460800.

 Registers (as the data sheet; the parts the RC2014 software uses):
   CR (write 80): 1:0 counter divide (00 /1, 01 /16, 10 /64, 11 master reset), 4:2 word select
     (taken as 8 data bits, no parity, any stop: the line engines are 8N1), 6:5 transmit control
     (01 = transmit interrupt enabled, 11 = break: TX held low), 7 receive interrupt enable.
   SR (read 80): 0 RDRF, 1 TDRE, 2 /DCD (0: the module ties DCD active), 3 /CTS (0), 4 FE, 5 OVRN,
     6 PE (0), 7 IRQ.
   TDR (write 81), RDR (read 81: clears RDRF, OVRN; FE follows the next character).
 After a master reset (and at power on) the ACIA waits for a CR write without the reset code;
 TDRE is 1.

 Bus: rd_stb / wr_stb are one clock each; rd_stb at the END of the CPU read (the read data stays
 valid while the CPU reads), wr_stb with the write data valid.
*/
module rc2014_acia (
	input wire clk,
	input wire reset,
	input wire ce,

	input wire a0,
	input wire rd_stb,
	input wire wr_stb,
	input wire [7:0] din,
	output wire [7:0] dout,
	output wire irq,

	output wire tx,
	input wire rx
);

reg [7:0] cr = 8'h03;
reg mreset = 1'b1;
reg [7:0] rdr = 8'd0;
reg rdrf = 1'b0, ovrn = 1'b0, fe = 1'b0;
reg [7:0] tdr = 8'd0;
reg tdre = 1'b1;

wire [6:0] div = cr[1:0] == 2'b00 ? 7'd1 : cr[1:0] == 2'b01 ? 7'd16 : 7'd64;
wire tie = cr[6:5] == 2'b01;
wire rie = cr[7];
assign irq = !mreset && ((rie && (rdrf || ovrn)) || (tie && tdre));

wire [7:0] sr = { irq, 1'b0, ovrn, fe, 1'b0, 1'b0, tdre, rdrf };
assign dout = a0 ? rdr : sr;

wire tx_busy;
reg tx_load = 1'b0;
wire tx_line;
rc2014_ser_tx stx (
	.clk(clk), .reset(reset || mreset), .ce(ce), .div(div),
	.load(tx_load), .data(tdr), .busy(tx_busy), .tx(tx_line)
);
assign tx = cr[6:5] == 2'b11 ? 1'b0 : tx_line;

wire rx_done, rx_fe;
wire [7:0] rx_data;
rc2014_ser_rx srx (
	.clk(clk), .reset(reset || mreset), .ce(ce), .div(div),
	.rx(rx), .done(rx_done), .data(rx_data), .frame_err(rx_fe)
);

always @(posedge clk) begin
	tx_load <= 1'b0;
	if (reset) begin
		cr <= 8'h03;
		mreset <= 1'b1;
		rdrf <= 1'b0;
		ovrn <= 1'b0;
		fe <= 1'b0;
		tdre <= 1'b1;
	end
	else begin
		// transmit: TDR -> shift register when it is free
		if (!tdre && !tx_busy && !tx_load && !mreset) begin
			tx_load <= 1'b1;
			tdre <= 1'b1;
		end
		if (rd_stb && a0) begin
			rdrf <= 1'b0;
			ovrn <= 1'b0;
		end
		if (rx_done && !mreset) begin
			if (rdrf && !(rd_stb && a0))
				ovrn <= 1'b1;   // the new character is lost (as the 6850)
			else begin
				rdr <= rx_data;
				rdrf <= 1'b1;
				fe <= rx_fe;
			end
		end
		if (wr_stb) begin
			if (!a0) begin
				cr <= din;
				mreset <= din[1:0] == 2'b11;
				if (din[1:0] == 2'b11) begin
					rdrf <= 1'b0;
					ovrn <= 1'b0;
					fe <= 1'b0;
					tdre <= 1'b1;
				end
			end
			else begin
				tdr <= din;
				tdre <= 1'b0;
			end
		end
	end
end

endmodule
