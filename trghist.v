`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 	ITEP
// Engineer: 	SvirLex
// 
// Create Date:     18:04:52 06/17/2015 
// Design Name: 	fpgachan
// Module Name:     trghist 
// Project Name: 	uwfd64
// Target Devices: 	xc6lsx45t
// Tool versions: 
// Description: 	takes master trigger and put sum64 history block
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//		Blocks sent to arbitter 
//	0	1CC0 000L LLLL LLLL - CC - 2-bit Xilinx number which produced the block ; 
//									 LLLLLLLLL - 9-bit block length in 16-bit words not including CW, L = WinLen + 2
// 1	0ttt penn nnnn nnnn - ttt - trigger block type (4 - trigger history) ;
//									 n - master : 10-bit trigger token from gtp, e - token error (as recieved by main FPGA)
//									 p - sent block sequential number LSB, independently on master/self
//	2	0000 0000 0000 0000 - not used
//	3	0XXX XXXX XXXX XXXX - L-2 words of ADC signed data after pedestal subtraction or ADC raw data
//
//////////////////////////////////////////////////////////////////////////////////
module trghist # (
		parameter		CBITS		= 10,	// number of bits in the circular buffer addr
		parameter		FBITS		= 11	// number of bits in output fifo addr
	) (
		input 				clk,		// master clock
		input [14:0] 		data,		// input data - sum of 64 channels
		input [CBITS-1:0]	winbeg,	// trigger history window begin
		input [8:0]			winlen,	// trigger history window length
		// communication to sending arbitter
		input					give,		// arbitter wants history data
		output				have,		// history data ready
		output [15:0]		dout,		// history data to arbitter
		input					mtrig,	// master tirgger input - asynchronous
		input					menable,	// master trigger data block enable
		input [15:0]		token,	// trigger token
		input					tok_vld,	// token valid
		input [1:0]			num,		// Xilinx number
		output reg			missed	// no room for trigger in the FIFO
   );

	// circular buffer for trigger history
	reg [14:0] 				cbuf [2**CBITS-1:0];	// buffer itself
	reg [14:0]				cb_data = 0;			// buffer output data
	reg [CBITS-1:0]		cb_waddr = 0;			// write address	
	reg [CBITS-1:0]		cb_raddr = 0;			// read address	

	// Output fifo
	reg [15:0] 				fifo [2**FBITS-1:0];	// fifo itself
	reg [15:0]				f_data = 0;				// fifo output data
	reg [FBITS-1:0]		f_waddr = 0;			// write address	
	reg [FBITS-1:0]		f_blkend = 0;			// block end 
	reg [FBITS-1:0]		f_waddr_s = 0;			// write address stored
	reg [FBITS-1:0]		f_raddr = 0;			// read address	

	reg 						mtrig_c	= 0;			// master trigger clocked to clk
	wire [10:0]				fifo_free;
	wire						fifo_full;
	reg [8:0]				blklen;
	reg [8:0]				to_copy;
	reg [15:0]				tofifo;
	reg                  tok_got;
	reg [10:0]				token_s;
	reg [1:0]				trg_state;
	reg						blkpar = 0;
	reg						skip;
	
	localparam	ST_IDLE = 0;
	localparam	ST_ZERO = 1;
	localparam	ST_COPY = 2;
	localparam	ST_TOKEN = 3;

	assign 	fifo_free = f_raddr - f_blkend;
	assign 	fifo_full = (fifo_free < (winlen + 3)) & (|fifo_free);

	always @ (posedge clk) begin
//		circular buffer for trigger history
		cbuf[cb_waddr] <= data;		// 15 bit only
		cb_waddr <= cb_waddr + 1;
		cb_data <= cbuf[cb_raddr];
//		fifo		
		//		block writing on triggers with state machine

// state machine
		blklen <= winlen + 2;			// relatch for better timing
		tofifo = 0;
		mtrig_c <= mtrig;
		if (tok_vld) begin
			token_s <= token[10:0];
			tok_got <= 1;
		end
//		state machine
		case (trg_state) 
		ST_IDLE: begin 
			if (mtrig_c) begin
				tok_got <= 0;
				if (~fifo_full) begin
					// write nothing on zero winlen
					if ((~|winlen) | ~menable) begin
						skip <= 1;
						trg_state <= ST_TOKEN;
					end else begin
					// we can write to fifo, write CW
						skip <= 0;
						missed <= 0;
						tofifo = {1'b1, num, 4'h0, blklen};
						f_waddr <= f_waddr + 2;
						to_copy <= winlen;
						cb_raddr <= cb_waddr - winbeg;
						trg_state <= ST_ZERO;
					end
				end else begin
					// we can't write to fifo -- just finish the trigger
					skip <= 1;
					missed <= 1;
					trg_state <= ST_TOKEN;
				end
			end
		end
		ST_ZERO: begin
			tofifo = 0;
			f_waddr <= f_waddr + 1;
			trg_state <= ST_COPY;
		end
		ST_COPY: begin
			// stream data from circular buffer to fifo
			tofifo = {1'b0, cb_data};
			f_waddr <= f_waddr + 1;
			cb_raddr <= cb_raddr + 1;
			to_copy <= to_copy - 1;
			if (to_copy == 1)	begin
				f_waddr <= f_blkend + 1;			// prepare waddr for token writing
				f_waddr_s <= f_waddr + 1;			// save next waddr for further restoration
				trg_state <= ST_TOKEN;
			end
		end
		ST_TOKEN: begin
			if (tok_got) begin
				if (skip) begin
					trg_state <= ST_IDLE;
				end else begin
				// 
					tofifo = {4'h4, blkpar, token_s};
					f_waddr <= f_waddr_s;			// restore waddr to the first empty word
					f_blkend <= f_waddr_s;			// f_blkend now points to the end of the newly written block
					blkpar <= ~blkpar;
					trg_state <= ST_IDLE;
				end
			end
		end
		endcase
		// write fifo
		fifo[f_waddr] <= tofifo;
		// read fifo
		f_data <= fifo[(have) ? (f_raddr + 1) : f_raddr];
		// increment raddr on data outputs
		if (have) begin
			f_raddr <= f_raddr + 1;
		end
	end

	assign dout = f_data;
	assign have = give & (f_raddr != f_blkend);

endmodule
