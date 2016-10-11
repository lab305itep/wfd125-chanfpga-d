`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    20:26:03 10/06/2016 
// Design Name: 
// Module Name:    extfreq 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description: 	Get external frequency, multiply by 8 and export counter.
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module extfreq(
	input	 		freqin,		// external frequency input, 125/8 MHz expected
	output reg		freqout = 0,	// output 125 MHz
	output [21:0] 		counter,	// 125 MHz counter
	input 			reset,		// reset counter
	input 			inhibit,	// inhibit counter
	input 			dcmreset	// reset DCM
);

	reg			inh;		// inhibit latched by local frequency
	reg			res;		// reset latched by local frequency
	wire			dcmfb;		// DCM feedback
	wire			freq16;		// 16x of input frequency
	reg [22:0]		cnt = 0;	// internal counter

	   // DCM_SP: Digital Clock Manager
   //         Spartan-6
   // Xilinx HDL Language Template, version 14.7

	DCM_SP #(
		.CLKFX_MULTIPLY(16),	// Multiply value on CLKFX outputs - M - (2-32)
		.CLKIN_PERIOD(64.0),	// Input clock period specified in nS
		.CLK_FEEDBACK("1X")	// Feedback source (NONE, 1X, 2X)
	) DCM_SP_inst (
		.CLK0(dcmfb),		// 1-bit output: 0 degree clock output
		.CLKFX(freq16),		// 1-bit output: Digital Frequency Synthesizer output (DFS)
		.CLKFB(dcmfb),		// 1-bit input: Clock feedback input
		.CLKIN(freqin),		// 1-bit input: Clock input
		.DSSEN(0),		// 1-bit input: Unsupported, specify to GND.
		.PSCLK(0),		// 1-bit input: Phase shift clock input
		.PSEN(0),	 	// 1-bit input: Phase shift enable
		.PSINCDEC(0),		// 1-bit input: Phase shift increment/decrement input
		.RST(dcmreset)		// 1-bit input: Active high reset input
	);

	always @ (posedge freq16) begin
		freqout <= ~freqout;
		inh <= inhibit;
		res <= reset;
		if (res) begin
			cnt <= 0;
		end else if (~inh) begin
			cnt <= cnt + 1;
		end
	end
	
	assign counter = cnt[22:1];
	
endmodule
