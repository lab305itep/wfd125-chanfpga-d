`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		ITEP
// Engineer: 		SvirLex
// 
// Create Date:    00:17:59 06/04/2015 
// Design Name: 	 fpga_chan
// Module Name:    snd_arb 
// Project Name: 	 wfd125
// Target Devices: s6
//
// Additional Comments: 
//		Sends k-char meaning trigger on trigger request - out of band
//		Polls channel fifo's in a round-robbin manner and sends one block of data
//		from each fifo if data is availiable
//		Sends commas in between
//////////////////////////////////////////////////////////////////////////////////

module snd_arb #(
		parameter					NFIFO =17
		) (
		input							clk,			// gtp clock
		// fifo control and data
//		output reg [NFIFO-1:0]	arb_want,	// arbitter wants data from one of the fifos
		output [NFIFO-1:0]		arb_want,	// arbitter wants data from one of the fifos
		input [NFIFO-1:0]			fifo_have,	// fifo reply to arb_want, asyncronous
		input	[NFIFO*16-1:0]		datain,		// data, valid with fifo_have
		// fifo errors
		output reg					err_undr,	// underrun error -- CW accepted earlier than expected
		output reg					err_ovr,		// overrun error -- CW accepted later than expected
		// trigger from summing to be sent to main
		input							trig,		// 1 clk pulse to propagate formed trigger to main
		// GTP data for sending
		output reg [15:0]			dataout,	
		output reg					kchar
		);

	localparam	CH_COMMA = 16'h00BC;		// comma K28.5
	localparam  CH_TRIG  = 16'h801C;		// K-character K28.0

	reg [4:0]		rr_cnt = 0;			// counter for Round Robbin arbitration
	wire 				fifohave;			// OR of dvalids from fifos, actually have from currently selected fifo
	reg [8:0]		towrite = 0;		// number of words in block to write
	wire				nextf;				// force increment of RR counter (after block is fully read)
	wire [15:0]		datamux [NFIFO-1:0];

	genvar i;
   generate
      for (i=0; i<NFIFO; i=i+1) 
      begin: gwant
			assign datamux[i] = datain[16*i +:16];
			assign arb_want[i] = (rr_cnt == i) & ~trig;
      end
   endgenerate

	// RR arbitration
	assign	fifohave = |fifo_have;
	assign	nextf = ((towrite == 2) & ~kchar) | ((towrite == 1) & kchar);		// ~trig assumed in both terms

	always @ (posedge clk) begin
		err_undr <= 0;
		err_ovr <= 0;
		if (trig) begin
			// send trigger out of band
			dataout <= CH_TRIG;
			kchar <= 1;
		end else begin
			// advance round robbin counter
			if ((~fifohave) | nextf) begin
				if (rr_cnt == NFIFO-1) begin
					rr_cnt <= 0;
				end else begin
					rr_cnt <= rr_cnt + 1;
				end
			end
			// send data or comma
			if (fifohave) begin
				// send data if we have any
				dataout <= datamux[rr_cnt];
				kchar <= 0;
			end else begin
				// send comma if no data
				dataout <= CH_COMMA;
				kchar <= 1;
			end
		end
		
		// check block structure
		if (~kchar) begin
			// this is valid data, not comma and not trigger
			if (dataout[15]) begin
				// this is CW
				towrite <= dataout[8:0];		// number of words to write -1
				if (|towrite) begin
					err_undr <= 1;				// must accept next CW with towrite=0, otherwize it's too early
				end
			end else begin
				if (|towrite) towrite <= towrite - 1;
				else err_ovr <= 1;			// must have accepted CW with towrite=0, otherwize it's too late
			end
		end
		
	end

endmodule
