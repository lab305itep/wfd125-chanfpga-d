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
//		Process single channel.
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//	- module calculates and subtracks pedestal
// - does self trigger
// - does zero suppression
// - produce master trigger block
//		Blocks sent to arbitter 
//		0	1CCC CCCL LLLL LLLL - CCCCCC - 6-bit channel number which produced the block ; 
//										 LLLLLLLLL - 9-bit block length in 16-bit words not including CW, L = WinLen + 2
// 	1	0ttt penn nnnn nnnn - ttt - trigger block type (0 - self, 1 - master, 3 - raw ADC data on master trigger) ;
//										 n - master : 10-bit trigger token from gtp, e - token error (as recieved by main FPGA)
//											- self : 10-bit sequential selftrigger number, as counted after prescale, e = 0;
//										 p - sent block sequential number LSB, independently on master/self
//		2	0000 0000 0000 0DDD - master : high resolution relative trigger time 0-5 or timing error if 7
//			or
//		2	0000 DDDD DDDD DDDD - self : baseline absolute value in ADC units
//		3	0XXX XXXX XXXX XXXX - L-2 words of ADC signed data after pedestal subtraction or ADC raw data
//////////////////////////////////////////////////////////////////////////////////
module prc1chan # (
		parameter ABITS = 12,			// width of ADC data
		parameter CBITS = 10,			// number of bits in circular buffer memory
		parameter FBITS = 11,			// number of bits in output fifo memory
		parameter STDELAY = 50,			// writing state machine sees self trigger after this number of clk
		parameter STDBITS = 6			// must correspond to STDELAY
		)
		(
		input 				clk,			// 125MHz GTP and output data clock
		input [5:0] 		num,			// ADC number
		// ADC data from its reciever
		input 				ADCCLK,		// ADC data clock
		input [ABITS-1:0]	ADCDAT,		// ADC raw data
		// data processing programmable parameters
		input [ABITS-1:0]	zthr,			// zero suppression threshold (12 bits)
		input [ABITS-1:0]	sthr,			// self trigger threshold (12 bits)
		input [15:0] 		prescale,	// prescale for self trigger (16 bits)
		input [CBITS-1:0]	mwinbeg,		// window begin relative to the master trigger (10 bits)
		input [CBITS-1:0]	swinbeg,		// self trigger window begin relative to sthr crossing (10 bits)
		input [8:0] 		winlen,		// window length (9 bits, but not greater than 509)
		input [8:0] 		zbeg,			// relative shift of zero suppression sensitive window begin
		input [8:0] 		zend,			// relative shift of zero suppression sensitive window end
		input 				smask,		// 1 bit mask for sum
		input 				tmask,		// 1 bit mask for trigger
		input 				stmask,		// 1 bit mask for self trigger
		input					invert,		// change waveform sign
		input 				raw,			// test mode: no selftrigger, zero for summing, raw data on master trigger
		// pedestals
		input					pedmode,		// pedestal mode: 0 - always calc and update, 1 - use small signal condition and change by 1
		input					pedinh,		// disable pedestal update according to pedmode
		output reg [ABITS-1:0] ped = 0,	// pedestal (baseline) for readout through WB pedarray
		// trigger token
		input [15:0] 		token,		// master trigger token as recieved by main FPGA and transmitted 
												// through GTP: 0000 0enn nnnn nnnn
		input					tok_vld,		// token valid strobe
		// trigger pulse and time
		input					adc_trig,	// master trigger as recieved by this ADC
		input	[2:0]			trig_time,	// high resolution master trigger time
		// inhibit
		input					inhibit,		// inhibits ONLY self trigger production
		// arbitter interface for data output
		input 				give,			// request from arbitter
		output 				have,			// acknowledge to arbitter, immediate with give
		output [15:0] 		dout,			// tristate data to arbitter
		output reg			missed,		// 1 clk pulse when fifo cannot accept data because of full
output [1:0] debug,
		// to double channel trigger (ADCCLK clocked)
		output [15:0]		dpdata,		// data to DCT
		input 				ddiscr,		// discriminator output from DCT
		// to sumtrig
		output reg [15:0] d2sum,		// (ADC - pedestal) signed to trigger summation
		input					testmode,	// Select test mode
		input					testpulse	// do test pulse on the leading edge
   );

assign debug = {mtrig_c, strig_c};

