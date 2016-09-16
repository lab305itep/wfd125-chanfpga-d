`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 	ITEP
// Engineer: 	SvirLex
// 
// Create Date:    01:28:38 11/05/2014 
// Design Name: 
// Module Name:    adccheck 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//		Check ADC data for given patterns
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//		Known pattern types:
//		0 - all zeroes
//		1 - all ones
//		4 - Checkerboard (0xAAA / 0x555)
//		5 - PN23 ITU 0.150 X**23 + X**18 + 1
//		6 - PN9  ITU 0.150 X**9  + X**5 + 1
//		7 - One-/zero-word toggle (0xFFF / 0)
//		9 - 0xAAA
//		10 - 1×sync  0000 0011 1111 
//		12 - Mixed frequency 1010 0011 0011
//////////////////////////////////////////////////////////////////////////////////
module adccheck(
		input [11:0] data,		// ADC data received
		input clk,					// ADC data clock
		output reg [15:0] cnt,	//	Error counter
		input count,				// Count errors enable
		input reset,				// Reset error counter
		input [3:0] type			// Pattern type
   );

	reg [11:0] data_d = 0;
	reg [11:0] data_dd = 0;
	wire [11:0] np23;
	wire [11:0] np9;
	reg [11:0] data_p = 0;
	
	NextP23 U23(
		.N(data_d),
		.PrevN(data_dd),
		.NextN(np23)
    );

	NextP9 U9(
		.N(data_d),
		.NextN(np9)
	);

	always @ (posedge clk) begin
		data_d <= data;
		data_dd <= data_d;
		case (type) 
			4'h0  : data_p <= 0;
			4'h1  : data_p <= 12'hFFF;
			4'h4  : data_p <= (data_d == 12'hAAA) ? 12'h555 : 12'hAAA;
			4'h5  : data_p <= np23;
			4'h6  : data_p <= np9;
			4'h7  : data_p <= (data_d == 12'hFFF) ? 0 : 12'hFFF;
			4'h9  : data_p <= 12'hAAA;
			4'hA  : data_p <= 12'h03F;
			4'hC	: data_p <= 12'hA33;
			default : data_p <= data;
		endcase
		if (reset) begin
			cnt <= 0;
		end else if (data_p != data_d && count && cnt != 16'hFFFF) begin
			cnt <= cnt + 1;
		end
	end

endmodule
