`timescale 1ns / 1ps
`default_nettype none
/*
 rc2014_sio.v

 The Z80 SIO/2 of the RC2014 Dual Serial module (SIOMODE_RC: 80 A control, 81 A data, 82 B control,
 83 B data, a[1] = channel, a[0] = data), both channels clocked by the 7.3728 MHz serial clock
 (ce): clock mode x64 = 115200 bps, x16 = 460800, x32 = 230400, x1 = the clock itself.

 What the RC2014 software uses (SCM, RomWBW sio.asm, CP/M BIOSes), asynchronous mode only:
   WR0  2:0 register pointer (the next control access, then back to 0), 5:3 commands: 010 reset
        ext / status interrupts, 011 channel reset, 100 enable interrupt on next Rx character,
        101 reset Tx interrupt pending, 110 error reset, 111 return from interrupt (channel A)
   WR1  0 ext / status int enable, 1 Tx int enable, 2 status affects vector (B), 4:3 Rx int mode
        (00 off, 01 first character, 10 / 11 all characters)
   WR2  the interrupt vector (channel B)
   WR3  0 Rx enable, 5 auto enables (CTS / DCD: always active here), 7:6 Rx bits (8 taken)
   WR4  7:6 clock mode (00 x1, 01 x16, 10 x32, 11 x64), the rest (stop bits, parity) taken as 8N1
   WR5  1 RTS, 3 Tx enable, 4 send break, 7 DTR
   RR0  0 Rx character available, 1 interrupt pending (channel A only), 2 Tx buffer empty, 3 DCD (1:
        the module ties DCD active), 5 CTS (1), 6 Tx underrun / EOM (1 after reset)
   RR1  0 all sent, 4 parity error (0), 5 Rx overrun, 6 CRC / framing error
   RR2  (channel B) the vector, modified by the interrupt state when WR1 bit 2 is set
 A three byte Rx FIFO per channel as the SIO. The interrupt is IM1 / IM2 level (int_n); the
 vector of an interrupt acknowledge (IM2) is on the data bus with ack (M1 and IORQ): the RC2014
 software runs IM1, the daisy chain (IEI / IEO, RETI decoding) is not modelled.

 Channel B is a byte stream (no line): the USB serial port of the board (kg_mcu2 port 0, the clean
 CDC of the firmware). A byte of rxb_data / rxb_wr goes into its Rx FIFO (rxb_ready: the FIFO is
 empty and Rx is on, so a byte waits in the MCU instead of overrunning); a byte written to its Tx
 buffer goes out as txb_data / txb_wr at once unless txb_full (the MCU side has no room). The clock
 mode of WR4 does not matter there.

 RXBUF_A (log2 of the depth, 0 = none): a receive buffer in block RAM in front of the Rx FIFO of
 line A (the ESP module of the second SIO: Fuzix has no RTS flow control on the SIO and the TMS
 console runs with the interrupts off longer than three characters). A character of the line goes
 into the buffer, the buffer gives one to the Rx FIFO while it is not full; a channel reset empties
 it, a full buffer drops the character.

 Bus: rd_stb / wr_stb one clock each, rd_stb at the END of the CPU read.
*/
module rc2014_sio #(
	parameter RXBUF_A = 0
) (
	input wire clk,
	input wire reset,
	input wire ce,

	input wire [1:0] a,        // a[1] B / A, a[0] data / control
	input wire rd_stb,
	input wire wr_stb,
	input wire [7:0] din,
	output wire [7:0] dout,
	output wire int_n,
	output wire [7:0] vector,

	output wire tx_a,
	input wire rx_a,
	input wire [7:0] rxb_data,   // channel B: the byte stream of the USB serial port
	input wire rxb_wr,
	output wire rxb_ready,
	output wire [7:0] txb_data,
	output wire txb_wr,
	input wire txb_full,
	output wire rts_a,
	output wire rts_b,
	input wire hold_a        // the receiver of line A asks to wait (RTS of the terminal): no new frame starts
);

wire [1:0] ch_int;
wire [2:0] ch_cause [0:1];  // 0 none, 1 Tx empty, 2 ext / status, 3 Rx char, 4 special Rx
wire [7:0] ch_dout [0:1];
wire [7:0] wr2_b;
wire wr1_sav_b;

