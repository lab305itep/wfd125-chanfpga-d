`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:			 ITEP 
// Engineer: 		 SvirLex
// 
// Create Date:    14:04:00 10/28/2014 
// Design Name: 	 chanfpga
// Module Name:    sumcalc 
// Project Name: 	 wfd125
// Description: 
//		Calculats local summ of 16 channels and sends it to to other X's, sends comma instead of zero value
//		Delays local sum to be added with data from other X's to make total sum.
//		Issue request for master trigger if total sum exceeds threshold
//		Forms and sends trigger formation history block
// Revision 0.01 - File Created
// Revision 0.02 - modified for signed data and programmable delay
//
//////////////////////////////////////////////////////////////////////////////////
module sumcalc # (
		parameter		DBITS		= 5,	// number of bits in delay line addr, need at least 5 for numbers as large as 23
		parameter		CBITS		= 10,	// number of bits in the circular buffer addr
		parameter		FBITS		= 11	// number of bits in output fifo addr
	)
	(
		input 				clk,			// master clock
		input [255:0] 		data,			// input data from local channels clk timed
		input [255:0]		coef,			// per channel coefficients for trigger
		// communication to other X's
		input [47:0] 		xdata,		// sums from 3 other xilinxes
		input [2:0]  		xcomma,		// commas from other xilinxes
		output reg [15:0]	sumres,		// 16-channel sum to other X's
		output reg 			sumcomma,	// comma / data to other X's
		// programmable parameters
		input [15:0] 		s64thr,		// 64-channel sum threshold
		input [DBITS-1:0]	xdelay,		// delay for local sum to be added to other X's		
		input [CBITS-1:0]	winbeg,		// trigger history window begin
		input [8:0]			winlen,		// trigger history window length
		// communication to sending arbitter
		input					give,			// arbitter wants history data
		output				have,			// history data ready
		output [15:0]		dout,			// history data to arbitter
		output 				missed,		// history fifo is full and missed a trigger
		// master trigger
		output reg 			trigout,		// 64-channel trigger to main
		input					mtrig,		// master serial tirgger input
		input					menable,		// master trigger data block enable
		input [15:0]		token,		// trigger token
		input					tok_vld,		// token valid
		input	[1:0]			num			// Xilinx number
   );

	localparam	CH_COMMA = 16'h00BC;		// comma K28.5

	// local sum
	wire signed [15:0] 	sum16;		// full local sum
	wire signed [15:0] 	db_data;		// full local sum delayed
	wire [255:0]			datac;		// corrected data
	
	// master trigger 
	reg signed [17:0]		sum64;		// sum of 4 X's
	reg 					trigout_s;		// sum above threshold

//		Amplification correction
	genvar i;
	generate
		for (i=0; i<16; i = i + 1) begin: GMULT
			normmult UMULT (
				.clk	(clk),
				.din	(data[16*i+15:16*i]),
				.dout	(datac[16*i+15:16*i]),
				.coef	(coef[16*i+15:16*i])
			);
		end
	endgenerate

//		Calculate local sum and send it
	sum16 USUM16(
		.clk	(clk),
		.din	(datac),
		.sum	(sum16)
	);
	always @ (posedge clk) begin
		// sum16 suuposed to be noisy around zero
		if (sum16 != 0) begin
			sumres <= sum16;
			sumcomma <= 0;
		end else begin
			// we send comma instead of zero value
			sumcomma <= 1;
			sumres <= CH_COMMA;
		end
	end

//		Delay local data
	xdelay #(.DBITS(DBITS)) UDELAY (
		.clk	(clk),
		.din	(sum16),
		.dout	(db_data),
		.xdelay	(xdelay)
	);
	
//		Master trigger
	always @ (posedge clk) begin
		sum64 <= db_data + $signed((~xcomma[0]) ? xdata[15:0] : 16'h0000) + 
					$signed((~xcomma[1]) ? xdata[31:16] : 16'h0000) + 
					$signed((~xcomma[2]) ? xdata[47:32] : 16'h0000);
		trigout <= 0;		// default
		if (sum64 > $signed({2'b00, s64thr})) begin
			// generate trigger when sum exceeds threshold
			trigout_s <= 1;
			if (!trigout_s) begin
				trigout <= 1;				// one clk pulse
			end
		end else if (sum64 <= $signed({3'b000, s64thr[15:1]})) begin
			// ready for new trigger when sum below half threshold
			trigout_s <= 0;
		end
	end
	
	trghist #(
		.CBITS(CBITS),
		.FBITS(FBITS)
	) UHIST (
		.clk		(clk),		// master clock
		.data		(sum64[17:3]),	// input data - sum of 64 channels, ignore 3 LSB
		.winbeg		(winbeg),	// trigger history window begin
		.winlen		(winlen),	// trigger history window length
		// communication to sending arbitter
		.give		(give),		// arbitter wants history data
		.have		(have),		// history data ready
		.dout		(dout),		// history data to arbitter
		.mtrig		(mtrig),	// master tirgger input - asynchronous
		.menable	(menable),	// master trigger data block enable
		.token		(token),	// trigger token
		.tok_vld	(tok_vld),	// token valid
		.num		(num),		// Xilinx number
		.missed		(missed)	// history fifo is full and missed a trigger
	);
endmodule
