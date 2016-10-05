`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    18:51:41 09/16/2016 
// Design Name: 
// Module Name:    doubletrig 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description: produce trigger on a pair of two channels if both channels are
//	above threshold_A and thier sum is above threshold_B.
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module doubletrig # (
	parameter ABITS = 12
)(
	input			ADCCLK,		// ADC clock, common for both channels
	input [31:0]		dpdata,		// data from 2 prc1chan's, ADC clocked, ped subtracted
	input [ABITS-1:0] 	ithr,		// individual channel threshold
	input [ABITS-1:0] 	sthr,		// two channel sum threshold
	input 			inhibit,	// cumulative inhibit
	input			exttrig,	// external trigger
	output reg		trig		// resulting trigger
);
	 
	reg signed [15:0]	ch0 = 0;
	reg signed [15:0]	ch1 = 0;
	reg signed [15:0]	ch0_p = 0;
	reg signed [15:0]	ch1_p = 0;
	reg signed [16:0]	s2 = 0;
	reg			ddiscr = 0;
	reg [1:0]		ext_d = 0;
	 
	always @ (posedge ADCCLK) begin
		ch0_p <= dpdata[15:0];
		ch1_p <= dpdata[31:16];
		ch0 <= ch0_p;
		ch1 <= ch1_p;
		s2 <= ch0_p + ch1_p;
		trig <= 0;

		if (~inhibit) begin
			if ((ch0 > $signed({1'b0,ithr})) & (ch1 > $signed({1'b0,ithr})) & (s2 > $signed({1'b0,sthr}))) begin
				if (~ddiscr) begin
					// crossing threshold (for the first time)
					ddiscr <= 1;
					trig <= 1;	// single pulse
				end
			end else if (s2 <= $signed({1'b0,sthr[ABITS-1:1]})) begin
				// HALF threshold crossed back (noise reduction)
				ddiscr <= 0;
			end 
		end else begin
			ddiscr <= 0;
		end
		if (ext_d == 2'b01) trig <= 1;
		ext_d <= {ext_d[0], exttrig};
	end

endmodule
