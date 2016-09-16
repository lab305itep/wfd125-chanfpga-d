`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ITEP	
// Engineer: SvirLex
// 
// Create Date:    16:41:35 06/17/2015 
// Design Name:    chanfpga
// Module Name:    sum16 
// Project Name:   uwfd64
// Target Devices: xc6lsx45t
// Tool versions: 
// Description:    Do signed summ of 16 inputs in 2 clock ticks
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module sum16(
    input [255:0] din,
    output signed [15:0] sum,
    input clk
    );

	wire signed [15:0] term [15:0];
	reg signed [17:0] s4 [3:0];
	reg signed [19:0] s16;
	
	genvar i;
	generate
		for (i=0; i<16; i = i + 1) begin: UASS
			assign term[i] = din[16*i+15 : 16*i];
		end
	endgenerate

	integer j;
	always @(posedge clk) begin
		for (j=0; j<4; j = j + 1) s4[j] <= term[4*j] + term[4*j+1] + term[4*j+2] + term[4*j+3];
		s16 <= s4[0] + s4[1] + s4[2] + s4[3];
	end
	
	assign sum = s16[18:3];	// strip 2 bits right to the decimal point and 1 bit for the sign

endmodule
