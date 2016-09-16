`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 ITEP
// Engineer: 		 SvirLex
// 
// Create Date:    19:59:41 06/18/2015 
// Design Name: 	 chanfpga
// Module Name:    capreg 
// Project Name: 	 wfd125
// Revision 0.01 - File Created
// Additional Comments: 
//		Captures active bits on input and allows reading from WB
//		Any write causes clear of all bits
//
//////////////////////////////////////////////////////////////////////////////////
module capreg # (
	parameter	ADRBITS = 1
	)
	(
   input 		[15:0]				wb_dat_i,
   output reg	[15:0] 				wb_dat_o,
   input 								wb_we,
   input 								wb_clk,
   input 								wb_cyc,
   output reg 							wb_ack,
   input 								wb_stb,
	input [ADRBITS-1:0]				wb_adr,
   input [16*(2**ADRBITS)-1:0] 	inbits
   );

	reg [16*(2**ADRBITS)-1:0]		capture;		// capture register
	
	always @ (posedge wb_clk) begin
		// capture
		capture <= capture | inbits; 
		// WB
		wb_ack <= 0;
		if (wb_cyc & wb_stb) begin
			wb_ack <= 1;
			if (wb_we) begin
				// reset on writes
				capture <= 0;
			end else begin
				// give out data on reads
				wb_dat_o <= capture[16*wb_adr +:16];
			end
		end
	end

endmodule
