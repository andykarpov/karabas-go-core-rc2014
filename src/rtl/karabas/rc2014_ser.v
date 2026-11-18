`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_ser.v

 The serial line engines of the ACIA and of the SIO/2 channels: 8 data bits, LSB first, no parity,
 one stop bit on transmit (enough for 8N1 / 8N2 receivers). A bit lasts `div` ticks of the serial
 clock enable (ce: 7.3728 MHz as the RC2014 clock, div 64 = 115200 bps, 16 = 460800, 1 = x1).

 rc2014_ser_tx: load (one clock, while idle) takes data; busy until the stop bit is out.
 rc2014_ser_rx: rx is synchronised here; a start bit is checked in its middle, the data bits are
 taken in their middles, done (one clock) with data and frame_err (stop bit 0).
*/

module rc2014_ser_tx (
	input wire clk,
	input wire reset,
	input wire ce,
	input wire [6:0] div,
	input wire load,
	input wire [7:0] data,
	output wire busy,
	output reg tx = 1'b1
);

reg [9:0] sh = 10'd0;      // { stop, data, start } still to send, LSB first
reg [3:0] bits = 4'd0;     // bits left (0 = idle)
reg [6:0] cnt = 7'd0;
assign busy = bits != 4'd0;

always @(posedge clk) begin
	if (reset) begin
		bits <= 4'd0;
		tx <= 1'b1;
	end
	else if (!busy) begin
		tx <= 1'b1;
		if (load) begin
			sh <= { 1'b1, data, 1'b0 };
			bits <= 4'd10;
			cnt <= 7'd0;
		end
	end
	else if (ce) begin
		if (cnt == 7'd0) begin
			tx <= sh[0];
			sh <= { 1'b1, sh[9:1] };
		end
		if (cnt == div - 7'd1) begin
			cnt <= 7'd0;
			bits <= bits - 4'd1;
		end
		else
			cnt <= cnt + 7'd1;
	end
end

endmodule

module rc2014_ser_rx (
	input wire clk,
	input wire reset,
	input wire ce,
	input wire [6:0] div,
	input wire rx,
	output reg done = 1'b0,
	output reg [7:0] data = 8'd0,
	output reg frame_err = 1'b0
);

reg [2:0] rx_s = 3'b111;
always @(posedge clk)
	rx_s <= { rx_s[1:0], rx };
wire rxd = rx_s[2];

reg [3:0] bit = 4'd0;      // 0 idle, 1 start, 2..9 data, 10 stop
reg [6:0] cnt = 7'd0;
reg [7:0] sh = 8'd0;
wire [6:0] half = (div >> 1);

always @(posedge clk) begin
	done <= 1'b0;
	if (reset)
		bit <= 4'd0;
	else if (bit == 4'd0) begin
		if (!rxd) begin
			bit <= 4'd1;
			cnt <= 7'd0;
		end
	end
	else if (ce) begin
		if (cnt == (bit == 4'd1 ? half : div - 7'd1)) begin
			cnt <= 7'd0;
			if (bit == 4'd1)
				bit <= rxd ? 4'd0 : 4'd2;     // a glitch, not a start bit
			else if (bit == 4'd10) begin
				bit <= 4'd0;
				done <= 1'b1;
				data <= sh;
				frame_err <= !rxd;
			end
			else begin
				sh <= { rxd, sh[7:1] };
				bit <= bit + 4'd1;
			end
		end
		else
			cnt <= cnt + 7'd1;
	end
end

endmodule
