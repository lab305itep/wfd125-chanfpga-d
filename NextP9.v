`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    13:54:08 10/31/2014 
// Design Name: 
// Module Name:    NextP9 
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

module NextP9(
    input [11:0] N,
    output [11:0] NextN
    );

   function  [11:0] nextP9;
      input [11:0] n;
		integer k;
      begin
         nextP9 = n;
         for (k=0; k<12; k=k+1) begin
            nextP9 = {nextP9[10:0], nextP9[4] ^ nextP9[8]};
         end
      end
   endfunction

	assign NextN = nextP9 (N);

endmodule
