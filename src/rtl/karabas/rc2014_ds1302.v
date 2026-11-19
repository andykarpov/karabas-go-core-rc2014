`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_ds1302.v

 The DS1302 of the RC2014 RTC module on port C0 (RomWBW DSRTCMODE_STD): write D7 data to the
 chip, D6 SCLK, D5 RD (1: the host reads, the chip drives data), D4 CE; read D0 = the data of the
 chip (the other bits read 1, an empty bus).

 The time is the clock of the board: kg_mcu2 with rtc_mode 1 (DS1307, BCD) keeps the registers
 00 seconds, 01 minutes, 02 hours, 03 day of week, 04 date, 05 month, 06 year in its RTC RAM
 (rtc_a -> rtc_do a clock later; the firmware sets them every 500 ms) and writes the clock chip
 when the core writes one (rtc_cs / rtc_wr_n). The DS1302 registers map onto them:
   DS1302 0 sec 1 min 2 hour 3 date 4 month 5 day 6 year -> DS1307 0 1 2 4 5 3 6
   7 control (WP, bit 7) and 8 trickle charger: here
   RAM 0-30 -> DS1307 RAM 08-26 (the firmware keeps it as the chip does)
 Clock halt (seconds bit 7) and 12 h mode (hours bit 7) are not kept: the clock always runs, 24 h.

 Protocol (data sheet): CE high starts a transfer; the command byte comes LSB first, a bit taken
 on each rising SCLK (bit 7 = 1, bit 6 RAM / clock, bits 5..1 address, bit 0 read); a read gives
 the first data bit after the falling SCLK that follows the command, the next bits on the next
 falling edges; a write takes the data on the rising edges. Address 31 = burst (clock: 8
 registers 0-7, RAM: 31 bytes). CE low ends it.
*/
module rc2014_ds1302 (
	input wire clk,
	input wire reset,

	input wire wr_stb,           // a write of port C0 (one clock, din valid)
	input wire [7:0] din,
	output wire [7:0] dout,      // the read value of port C0

	output reg [7:0] rtc_a = 8'd0,
	input wire [7:0] rtc_do,
	output reg [7:0] rtc_di = 8'd0,
	output reg rtc_cs = 1'b0,
	output reg rtc_wr_n = 1'b1
);

reg ce = 1'b0, sclk = 1'b0, io_in = 1'b0;
reg [7:0] cmd = 8'd0;
reg [3:0] nbit = 4'd0;         // bits of the current byte
reg have_cmd = 1'b0;
reg [5:0] idx = 6'd0;          // register / RAM byte of the transfer (bursts count it up)
reg [7:0] sh = 8'd0;           // the byte being read out / written in
reg io_out = 1'b1;             // the data bit the chip drives
reg wp = 1'b0;
reg [7:0] tcs = 8'h5C;         // trickle charger: off

assign dout = { 7'b1111111, io_out };

wire is_ram = cmd[6];
wire burst = cmd[5:1] == 5'd31;
wire rd_cmd = cmd[0];

// the RTC RAM address of a DS1302 register / RAM byte
function [7:0] map_a;
	input ram;
	input [5:0] i;
	begin
		if (ram)
			map_a = 8'h08 + { 2'b00, i };
		else case (i[2:0])
			3'd3: map_a = 8'h04;
			3'd4: map_a = 8'h05;
			3'd5: map_a = 8'h03;
			default: map_a = { 5'd0, i[2:0] };
		endcase
	end
endfunction

// the fetch of a byte to read: rtc_a set, rtc_do one clock later, taken the clock after
reg [1:0] fetch = 2'd0;

always @(posedge clk) begin
	rtc_cs <= 1'b0;
	rtc_wr_n <= 1'b1;
	if (fetch != 2'd0) begin
		fetch <= fetch - 2'd1;
		if (fetch == 2'd1) begin
			if (is_ram)
				sh <= rtc_do;
			else case (idx)
				6'd0: sh <= { 1'b0, rtc_do[6:0] };   // clock running
				6'd2: sh <= { 1'b0, rtc_do[6:0] };   // 24 h
				6'd7: sh <= { wp, 7'd0 };
				6'd8: sh <= tcs;
				default: sh <= rtc_do;
			endcase
			io_out <= is_ram ? rtc_do[0] : (idx == 6'd7 ? 1'b0 : idx == 6'd8 ? tcs[0] : rtc_do[0]);
		end
	end
	if (reset) begin
		ce <= 1'b0;
		have_cmd <= 1'b0;
		nbit <= 4'd0;
		io_out <= 1'b1;
		wp <= 1'b0;
	end
	else if (wr_stb) begin
		ce <= din[4];
		sclk <= din[6];
		io_in <= din[7];
		if (!din[4]) begin
			// CE low: the end of a transfer
			have_cmd <= 1'b0;
			nbit <= 4'd0;
			io_out <= 1'b1;
		end
		else if (!ce) begin
			have_cmd <= 1'b0;
			nbit <= 4'd0;
		end
		else if (din[6] && !sclk) begin
			// rising SCLK: a bit in (the command, or the data of a write)
			if (!have_cmd) begin
				cmd <= { din[7], cmd[7:1] };
				if (nbit == 4'd7) begin
					have_cmd <= 1'b1;
					nbit <= 4'd0;
					idx <= burst_of({ din[7], cmd[7:1] }) ? 6'd0 : { 1'b0, cmd[6:2] };
				end
				else
					nbit <= nbit + 4'd1;
			end
			else if (!rd_cmd) begin
				sh <= { din[7], sh[7:1] };
				if (nbit == 4'd7) begin
					nbit <= 4'd0;
					// the byte is complete: store it
					if (!is_ram && idx == 6'd7)
						wp <= din[7];
					else if (!is_ram && idx == 6'd8) begin
						if (!wp) tcs <= { din[7], sh[7:1] };
					end
					else if (!wp && (is_ram ? idx < 6'd31 : idx < 6'd7)) begin
						rtc_a <= map_a(is_ram, idx);
						rtc_di <= (!is_ram && idx == 6'd0) ? { 1'b0, sh[7:1] } : { din[7], sh[7:1] };   // seconds: clock halt (CH) cleared
						rtc_cs <= 1'b1;
						rtc_wr_n <= 1'b0;
					end
					if (burst) idx <= idx + 6'd1;
				end
				else
					nbit <= nbit + 4'd1;
			end
		end
		else if (!din[6] && sclk && have_cmd && rd_cmd) begin
			// falling SCLK of a read: the next data bit out (the first one after the command)
			if (nbit == 4'd0) begin
				rtc_a <= map_a(is_ram, idx);
				fetch <= 2'd2;
				nbit <= 4'd1;
			end
			else begin
				io_out <= sh[nbit[2:0]];
				if (nbit == 4'd7) begin
					nbit <= 4'd0;
					if (burst) idx <= idx + 6'd1;
				end
				else
					nbit <= nbit + 4'd1;
			end
		end
	end
end

function burst_of;
	input [7:0] c;
	burst_of = c[5:1] == 5'd31;
endfunction

endmodule