// the vector of the highest priority interrupt (A Rx, A Tx, A ext, B Rx, B Tx, B ext): the
// status affects vector code (V3:V1) as the SIO data sheet, B = 0xx, A = 1xx
reg [2:0] vcode;
always @* begin
	vcode = 3'b011;                                          // no interrupt pending
	if (ch_int[0])
		case (ch_cause[0])
			3'd3: vcode = 3'b110;
			3'd4: vcode = 3'b111;
			3'd2: vcode = 3'b101;
			default: vcode = 3'b100;
		endcase
	else if (ch_int[1])
		case (ch_cause[1])
			3'd3: vcode = 3'b010;
			3'd4: vcode = 3'b011;
			3'd2: vcode = 3'b001;
			default: vcode = 3'b000;
		endcase
end
assign vector = wr1_sav_b ? { wr2_b[7:4], vcode, wr2_b[0] } : wr2_b;
assign int_n = !(|ch_int);

assign dout = a[1] ? ch_dout[1] : ch_dout[0];

rc2014_sio_ch #(.CHAN_B(0), .RXBUF(RXBUF_A)) cha (
	.clk(clk), .reset(reset), .ce(ce),
	.b_data(8'd0), .b_wr(1'b0), .b_ready(), .bt_data(), .bt_wr(), .bt_full(1'b0),
	.sel(!a[1]), .data(a[0]), .rd_stb(rd_stb), .wr_stb(wr_stb), .din(din), .dout(ch_dout[0]),
	.int_any(|ch_int), .vector(vector), .irq(ch_int[0]), .cause(ch_cause[0]),
	.wr2(), .wr1_sav(), .tx(tx_a), .rx(rx_a), .rts(rts_a), .hold(hold_a)
);

rc2014_sio_ch #(.CHAN_B(1)) chb (
	.clk(clk), .reset(reset), .ce(ce),
	.b_data(rxb_data), .b_wr(rxb_wr), .b_ready(rxb_ready), .bt_data(txb_data), .bt_wr(txb_wr), .bt_full(txb_full),
	.sel(a[1]), .data(a[0]), .rd_stb(rd_stb), .wr_stb(wr_stb), .din(din), .dout(ch_dout[1]),
	.int_any(|ch_int), .vector(vector), .irq(ch_int[1]), .cause(ch_cause[1]),
	.wr2(wr2_b), .wr1_sav(wr1_sav_b), .tx(), .rx(1'b1), .rts(rts_b), .hold(1'b0)
);

endmodule

module rc2014_sio_ch #(
	parameter CHAN_B = 0,
	parameter RXBUF = 0
) (
	input wire clk,
	input wire reset,
	input wire ce,

	// CHAN_B: the byte stream instead of the line (see the top)
	input wire [7:0] b_data,
	input wire b_wr,
	output wire b_ready,
	output reg [7:0] bt_data = 8'd0,
	output reg bt_wr = 1'b0,
	input wire bt_full,

	input wire sel,
	input wire data,
	input wire rd_stb,
	input wire wr_stb,
	input wire [7:0] din,
	output reg [7:0] dout,
	input wire int_any,          // RR0 bit 1 of channel A: any interrupt pending
	input wire [7:0] vector,     // RR2 of channel B

	output wire irq,
	output reg [2:0] cause,
	output wire [7:0] wr2,
	output wire wr1_sav,

	output wire tx,
	input wire rx,
	output wire rts,
	input wire hold
);

reg [2:0] ptr = 3'd0;
reg [7:0] wr1 = 8'd0, wr2_r = 8'd0, wr3 = 8'd0, wr4 = 8'd0, wr5 = 8'd0;
assign wr2 = wr2_r;
assign wr1_sav = wr1[2];

// line
wire [6:0] div = wr4[7:6] == 2'b00 ? 7'd1 : wr4[7:6] == 2'b01 ? 7'd16 : wr4[7:6] == 2'b10 ? 7'd32 : 7'd64;
wire tx_en = wr5[3];
wire rx_en = wr3[0];
assign rts = wr5[1];

// transmit buffer
reg [7:0] tdr = 8'd0;
reg tbe = 1'b1;              // Tx buffer empty
reg tx_load = 1'b0;
wire tx_busy, tx_line;
reg tx_ip = 1'b0;            // Tx interrupt pending
reg tx_armed = 1'b0;         // a character was written since the last reset of Tx int pending
generate if (!CHAN_B) begin : line_tx
rc2014_ser_tx stx (
	.clk(clk), .reset(reset), .ce(ce), .div(div),
	.load(tx_load), .data(tdr), .busy(tx_busy), .tx(tx_line)
);
end else begin : no_line_tx
assign tx_busy = 1'b0;
assign tx_line = 1'b1;
end endgenerate
assign tx = wr5[4] ? 1'b0 : tx_line;

