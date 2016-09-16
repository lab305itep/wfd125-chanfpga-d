`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 ITEP
// Engineer: 		 SvirLex
// 
// Create Date:    18:55:39 04/28/2015 
// Design Name: 	 fpga_chan
// Module Name:    bitslip 
// Project Name: 	 wfd125
// Revision 0.01 - File Created
// Additional Comments: 
//
//		Generates BITSLIP pulse when DATA is not equal to the 111000 sample,
//		but next pulse is not earlier than 16 CLK after that
//
//////////////////////////////////////////////////////////////////////////////////
module bitslip(
    input 			CLK,		// ADC clock divided
    input [5:0] 	DATA,		// ADC one line 6-bit data, CLK timed
	 input 			BSENB,	// allow bitslip
    output reg		BS			// bitslip
    );

	localparam [5:0] 	FRAME = 6'b111000;
	reg [3:0] 			BSCNT;

	always @ (posedge CLK) begin
		if (BSENB & ~(|BSCNT) & DATA != FRAME) begin
			BS <= 1;
			BSCNT <= 15;
		end else begin
			BS <= 0;
		end
		if (|BSCNT) BSCNT <= BSCNT - 1;
	end 


endmodule
