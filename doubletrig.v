`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    18:51:41 09/16/2016 
// Design Name: 
// Module Name:    doubletrig 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
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
	 )
	 (
    input 					ADCCLK,		// ADC clock, common for both channels
    input [31:0] 			dpdata,		// data from 2 prc1chan's, ADC clocked, ped subtracted
    input [ABITS-1:0] 	ithr,			// individual channel threshold
    input [ABITS-1:0] 	sthr,			// two channel sum threshold
    input 					raw,			// raw mode inhibits
	 input 					dtmask,		// mask bit inhibits
    output reg				ddiscr		// discriminator output		
    );
	 
	 wire signed [15:0]	ch0;
	 wire signed [15:0]	ch1;
	 wire signed [16:0]  s2;
	 
	 assign ch0 = dpdata[15:0];
	 assign ch1 = dpdata[31:16];
	 assign s2 = ch0 + ch1;

	always @ (posedge ADCCLK) begin
		if (~dtmask & ~raw) begin
			if ((ch0 > $signed({1'b0,ithr})) & (ch1 > $signed({1'b0,ithr})) & (s2 > $signed({1'b0,sthr}))) begin
				if (~ddiscr) begin
					// crossing threshold (for the first time)
					ddiscr <= 1;
				end
			end else if (s2 <= $signed({1'b0,sthr[ABITS-1:1]})) begin
				// HALF threshold crossed back (noise reduction)
				ddiscr <= 0;
			end 
		end else begin
			ddiscr <= 0;
		end
	end

endmodule
