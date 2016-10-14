`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    23:52:53 10/26/2014 
// Design Name: 
// Module Name:    prc1chan 
// Project Name: 
// Target Devices: 
// Tool versions:  
// Description: 
//		Process single channel. Version for _testbench_ without common master trigger,
//	but with trigger on SiPM pair. Unlike main design here only output from FIFO works on clk,
// 	all the rest uses ADCCLK.
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//	- module calculates and subtracks pedestal
// - does self trigger
// - does _no_ zero suppression
// - produce pair trigger block
//	Blocks sent to arbitter 
//	0	1CCC CCCL LLLL LLLL - CCCCCC - 6-bit channel number which produced the block ; 
//			 LLLLLLLLL - 9-bit block length in 16-bit words not including CW, L = WinLen + 2
// 	1	0ttt penn nnnn nnnn - ttt - trigger block type (0 - self, 3 - raw ADC data on master trigger, 6 - pair);
//			n - pair : 10-bit MSB global time, e = 0
//			  - self : 10-bit sequential selftrigger number, as counted after prescale, e = 0;
//			p - sent block sequential number LSB, independently on pair/self
//	2	0TTT TTTT TTTT TDDD - pair : D high resolution relative master frequency time 0-5 or timing error if 7
//		        T 12-bit LSB of global time.
//		or
//	2	0000 DDDD DDDD DDDD - self : baseline absolute value in ADC units
//	3	0XXX XXXX XXXX XXXX - L-2 words of ADC signed data after pedestal subtraction or ADC raw data
//////////////////////////////////////////////////////////////////////////////////
module prc1chand # (
	parameter ABITS = 12,			// width of ADC data
	parameter CBITS = 10,			// number of address bits in circular buffer memory
	parameter FBITS = 11,			// number of address bits in output fifo memory
	parameter STDELAY = 6,			// writing state machine sees self trigger after this number of clk
	parameter STDBITS = 3			// must correspond to STDELAY
)(
	input			clk,		// 125MHz GTP and output data clock
	input [5:0]		num,		// ADC number
	// ADC data from its reciever
	input			ADCCLK,		// ADC data clock
	input [ABITS-1:0]	ADCDAT,		// ADC raw data
	// data processing programmable parameters
	input [ABITS-1:0]	sthr,		// self trigger threshold (12 bits)
	input [15:0] 		prescale,	// prescale for self trigger (16 bits)
	input [CBITS-1:0]	mwinbeg,	// window begin relative to the pair trigger (10 bits)
	input [CBITS-1:0]	swinbeg,	// self trigger window begin relative to sthr crossing (10 bits)
	input [8:0] 		winlen,		// window length (9 bits, but not greater than 509)
	input 			stmask,		// 1 bit mask for self trigger
	input			invert,		// change waveform sign
	input 			raw,		// test mode: no selftrigger, zero for summing, raw data on master trigger
	// pedestals
	input			pedmode,	// pedestal mode: 0 - always calc and update, 1 - use small signal condition and change by 1
	input			pedinh,		// disable pedestal update according to pedmode
	output [ABITS-1:0]	ped,		// pedestal (baseline) for readout through WB pedarray
	// to double channel trigger (ADCCLK clocked)
	output [15:0]		dpdata,		// data to DCT
	// trigger time
	input [24:0] 		gtime,		// global time,inlcuding fine frequency shift in the 3 LS bits
	// trigger pulse and time
	input			ptrig,		// pair trigger (ADC clock)
	// inhibit
	input			inhibit,	// inhibits ONLY self trigger production
	// arbitter interface for data output
	input 			give,		// request from arbitter
	output 			have,		// acknowledge to arbitter, immediate with give
	output reg [15:0]	dout,		// tristate data to arbitter
	output reg		missed,		// 1 clk pulse when fifo cannot accept data because of full
	// test pulse interface
	input			testmode,	// Select test mode
	input			testpulse,	// do test pulse on the leading edge
	output			debug
);
//
//		Signals decalrations
//
	// pedestal calculations
	localparam 		PBITS = 12;	// number of bits in pedestal window counter
	wire [ABITS-1:0] 	ped_c;		// currently used averaged value, ADCCLK timed
	//	ADC data after pedestal subtraction and inversion, signed, ADCCLK timed
	reg signed [15:0]	pdata = 0;

	//	circular buffer for keeping prehistory and resynching ADC data to clk 
	reg [15:0] 		cbuf [2**CBITS-1:0];	// buffer itself
	reg [15:0]		cb_data = 0;	// buffer output data
	reg [CBITS-1:0]		cb_waddr = 0;	// write address, ADCCLK timed
	reg [CBITS-1:0]		cb_raddr = 0;	// read address, ADCCLK timed

	// self trigger & prescale
	reg			inh = 1;	// inhibit - sum all contributions
	wire 			strig;		// self trigger ADCCLK timed
	wire [9:0]		strig_cnt;	// self trigger counter after prescale

	//		state mathine definitions
	localparam ST_IDLE	= 0;		// waiting for triggers
	localparam ST_M0	= 1;		// master trigger preparation (need to sypport slave trigger abort)
	localparam ST_M1	= 2;		// trigger block words 1,2
	localparam ST_M2	= 3;
	localparam ST_MDATA	= 4;		// waveform
	localparam ST_S1	= 5;		// trigger block words 1,2
	localparam ST_S2	= 6;
	localparam ST_SDATA	= 7;		// waveform

	reg [2:0] 		trg_state = ST_IDLE;	// state
	reg [8:0] 		to_copy = 0;	// number of words from CB left for copying
	reg [8:0] 		blklen;		// block length derived from winlen
	reg			blkpar = 0;	// sequential parity of any sent block

	// output fifo
	reg [15:0] 		fifo [2**FBITS-1:0];	// fifo itself
	reg [15:0]		tofifo;		// variable to store data for writes to fifo, ADCCLK
	reg [FBITS-1:0] 	f_waddr = 0;	// fifo current write address, ADCCLK
	reg [FBITS-1:0] 	f_raddr = 0;	// fifo current read address, CLK
	wire [FBITS-1:0] 	graddr;		// fifo current read address for data outputs, CLK
	reg [FBITS-1:0] 	f_blkend = 0;	// memorized address of block end or start of currently written block, ADCCLK
	reg [FBITS-1:0] 	f_blkend_clk = 0;	// memorized address of block end or start of currently written block, clk
	reg			p_blkend = 0;	// pulse to reclock f_blkend to clk (ADCCLK)
	reg			p_blkend_clk = 0;	// pulse to reclock f_blkend to clk (CLK)
	
	wire [FBITS-1:0]	fifo_free;	// number of free 16-bit words in the output FIFO
	reg			fifo_full;	// fifo cannot accept next block, ADCCLK
	reg			fifo_full_clk;	// fifo cannot accept next block, clk
	reg			missed_adcclk;	// skipped trigger, adc clock

	// test mode support
	reg [1:0]		testp = 0;
	
	assign debug = 0;

//
//		The logic
//
	
//	pedestal calculation (round rather than truncate to avoid average buildup in summing)
	ped_calc #(
		.ABITS(ABITS),
		.PBITS(12)
	) UPED (
		.clk(clk),
		.adcclk(ADCCLK),
		.data(ADCDAT),
		.inhibit(pedinh),
		.mode(pedmode),
		.ped(ped_c),
		.ped_clk(ped)
	);

// 	pedestal subtraction and inversion
//		test pulse processing
	always @ (posedge ADCCLK) begin
		if (testmode) begin
			pdata <= (testp == 2'b01) ? 256 : 0;
		end else if (raw) begin
			pdata <= {{(16-ABITS){1'b0}}, ADCDAT};
		end else if (invert) begin
			pdata <= ped_c - ADCDAT;
		end else begin
			pdata <= ADCDAT - ped_c;
		end
		testp <= {testp[0], testpulse};
	end
	assign dpdata = pdata;

//		circular memory buffer at ADCCLK
	always @ (posedge ADCCLK) begin
		cbuf[cb_waddr] <= pdata;
		cb_data <= cbuf[cb_raddr];
		cb_waddr <= cb_waddr + 1;
	end

//		self trigger & prescale 
	always @ (posedge clk) begin
		inh <= inhibit | stmask | raw;	// effective inhibit
	end
	self_trig #(
		.ABITS(ABITS),
		.STDELAY(STDELAY),
		.STDBITS(STDBITS)
	) USELF (
		.adcclk(ADCCLK),
		.data(pdata),
		.inhibit(inh),
		.threshold(sthr),
		.prescale(prescale),
		.trig(strig),
		.counter(strig_cnt)
	);
	
//	FIFO
	assign have = give & (f_raddr != f_blkend_clk);
	assign graddr = (have) ? (f_raddr + 1) : f_raddr;
	assign fifo_free = f_raddr - f_blkend_clk;
	// write fifo
	always @ (posedge ADCCLK) begin
		fifo[f_waddr] <= tofifo;
		fifo_full <= fifo_full_clk;
	end
	// read fifo
	always @ (posedge clk) begin
		dout <= fifo[graddr];
		// increment raddr on data outputs
		if (have) begin
			f_raddr <= f_raddr + 1;
		end
		if (p_blkend_clk) begin
			f_blkend_clk <= f_blkend;
		end
		fifo_full_clk <= (fifo_free < (winlen + 4)) & (fifo_free != 0);
	end

	always @ (posedge clk or posedge p_blkend) begin
		if (p_blkend) begin
			p_blkend_clk <= 1;
		end else if (p_blkend_clk) begin
			p_blkend_clk <= 0;
		end 
	end

	always @ (posedge clk or posedge missed_adcclk) begin
		if (missed_adcclk) begin
			missed <= 1;
		end else if (missed) begin
			missed <= 0;
		end 
	end

// state machine @ ADCCLK
	always @ (posedge ADCCLK) begin
		p_blkend <= 0;			// default
		blklen <= winlen + 2;		// relatch for better timing
		tofifo = 0;
		cb_raddr <= cb_raddr + 1;	// increment by default
//		state machine
		case (trg_state) 
		ST_IDLE: begin
			if (~fifo_full && (winlen != 0)) begin // write nothing on zero winlen
				if (ptrig) begin
					trg_state <= ST_M0;
				end else if (strig) begin
					// we can write to fifo, write CW
					tofifo = {1'b1, num, blklen};
					f_waddr <= f_waddr + 1;
					to_copy <= winlen + 1;
					trg_state <= ST_S1;					
				end
			end
		end
		ST_M0: begin
			// we can write to fifo, write CW
			tofifo = {1'b1, num, blklen};
			f_waddr <= f_waddr + 1;
			to_copy <= winlen + 1;
			trg_state <= ST_M1;
		end
		ST_M1: begin
// 	1	0ttt penn nnnn nnnn
			tofifo = {4'b0110, blkpar, 1'b0, gtime[24:15]};
			f_waddr <= f_waddr + 1;
			cb_raddr <= cb_waddr - mwinbeg;	// prepare for reading from circular buffer
			trg_state <= ST_M2;
		end
		ST_M2: begin
//	2	0TTT TTTT TTTT TDDD 
			tofifo = {1'b0, gtime[14:0]};
			f_waddr <= f_waddr + 1;
			trg_state <= ST_MDATA;
		end
		ST_MDATA: begin
			// stream data from circular buffer to fifo
			tofifo = {1'b0, cb_data[14:0]};
			f_waddr <= f_waddr + 1;
			to_copy <= to_copy - 1;
			if (to_copy == 1)	begin
				f_blkend <= f_waddr + 1;			// save next waddr for further restoration
				trg_state <= ST_IDLE;
				p_blkend <= 1;
				blkpar <= ~blkpar;
			end
		end
		ST_S1: begin
			if (ptrig) begin	// abort self trig on pair trig
				f_waddr <= f_blkend;
				trg_state <= ST_M0;
			end else begin
// 	1	0ttt penn nnnn nnnn
				tofifo = {4'b0011, blkpar, 1'b0, strig_cnt};
				f_waddr <= f_waddr + 1;
				cb_raddr <= cb_waddr - swinbeg;	// prepare for reading from circular buffer
				trg_state <= ST_S2;
			end
		end
		ST_S2: begin
			if (ptrig) begin	// abort self trig on pair trig
				f_waddr <= f_blkend;
				trg_state <= ST_M0;
			end else begin
//	2	0000 DDDD DDDD DDDD - self : baseline absolute value in ADC units
				tofifo = {{(16-ABITS){1'b0}}, ped_c};
				f_waddr <= f_waddr + 1;
				trg_state <= ST_SDATA;
			end
		end
		ST_SDATA: begin
			if (ptrig) begin	// abort self trig on pair trig
				f_waddr <= f_blkend;
				trg_state <= ST_M0;
			end else begin
				// stream data from circular buffer to fifo
				tofifo = {1'b0, cb_data[14:0]};
				f_waddr <= f_waddr + 1;
				to_copy <= to_copy - 1;
				if (to_copy == 1)	begin
					f_blkend <= f_waddr + 1;			// save next waddr for further restoration
					trg_state <= ST_IDLE;
					p_blkend <= 1;
					blkpar <= ~blkpar;
				end
			end
		end

		default: trg_state <= ST_IDLE;
		endcase
//		Missed
		if (ptrig && (fifo_full || trg_state == ST_M0 || trg_state == ST_M1 ||
			trg_state == ST_M2 || trg_state == ST_MDATA)) begin
			missed_adcclk <= 1;
		end else begin
			missed_adcclk <= 0;
		end
	end

endmodule
