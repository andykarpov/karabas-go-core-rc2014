`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_xonxoff.v

 XON / XOFF of the built-in terminal, done in the line: the bytes the terminal sends (its tx,
 115200 8N1) are received here; XOFF (13h, ^S) sets xoff, XON (11h, ^Q) clears it, both are taken
 out; every other byte is sent on to the machine (one frame later). xoff holds the transmitters
 of the terminal line (ACIA / SIO A) as RTS does: the RC2014 software (SCM, BASIC) knows no
 XON / XOFF, and the terminal (vt10x firmware) drops characters it cannot take while it scrolls.
 ^S / ^Q typed on the keyboard pause / resume the output the same way, as on a real terminal.

 xoff_count: the number of XOFF seen (debug).
*/
module rc2014_xonxoff (
	input wire clk,
	input wire reset,
	input wire term_tx,          // from the terminal
	output wire host_rx,         // to the machine
	output reg xoff = 1'b0,
	output reg [7:0] xoff_count = 8'd0
);

// 7.3728 MHz serial clock enable, as in rc2014_machine (/64 = 115200)
localparam [23:0] INC = 24'd2473901;
reg [24:0] acc = 25'd0;
reg ce = 1'b0;
always @(posedge clk) begin
	acc <= { 1'b0, acc[23:0] } + { 1'b0, INC };
	ce <= acc[24];
end

wire rx_done;
wire [7:0] rx_data;
rc2014_ser_rx srx (
	.clk(clk), .reset(reset), .ce(ce), .div(7'd64),
	.rx(term_tx), .done(rx_done), .data(rx_data), .frame_err()
);

// a small FIFO of bytes to pass on (the terminal sends at the line rate, so 4 is plenty)
reg [7:0] q [0:3];
reg [1:0] wp = 2'd0, rp = 2'd0;
reg [2:0] n = 3'd0;
wire tx_busy;
reg tx_load = 1'b0;

always @(posedge clk) begin
	tx_load <= 1'b0;
	if (reset) begin
		xoff <= 1'b0;
		wp <= 2'd0;
		rp <= 2'd0;
		n <= 3'd0;
	end
	else begin
		if (rx_done) begin
			if (rx_data == 8'h13) begin
				xoff <= 1'b1;
				xoff_count <= xoff_count + 8'd1;
			end
			else if (rx_data == 8'h11)
				xoff <= 1'b0;
			else if (n != 3'd4) begin
				q[wp] <= rx_data;
				wp <= wp + 2'd1;
			end
		end
		if (!tx_busy && !tx_load && n != 3'd0) begin
			tx_load <= 1'b1;
			rp <= rp + 2'd1;
		end
		n <= n + ((rx_done && rx_data != 8'h13 && rx_data != 8'h11 && n != 3'd4) ? 3'd1 : 3'd0)
		       - ((!tx_busy && !tx_load && n != 3'd0) ? 3'd1 : 3'd0);
	end
end

rc2014_ser_tx stx (
	.clk(clk), .reset(reset), .ce(ce), .div(7'd64),
	.load(tx_load), .data(q[rp - 2'd1]), .busy(tx_busy), .tx(host_rx)
);

endmodule
