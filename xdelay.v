`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ITEP
// Engineer: SvirLex
// 
// Create Date:    16:59:57 06/17/2015 
// Design Name: 	chanfpga
// Module Name:     xdelay 
// Project Name: 	uwfd64
// Target Devices:  xc6lsx45t
// Tool versions: 
// Description: 	circular buffer for summing delay
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module xdelay #(
		parameter		DBITS		= 5	// number of bits in delay line addr, need at least 5 for numbers as large as 23
		)(
		input [15:0] din,
		output reg [15:0] dout,
		input clk,
		input [DBITS-1:0] xdelay
		);
	
	reg [15:0] 				dbuf [2**DBITS-1:0];	// buffer itself
	reg [DBITS-1:0]			db_waddr = 0;			// write address	
	reg [DBITS-1:0]			db_raddr = 0;			// read address	

//		Delay local result	
	always @ (posedge clk) begin
		dbuf[db_waddr] <= din;
		db_waddr <= db_waddr + 1;
		db_raddr <= db_waddr - xdelay;	// raddr is less then waddr at least by 1
		dout <= dbuf[db_raddr];
	end

endmodule
