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
module doubletrig (
	input			ADCCLK,		// ADC clock, common for both channels
	input [31:0]		dpdata,		// data from 2 prc1chan's, ADC clocked, ped subtracted
	input [15:0] 		ithr,		// individual channel threshold
	input [15:0] 		sthr,		// two channel sum threshold
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
	reg 			ext_d = 0;
	reg 			inh = 0;
	 
	always @ (posedge ADCCLK) begin
		ch0_p <= dpdata[15:0];
		ch1_p <= dpdata[31:16];
		ch0 <= ch0_p;
		ch1 <= ch1_p;
		s2 <= ch0_p + ch1_p;
		trig <= 0;
		inh <= inhibit;

		if (~inh) begin
			if ((ch0 > $signed({1'b0,ithr})) & (ch1 > $signed({1'b0,ithr})) & (s2 > $signed({1'b0,sthr}))) begin
				if (~ddiscr) begin
					// crossing threshold (for the first time)
					ddiscr <= 1;
					trig <= 1;	// single pulse
				end
			end else if (s2 <= $signed({1'b0,sthr[15:1]})) begin
				// HALF threshold crossed back (noise reduction)
				ddiscr <= 0;
			end 
		end else begin
			ddiscr <= 0;
		end
		if (ext_d) trig <= 1;
	end
	
	always @(posedge ADCCLK or posedge exttrig) begin
		if (exttrig) begin
			ext_d <= 1;
		end else if (ext_d) begin
			ext_d <= 0;
		end
	end
						
endmodule