assign dpdata = pdata;

	// pedestal calculations
		localparam 					PBITS = 12;			// number of bits in pedestal window counter
		localparam [ABITS-1:0]	pedrange = 5;		// inteval for small signal in pedmode=1
		reg [PBITS+ABITS-1:0] 	pedsum = 0;			// sum for average
		reg [PBITS-1:0] 			pedcnt = 0;			// ped window counter
		reg [ABITS-1:0] 			ped_s = 0;			// currently calculated averaged value, ADCCLK timed
		wire [ABITS-1:0] 			ped_s_m1 = ped_s - 1'b1;	// currently calculated averaged value minus 1, ADCCLK timed
		reg [ABITS-1:0] 			ped_c = 0;			// currently used averaged value, ADCCLK timed
		reg [ABITS-1:0] 			ped_b = 0;			// currently used averaged value, clk timed
		reg 							ped_pulse = 0;		// ped ready
		reg [1:0] 					ped_pulse_d = 0;	// for CLK sync

	//	ADC data after pedestal subtraction and inversion, signed, ADCCLK timed
		reg signed [15:0]			pdata = 0;

	//	circular buffer for keeping prehistory and resynching ADC data to clk 
		reg [15:0] 				cbuf [2**CBITS-1:0];	// buffer itself
		reg [15:0]				cb_data = 0;			// buffer output data
		reg [CBITS-1:0]		cb_waddr = 0;			// write address, ADCCLK timed
		reg [CBITS-1:0]		cb_raddr = 0;			// read address, clk timed
		reg [CBITS-1:0] 		str_addr = 0;			// write address at self trigger start, ADCCLK timed
		reg [CBITS-1:0] 		mtr_addr = 0;			// write address at master trigger start, ADCCLK timed

	// self trigger & prescale 
		reg						inh = 1;					// inhibit, relatched to ADCCLK
		reg 						discr = 0;				// signal above selftrigger threshold
		reg 						strig = 0;				// self trigger ADCCLK timed
		reg [STDBITS-1:0]		strig_del;				// counter for selftrigger delay
		reg						strig_c = 0;			// self trigger delayed, clk timed
		reg [9:0]				strig_cnt = 0;			// self trigger counter after prescale
		reg [9:0]				strig_cnt_c = 0;		// self trigger counter after prescale reclocked to clk
		reg [15:0] 				presc_cnt = 0;			// selftrigger prescale counter
	
	// master trigger
		reg						mtrig = 0;				// master trigger
		reg						mtrig_c = 0;			// master trigger reclocked to clk
		reg [2:0]				tr_time = 0;			// high resoultion trigger time
		reg [2:0]				tr_time_c = 0;			// high resoultion trigger time recdlocked to clk
		reg						tok_got = 0;			// token accepted for this mtrig
		reg [10:0]				tr_tok = 0;				// memorized token with error
		
	// output fifo
		reg [15:0] 				fifo [2**FBITS-1:0];	// fifo itself
		reg [15:0]				tofifo;					// variable to store data for writes to fifo
		reg [15:0]				f_data;					// fifo output data
		reg [FBITS-1:0] 		f_waddr = 0;			// fifo current write address
		reg [FBITS-1:0] 		f_waddr_s = 0;			// temprary holder for waddr for token out of order writing
		reg [FBITS-1:0] 		f_raddr = 0;			// fifo current read address
		wire [FBITS-1:0] 		graddr;					// fifo current read address for data outputs
		reg [FBITS-1:0] 		f_blkend = 0;			// memorized address of block end or start of currently written block
		wire [10:0] 			fifo_free;				// number of words availiable for the next block
		wire						fifo_full;				// fifo cannot accept next block

	//		state mathine definitions
		localparam ST_IDLE   = 0;
		localparam ST_MTRIG  = 1;
		localparam ST_MTIME  = 2;
		localparam ST_MTCOPY = 3;
		localparam ST_MTOK	= 4;
		localparam ST_MTCLR	= 5;
		localparam ST_STDEL  = 6;
		localparam ST_STRIG  = 7;
		localparam ST_STPED	= 8;
		localparam ST_STCOPY = 9;
		localparam ST_STCLR	= 10;

		reg [3:0] 				trg_state = ST_IDLE;	// state
		reg [8:0] 				to_copy = 0;			// number of words from CB left for copying
		reg [8:0] 				blklen;					// block length derived from winlen
		reg 						zflag = 0;				// flag to apply zero suppression to the current block
		reg						blkpar = 0;				// sequential parity of any sent block
		reg						mtrg_clr;				// flag to indicate end of master trigger block writing
		reg						mtrg_clr_a;				// flag to indicate end of master trigger block writing reclocked to ADCCLK
		reg						strg_clr;				// flag to indicate end of self trigger block writing
		reg						strg_clr_a;				// flag to indicate end of self trigger block writing reclocked to ADCCLK

	// 4 word circular buffer to resync ADC data (ped subtracted) to clk for trigger sum calculations
		reg [15:0] 			d2sumfifo [7:0];			//	buffer itself
		reg [2:0] 			d2sum_waddr = 0;			// write address
		reg [2:0] 			d2sum_raddr = 2;			// read address
		reg 					d2sum_arst = 0;			// sync as generated at ADCCLK
		reg 					d2sum_arst_d = 0;			// sync as felt at clk
	// test mode support
		reg [1:0]			testp = 0;
	
