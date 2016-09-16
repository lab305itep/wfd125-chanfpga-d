`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    15:11:50 10/31/2014 
// Design Name: 
// Module Name:    NextP23 
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
module NextP23(
    input [11:0] N,
    input [11:0] PrevN,
    output [11:0] NextN
    );

   function  [11:0] nextP23;
      input [11:0] n;
      input [11:0] prevn;
		integer tmp;
		integer k;
      begin
         tmp = {prevn,n};
         for (k=0; k<12; k=k+1) begin
            tmp = {tmp[22:0], tmp[17] ^ tmp[22]};
         end
			nextP23 = tmp[11:0];
      end
   endfunction

	assign NextN = nextP23 (N, PrevN);


endmodule
