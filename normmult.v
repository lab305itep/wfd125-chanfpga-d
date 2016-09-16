`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ITEP
// Engineer: SvirLex
// 
// Create Date:    14:19:20 06/17/2015 
// Design Name: 	 chanfpga
// Module Name:    normmult 
// Project Name: 	 uwfd64
// Target Devices: xc6slx45t
// Tool versions: 
// Description:    Multiply raw data to normalizing coefficients
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module normmult(
    input [15:0] din,		// input data, signed, 13 active bits
    output [15:0] dout,		// output data, signed
    input clk,				// Master clock (125 MHz)
    input [15:0] coef		// unsigned, 1.0 = 0x8000
    );

	wire signed [17:0] termd;
	wire signed [17:0] termc;
	reg signed [35:0] product;
	
	assign termd = {din[15], din[15], din};		// ??? 5 extra birs
	assign termc = {2'b00, coef};				// 2 extra bits
	assign dout = product[28:13]; 				// We take here 2 bits right to the fixed point
	
	always @(posedge clk) product <= termd * termc;

endmodule