//		pedestal calculation (round rather than truncate to avoid average buildup in summing)
	always @ (posedge ADCCLK) begin
		if (~pedmode | ((ADCDAT > ped_s - pedrange) & (ADCDAT < ped_s + pedrange))) begin
			if (&pedcnt) begin
				// on full pedcnt, update calculated value
				pedcnt <= 0;
				pedsum <= ADCDAT;
				if (~pedmode) begin
					// Full update with new value (round rather than truncate)
					if (pedsum[PBITS-1]) begin
						ped_s <= pedsum[PBITS+ABITS-1:PBITS] + 1;
					end else begin
						ped_s <= pedsum[PBITS+ABITS-1:PBITS];
					end
				end else begin
					// increment if greater than (ped_s + 0.5) or decrement if less than (ped_s - 0.5)
					if (pedsum[PBITS+ABITS-1:PBITS-1] > {ped_s, 1'b0}) begin
						ped_s <= ped_s + 1;
					end else if (pedsum[PBITS+ABITS-1:PBITS-1] < {ped_s_m1, 1'b1}) begin
						ped_s <= ped_s - 1;
					end
				end
			end else begin
				pedcnt <= pedcnt + 1;
				pedsum <= pedsum + ADCDAT;
			end
			if (~pedinh & (pedcnt == 0)) begin
					// on zero pedcnt update used value if allowed
					ped_c <= ped_s;
			end
			ped_pulse <= (pedcnt < 3) ? 1 : 0;
		end
	end
	//	do safe pedestal output
	always @ (posedge clk) begin
		ped_pulse_d <= {ped_pulse_d[0], ped_pulse};
		if (ped_pulse_d == 2'b01) begin
			ped <= ped_s;
			ped_b <= ped_c;
		end
	end

// 	pedestal subtraction and inversion
//		test pulse processing
	always @ (posedge ADCCLK) begin
		if (testmode) begin
			pdata <= (testp == 2'b01) ? 256 : 0;
		end else if (raw) begin
			pdata <= {{(16-ABITS){1'b0}} ,ADCDAT};
		end else if (invert) begin
			pdata <= ped_c - ADCDAT;
		end else begin
			pdata <= ADCDAT - ped_c;
		end
		testp <= {testp[0], testpulse};
	end

//		circular memory buffer
	// write at ADCCLK
	always @ (posedge ADCCLK) begin
		cbuf[cb_waddr] <= pdata;
		cb_waddr <= cb_waddr + 1;
	end
	// read at clk
	always @ (posedge clk) begin
		cb_data <= cbuf[cb_raddr];
	end

// reclock trigger ends
	always @ (posedge ADCCLK) begin
		mtrg_clr_a <= mtrg_clr;
		strg_clr_a <= strg_clr;
	end

//		self trigger & prescale 
	always @ (posedge ADCCLK) begin
		inh <= inhibit;		// relatch inhibit to ADCCLK
		if (~stmask & ~raw & ~inh) begin
			if (pdata > $signed({1'b0,sthr})) begin
				if (~discr) begin
					// crossing threshold (for the first time)
					discr <= 1;
					// prescale threshold crossings
					if (|presc_cnt) begin
						presc_cnt <= presc_cnt - 1;
					end else begin
						presc_cnt <= prescale;
						// produce self trigger and memorize current position in circular buffer
						strig <= 1;
						strig_cnt <= strig_cnt + 1;	// count self triggers after prescale independently of transmission
						str_addr <= cb_waddr;
					end
				end
			end else if (pdata <= $signed({1'b0,sthr[ABITS-1:1]})) begin
				// HALF threshold crossed back (noise reduction)
				discr <= 0;
				// finish with trigger on command from state machine
				if (strg_clr_a) strig <= 0;
			end 
		end else begin
			strig <= 0;
		end
	end

//		master trigger	and token
	always @ (posedge ADCCLK) begin
		if (adc_trig & ~mtrig & ~tmask) begin
			// catch the first adc_trig and corresponding trigger time
			mtrig <= 1;
			mtr_addr <= cb_waddr;
			tr_time <= trig_time;
		end else if (mtrg_clr_a) begin
			// finish with trigger on command from state machine after token is accepted
			mtrig <= 0;
		end
	end
	// process token from GTP (appears later than all adc_trig's)
	always @ (posedge clk) begin
		if (mtrig_c) begin
			// catch token from GTP
			if (tok_vld) begin
				tok_got <= 1;
				tr_tok <= token[10:0];
			end
		end else begin
			// clear token flag on trigger end
			tok_got <= 0;
		end
	end

//		block writing on triggers with state machine
	assign 	fifo_free = f_raddr - f_blkend;
	assign 	fifo_full = (fifo_free < (winlen + 3)) & (fifo_free != 0);

	// state machine
	always @ (posedge clk) begin
		strg_clr <= 0;		// default
		mtrg_clr <= 0;		// default
		missed <= 0;		// default
		blklen <= winlen + 2;		// relatch for better timing
		tofifo = 0;
		mtrig_c <= mtrig;				// reclock master trigger
		strig_c <= strig;				// reclock self trigger
		tr_time_c <= tr_time;		// reclock trigger time
		strig_cnt_c <= strig_cnt;	// reclock self trigger number
//		state machine
		case (trg_state) 
		ST_IDLE: begin 
			if (mtrig_c) begin
				if (~fifo_full) begin
					// write nothing on zero winlen
					if (~|winlen) begin
						trg_state <= ST_MTCLR;
					end else begin
					// we can write to fifo, write CW
						tofifo = {1'b1, num, blklen};
						f_waddr <= f_waddr + 1;
						to_copy <= winlen;
						trg_state <= ST_MTRIG;
					end
				end else begin
					// we can't write to fifo -- just finish the trigger
					missed <= 1;
					trg_state <= ST_MTCLR;
				end
			end else if (strig_c) begin
				strig_del <= STDELAY;
				trg_state <= ST_STDEL;
			end
		end
		ST_MTRIG: begin
			// just skip one word, we cannot write token here
			f_waddr <= f_waddr + 1;
			cb_raddr <= mtr_addr - mwinbeg;	// prepare for reading from circular buffer
			trg_state <= ST_MTIME;
		end
		ST_MTIME: begin
			// write high resolution time
			tofifo = {13'h0000, tr_time_c};
			f_waddr <= f_waddr + 1;
			cb_raddr <= cb_raddr + 1;			// preincrement circular buffer read address
			zflag <= ~raw;							// set zero suppression flag (no zero suppression in raw mode)
			trg_state <= ST_MTCOPY;
		end
		ST_MTCOPY: begin
			// stream data from circular buffer to fifo
			tofifo = {1'b0, cb_data[14:0]};
			f_waddr <= f_waddr + 1;
			cb_raddr <= cb_raddr + 1;
			to_copy <= to_copy - 1;
			if (($signed(cb_data) >= $signed({1'b0, zthr})) 
				& (winlen - to_copy >= zbeg) 
				& (winlen - to_copy < zend)) zflag <= 0;	// remove ZS flag if signal is above threshold
			if (to_copy == 1)	begin
				f_waddr <= f_blkend + 1;			// prepare waddr for token writing
				f_waddr_s <= f_waddr + 1;			// save next waddr for further restoration
				trg_state <= ST_MTOK;
			end
		end
		ST_MTOK: begin
			if (zflag) begin
				// if zero suppression happens, restore write pointer to the beg of block and finish with trigger
				f_waddr <= f_blkend;
				trg_state <= ST_MTCLR;
			end else if (tok_got) begin
				// no ZS -- wait for token, write it to proper place and update block end pointer
				tofifo = {2'b00, raw, 1'b1, blkpar, tr_tok};
				f_waddr <= f_waddr_s;			// restore waddr to the first empty word
				f_blkend <= f_waddr_s;			// f_blkend now points to the end of the newly written block
				blkpar <= ~blkpar;
				trg_state <= ST_MTCLR;
			end
		end
		ST_MTCLR: begin		// we can appear here with slftrigger not finished, clear both and wait for both to be cleared
			mtrg_clr <= 1;
			if (strig_c) strg_clr <= 1;
			if (~mtrig_c & ~strig_c)
				trg_state <= ST_IDLE;
		end
		ST_STDEL: begin
			if (mtrig_c) begin		// catch master trigger
				trg_state <= ST_IDLE;
			end else begin
				if (|strig_del) begin	// just wait
					strig_del <= strig_del - 1'b1;
				end else begin				// start selftrigger record
					if (~fifo_full) begin
						// write nothing on zero winlen
						if (~|winlen) begin
							trg_state <= ST_STCLR;
						end else begin
							// we can write to fifo, write CW
							tofifo = {1'b1, num, blklen};
							f_waddr <= f_waddr + 1;
							to_copy <= winlen;
							trg_state <= ST_STRIG;
						end
					end else begin
						// we can't write to fifo -- just finish the trigger
						missed <= 1;
						trg_state <= ST_STCLR;
					end
				end
			end
		end
		ST_STRIG: begin
			if (mtrig_c) begin
			// enforce master trigger priority
				f_waddr <= f_blkend;
				trg_state <= ST_IDLE;
			end else begin
			// write sequential self trigger number
				tofifo = {4'h0, blkpar, 1'b0, strig_cnt_c};
				f_waddr <= f_waddr + 1;
				cb_raddr <= str_addr - swinbeg;	// prepare for reading from circular buffer
				trg_state <= ST_STPED;
			end
		end
		ST_STPED: begin
			if (mtrig_c) begin
			// enforce master trigger priority
				f_waddr <= f_blkend;
				trg_state <= ST_IDLE;
			end else begin
			// write pedestal value
				tofifo = {{(16-ABITS){1'b0}}, ped_b};
				f_waddr <= f_waddr + 1;
				cb_raddr <= cb_raddr + 1;			// preincrement circular buffer read address
				trg_state <= ST_STCOPY;
			end
		end
		ST_STCOPY: begin
			if (mtrig_c) begin
			// enforce master trigger priority
				f_waddr <= f_blkend;
				trg_state <= ST_IDLE;
			end else begin
				// stream data from circular buffer to fifo
				tofifo = {1'b0, cb_data[14:0]};
				f_waddr <= f_waddr + 1;
				cb_raddr <= cb_raddr + 1;
				to_copy <= to_copy - 1;
				if (to_copy == 1)	begin
					f_blkend <= f_waddr + 1;		// f_blkend now points to the end of the newly written block
					blkpar <= ~blkpar;
					trg_state <= ST_STCLR;
				end
			end
		end
		ST_STCLR: begin		// we go to idle if we recieve master trigger or finish with self trigger
			strg_clr <= 1;
			if (mtrig_c | ~strig_c)
				trg_state <= ST_IDLE;
		end
		default: trg_state <= ST_IDLE;
		endcase
		// fifo
		// write fifo
		fifo[f_waddr] <= tofifo;
		// read fifo
		f_data <= fifo[graddr];
		// increment raddr on data outputs
		if (have) begin
			f_raddr <= f_raddr + 1;
		end
	end

	assign dout = f_data;
	assign have = give & (f_raddr != f_blkend);
	assign graddr = (have) ? (f_raddr + 1) : f_raddr;

//		to total sum -- resync adc data to clk
	// fill buffer at ADFCCLK
	always @ (posedge ADCCLK) begin
		// send zero if masked or raw data requested
		d2sumfifo[d2sum_waddr] <= ((~smask) & (~raw)) ? pdata : 0;
		d2sum_waddr <= d2sum_waddr + 1;
		d2sum_arst <= (d2sum_waddr == 0) ? 1 : 0;
	end
	// read buffer at clk
	always @ (posedge clk) begin
		d2sum_arst_d <= d2sum_arst;
		d2sum <= d2sumfifo[d2sum_raddr];
		d2sum_raddr <= (d2sum_arst_d) ? 0 : d2sum_raddr + 1;
	end

endmodule
