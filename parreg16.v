`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    19:59:41 09/26/2014 
// Design Name: 
// Module Name:    inoutreg 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
// 	Block of 16 bit registers
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module parreg16(wb_dat_i, wb_dat_o, wb_we, wb_clk, wb_cyc, wb_ack, wb_stb, wb_adr, reg_o);
	parameter ADRBITS = 1;
   input [15:0] wb_dat_i;
   output reg [15:0] wb_dat_o;
   input wb_we;
   input wb_clk;
   input wb_cyc;
   output reg wb_ack;
   input wb_stb;
	input [ADRBITS-1:0] wb_adr;
   output [16*2**ADRBITS - 1:0] reg_o;
	 
	reg [15:0] register [2**ADRBITS - 1:0];
	
	genvar i;
	generate
	for (i = 0; i < 2**ADRBITS; i = i + 1) begin: UFOR
		assign reg_o[16*i+15:16*i] = register[i];
	end
	endgenerate
	
	always @ (posedge wb_clk) begin
		wb_dat_o <= register[wb_adr];
		if (wb_cyc & wb_stb & wb_we) register[wb_adr] <= wb_dat_i;
		wb_ack <= wb_cyc & wb_stb;
	end

endmodule
