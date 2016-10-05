`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    13:31:23 10/05/2016 
// Design Name: 
// Module Name:    ped_calc 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description:    calculates average pedestal
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module ped_calc #(
	parameter ABITS = 12,	// width of ADC data
	parameter PBITS = 12	// pedestal counter bits
)(
	input 		clk,	// System clock
	input 		adcclk,	// ADC clock
	input [ABITS-1:0] data,	// ADC data
	input 		inhibit,// inhibit pedestal update
	input 		mode,	// mode: 0 - always calc and update, 1 - use small signal condition and change by 1
	output reg [ABITS-1:0] ped,	// resulting pedestal, ADC clock
	output reg [ABITS-1:0] ped_clk	// resulting pedestal, system clock
);
	localparam [ABITS-1:0]	pedrange = 5;	// inteval for small signal in pedmode=1
	reg [PBITS+ABITS-1:0] 	pedsum = 0;	// sum for average
	reg [PBITS-1:0] 	pedcnt = 0;	// ped window counter
	reg [ABITS-1:0] 	ped_s = 0;	// currently calculated averaged value, ADCCLK timed
	wire [ABITS-1:0] 	ped_s_m1 = ped_s - 1'b1;	// currently calculated averaged value minus 1, ADCCLK timed
	reg 			ped_pulse = 0;	// ped ready
	reg [1:0]		ped_pulse_d = 0;	// for CLK sync

//		pedestal calculation (round rather than truncate to avoid average buildup in summing)
	always @ (posedge adcclk) begin
		if (~mode | ((data > ped_s - pedrange) & (data < ped_s + pedrange))) begin
			if (&pedcnt) begin
				// on full pedcnt, update calculated value
				pedcnt <= 0;
				pedsum <= data;
				if (~mode) begin
					// Full update with new value (round rather than truncate)
					if (pedsum[PBITS-1]) begin
						ped_s <= pedsum[PBITS+ABITS-1:PBITS] + 1;
					end else begin
						ped_s <= pedsum[PBITS+ABITS-1:PBITS];
					end
				end else begin
					// increment if greater than (ped_s + 0.5) or decrement if less than (ped_s - 0.5)
					if (pedsum[PBITS+ABITS-1:PBITS-1] > {ped_s, 1'b0}) begin
						ped_s <= ped_s + 1;
					end else if (pedsum[PBITS+ABITS-1:PBITS-1] < {ped_s_m1, 1'b1}) begin
						ped_s <= ped_s - 1;
					end
				end
			end else begin
				pedcnt <= pedcnt + 1;
				pedsum <= pedsum + data;
			end
			if (~inhibit & (pedcnt == 0)) begin
				// on zero pedcnt update used value if allowed
				ped <= ped_s;
			end
			ped_pulse <= (pedcnt < 3) ? 1 : 0;
		end
	end
	//	do safe pedestal output @ clk
	always @ (posedge clk) begin
		ped_pulse_d <= {ped_pulse_d[0], ped_pulse};
		if (ped_pulse_d == 2'b10) begin
			ped_clk <= ped;
		end
	end

endmodule
