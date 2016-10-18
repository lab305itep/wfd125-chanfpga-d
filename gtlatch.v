`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    20:36:34 10/05/2016 
// Design Name: 
// Module Name:    gtlatch 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description:    Latch external 125 MHz frequency counter with ADC clock.
//		The result includes phase as 3 LS bits
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module gtlatch #(
	parameter PHASE = "ENCODED"	// RAW / ENCODED
)(
	input			extclk,	// External frequency
	input [21:0] 		gtin,	// External frequency counter
	input 			trig,	// Trigger
	input [2:0] 		phase,	// external frequency phase encoded
	input [5:0]		raw,	// external frequency phase raw
	output [24:0]	 	gtout	// latched result
);

	reg [21:0]		gt = 0;
	reg			trig_e = 0;
	
	always @ (posedge extclk or posedge trig) begin
		if (trig) begin
			trig_e <= 1;
		end else if (trig_e) begin
			trig_e <= 0;
		end
	end

	always @ (posedge extclk) begin
		if (trig_e) begin
			gt <= gtin;
		end
	end
	generate 
		if (PHASE == "RAW") begin
			assign gtout = {gt[18:0], raw};
		end else begin
			assign gtout = {gt, phase};
		end
	endgenerate

endmodule