// receive FIFO (3 deep)
wire line_done, line_fe;
wire [7:0] line_data;
generate if (!CHAN_B) begin : line_rx
rc2014_ser_rx srx (
	.clk(clk), .reset(reset), .ce(ce), .div(div),
	.rx(rx), .done(line_done), .data(line_data), .frame_err(line_fe)
);
end else begin : no_line_rx
assign line_done = 1'b0;
assign line_data = 8'd0;
assign line_fe = 1'b0;
end endgenerate
reg [7:0] fifo [0:2];
reg [2:0] fifo_fe = 3'b000;
reg [1:0] cnt = 2'd0;
reg chan_reset = 1'b0;       // the channel reset command (one clock)

// the receive buffer of RXBUF (see the top): one character into the Rx FIFO at a time, the next
// one after the count of the FIFO has followed (two clocks)
wire buf_wr;
wire buf_fe;
wire [7:0] buf_data;
generate if (RXBUF > 0) begin : rx_buf
reg [8:0] bmem [0:(1 << RXBUF) - 1];
reg [RXBUF-1:0] wp = 0, rp = 0;
reg [8:0] bq = 9'd0;
reg bq_wr = 1'b0, bq_wr_q = 1'b0;
wire bempty = wp == rp;
wire bfull = wp + 1'd1 == rp;
always @(posedge clk) begin
	bq_wr <= 1'b0;
	bq_wr_q <= bq_wr;
	if (line_done && !bfull) begin
		bmem[wp] <= { line_fe, line_data };
		wp <= wp + 1'd1;
	end
	bq <= bmem[rp];
	if (reset || chan_reset)
		rp <= wp;
	else if (!bempty && rx_en && cnt != 2'd3 && !bq_wr && !bq_wr_q) begin
		rp <= rp + 1'd1;
		bq_wr <= 1'b1;
	end
end
assign buf_wr = bq_wr;
assign buf_fe = bq[8];
assign buf_data = bq[7:0];
end else begin : no_rx_buf
assign buf_wr = line_done;
assign buf_fe = line_fe;
assign buf_data = line_data;
end endgenerate

wire rx_done = CHAN_B ? b_wr && rx_en : buf_wr;
wire rx_fe = CHAN_B ? 1'b0 : buf_fe;
wire [7:0] rx_data = CHAN_B ? b_data : buf_data;
reg ovr = 1'b0;              // RR1 bit 5
reg fe_rr1 = 1'b0;           // RR1 bit 6 (of the character at the top)
reg rx_first = 1'b1;         // Rx int on first character: armed
wire rca = cnt != 2'd0;
// the byte stream: one byte at a time into an empty FIFO (the port gives out_wr a clock after
// ready, the count a clock after that)
reg b_wr_q = 1'b0;
always @(posedge clk)
	b_wr_q <= b_wr;
assign b_ready = rx_en && cnt == 2'd0 && !b_wr && !b_wr_q;

reg rx_first_hit = 1'b0;     // the first character after the arming is in the FIFO
wire acc_wr = sel && wr_stb;
wire acc_rd = sel && rd_stb;
wire pop = acc_rd && data && cnt != 2'd0;

// interrupts
wire [1:0] rx_mode = wr1[4:3];
wire rx_irq = rca && ((rx_mode == 2'b01 && rx_first_hit) || rx_mode[1]);
wire tx_irq = wr1[1] && tx_ip;
assign irq = rx_irq || tx_irq;
always @* begin
	if (rx_irq)
		cause = (fe_rr1 || ovr) ? 3'd4 : 3'd3;
	else if (tx_irq)
		cause = 3'd1;
	else
		cause = 3'd0;
end

// read registers
wire all_sent = tbe && !tx_busy && !tx_load;
wire [7:0] rr0 = { 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, tbe, (CHAN_B ? 1'b0 : int_any), rca };
wire [7:0] rr1 = { 1'b0, fe_rr1, ovr, 1'b0, 3'b011, all_sent };
always @* begin
	if (data)
		dout = fifo[0];
	else
		case (ptr)
			3'd1: dout = rr1;
			3'd2: dout = CHAN_B ? vector : wr2_r;
			default: dout = rr0;
		endcase
end


always @(posedge clk) begin
	tx_load <= 1'b0;
	bt_wr <= 1'b0;
	chan_reset <= 1'b0;
	if (reset) begin
		ptr <= 3'd0;
		wr1 <= 8'd0;
		wr3 <= 8'd0;
		wr4 <= 8'd0;
		wr5 <= 8'd0;
		tbe <= 1'b1;
		tx_ip <= 1'b0;
		tx_armed <= 1'b0;
		cnt <= 2'd0;
		ovr <= 1'b0;
		fe_rr1 <= 1'b0;
		rx_first <= 1'b1;
		rx_first_hit <= 1'b0;
		if (CHAN_B) wr2_r <= 8'd0;
	end
	else begin
		// Tx: buffer -> shift register; the buffer going empty sets Tx int pending (not when it
		// was empty already)
		if (!tbe && !tx_busy && !tx_load && tx_en && !hold && !(CHAN_B && bt_full)) begin
			tx_load <= !CHAN_B;
			bt_wr <= CHAN_B;
			bt_data <= tdr;
			tbe <= 1'b1;
			if (tx_armed) tx_ip <= 1'b1;
		end

		// Rx: into the FIFO (an overrun replaces the last character, as the SIO)
		if (rx_done && rx_en) begin
			if (cnt == 2'd3 && !pop) begin
				fifo[2] <= rx_data;
				fifo_fe[2] <= rx_fe;
				ovr <= 1'b1;
			end
			else begin
				// written after the pop below (the same clock): the index of the free entry
				// after the pop
				fifo[pop ? cnt - 2'd1 : cnt] <= rx_data;
				fifo_fe[pop ? cnt - 2'd1 : cnt] <= rx_fe;
			end
			if (rx_first) begin
				rx_first_hit <= 1'b1;
				rx_first <= 1'b0;
			end
		end

		// data read: pop
		if (pop) begin
			rx_first_hit <= 1'b0;
			fifo[0] <= fifo[1];
			fifo[1] <= fifo[2];
			fifo_fe <= { 1'b0, fifo_fe[2:1] };
			fe_rr1 <= fifo_fe[1];
		end
		if (rx_done && rx_en) begin
			if (!(cnt == 2'd3 && !pop))
				cnt <= pop ? cnt : cnt + 2'd1;
		end
		else if (pop)
			cnt <= cnt - 2'd1;
		if (rx_done && rx_en && cnt == 2'd0)
			fe_rr1 <= rx_fe;

		// control read: the pointer back to 0
		if (acc_rd && !data)
			ptr <= 3'd0;

		// data write
		if (acc_wr && data) begin
			tdr <= din;
			tbe <= 1'b0;
			tx_ip <= 1'b0;
			tx_armed <= 1'b1;
		end

		// control write
		if (acc_wr && !data) begin
			if (ptr != 3'd0) begin
				case (ptr)
					3'd1: wr1 <= din;
					3'd2: wr2_r <= din;
					3'd3: wr3 <= din;
					3'd4: wr4 <= din;
					3'd5: wr5 <= din;
					default: ;
				endcase
				ptr <= 3'd0;
			end
			else begin
				ptr <= din[2:0];
				case (din[5:3])
					3'b011: begin                // channel reset
						chan_reset <= 1'b1;
						wr1 <= 8'd0;
						wr3 <= 8'd0;
						wr4 <= 8'd0;
						wr5 <= 8'd0;
						tbe <= 1'b1;
						tx_ip <= 1'b0;
						tx_armed <= 1'b0;
						cnt <= 2'd0;
						ovr <= 1'b0;
						fe_rr1 <= 1'b0;
						rx_first <= 1'b1;
						rx_first_hit <= 1'b0;
					end
					3'b100: begin                // enable interrupt on next Rx character
						rx_first <= 1'b1;
						rx_first_hit <= 1'b0;
					end
					3'b101: begin                // reset Tx int pending
						tx_ip <= 1'b0;
						tx_armed <= 1'b0;
					end
					3'b110: begin                // error reset
						ovr <= 1'b0;
						fe_rr1 <= 1'b0;
					end
					default: ;
				endcase
			end
		end
	end
end

endmodule
