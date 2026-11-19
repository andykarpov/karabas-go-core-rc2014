`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_kbd8242.v

 The 8242 PS/2 keyboard controller of the console on the TMS9918 (RomWBW TMSMODE_MSXKBD, kbd.asm):
 60 data, 64 status (read) / command (write). The keyboard is the PS/2 set 2 bytes of kg_mcu2
 (translation off, as kbd.asm sets it), the keyboard and controller answers are made here.

   status (64)  bit 0 OBF (a byte waits at 60), bit 1 IBF (always 0: a write is taken at once),
                bit 2 system flag (1)
   commands     AA self test -> 55; 20 read the command byte; 60 write it (the next byte at 60);
                AB / A9 interface tests -> 00; AD / AE / A7 / A8 port disable / enable: taken
   to the keyboard (a byte at 60): FF reset -> FA AA; ED LEDs, F3 rate, F0 scan set (a parameter
                byte follows) -> FA, and FA for the parameter; F2 identify -> FA AB 83; EE echo -> EE;
                any other byte -> FA

 One FIFO of 16 bytes holds the keyboard bytes and the answers (an answer never gets lost: a
 keyboard byte of the same clock waits a clock). A read of 60 with nothing there gives the last
 byte again. No interrupt (KBDINTS off in RomWBW).

 Bus: rd_stb at the END of a CPU read (the byte is popped), wr_stb one clock with din.
*/
module rc2014_kbd8242 (
	input wire clk,
	input wire reset,

	input wire a2,             // 0: 60 data, 1: 64 status / command (the port of the access)
	input wire rd_stb,
	input wire wr_stb,
	input wire [7:0] din,
	output wire [7:0] dout,    // the read value (the port of a2)

	input wire [7:0] kbd_code, // the keyboard: PS/2 set 2 bytes
	input wire kbd_wr
);

reg [7:0] q [0:15];
reg [3:0] wp = 4'd0, rp = 4'd0;
reg [4:0] n = 5'd0;
reg [7:0] last = 8'h00;
wire obf = n != 5'd0;
wire [7:0] head = obf ? q[rp] : last;

reg [7:0] cmd_byte = 8'h20;
reg want_cmd = 1'b0;       // the next byte at 60 is the command byte (command 60)
reg want_par = 1'b0;       // the next byte at 60 is the parameter of a keyboard command

// answers waiting to go into the FIFO (one a clock, the first in a[7:0])
reg [23:0] ans = 24'd0;
reg [1:0] ans_n = 2'd0;
reg [7:0] kbd_hold = 8'd0;
reg kbd_pend = 1'b0;

assign dout = a2 ? { 5'b00000, 1'b1, 1'b0, obf } : head;

wire pop = rd_stb && !a2 && obf;

always @(posedge clk) begin
	if (reset) begin
		wp <= 4'd0;
		rp <= 4'd0;
		n <= 5'd0;
		want_cmd <= 1'b0;
		want_par <= 1'b0;
		ans_n <= 2'd0;
		kbd_pend <= 1'b0;
		cmd_byte <= 8'h20;
	end
	else begin : step
		reg push;
		reg [7:0] pv;
		push = 1'b0;
		pv = 8'h00;

		// a new keyboard byte (held a clock when an answer goes in)
		if (kbd_wr) begin
			kbd_hold <= kbd_code;
			kbd_pend <= 1'b1;
		end

		if (ans_n != 2'd0) begin
			push = 1'b1;
			pv = ans[7:0];
			ans <= { 8'h00, ans[23:8] };
			ans_n <= ans_n - 2'd1;
		end
		else if (kbd_pend && !kbd_wr) begin
			push = 1'b1;
			pv = kbd_hold;
			kbd_pend <= 1'b0;
		end

		// commands and bytes to the keyboard (answers go out from the next clock)
		if (wr_stb && a2) begin
			want_cmd <= 1'b0;
			case (din)
				8'hAA: begin ans <= 24'h000055; ans_n <= 2'd1; end
				8'h20: begin ans <= { 16'd0, cmd_byte }; ans_n <= 2'd1; end
				8'h60: want_cmd <= 1'b1;
				8'hAB, 8'hA9: begin ans <= 24'h000000; ans_n <= 2'd1; end
				default: ;
			endcase
		end
		else if (wr_stb && !a2) begin
			if (want_cmd) begin
				cmd_byte <= din;
				want_cmd <= 1'b0;
			end
			else if (want_par) begin
				want_par <= 1'b0;
				ans <= 24'h0000FA; ans_n <= 2'd1;
			end
			else case (din)
				8'hFF: begin ans <= 24'h00AAFA; ans_n <= 2'd2; end
				8'hED, 8'hF3, 8'hF0: begin ans <= 24'h0000FA; ans_n <= 2'd1; want_par <= 1'b1; end
				8'hF2: begin ans <= 24'h83ABFA; ans_n <= 2'd3; end
				8'hEE: begin ans <= 24'h0000EE; ans_n <= 2'd1; end
				default: begin ans <= 24'h0000FA; ans_n <= 2'd1; end
			endcase
		end

		// the FIFO (a byte over 16 is dropped)
		if (push && n != 5'd16) begin
			q[wp] <= pv;
			wp <= wp + 4'd1;
		end
		if (pop) begin
			last <= q[rp];
			rp <= rp + 4'd1;
		end
		n <= n + ((push && n != 5'd16) ? 5'd1 : 5'd0) - (pop ? 5'd1 : 5'd0);
	end
end

endmodule
