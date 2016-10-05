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
module gtlatch(
	input 		adcclk,	// ADC clock
	input [21:0] 	gtin,	// External frequency counter
	input 		trig,	// Trigger
	input [2:0] 	phase,	// external frequency phase
	input [24:0] 	gtout	// latched result
);


endmodule
