`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    14:51:48 10/05/2016 
// Design Name: 
// Module Name:    self_trig 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description:    Produce self trigger based on the prescale and threshod.
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module self_trig #(
	parameter ABITS = 12,			// width of ADC data
	parameter STDELAY = 6,			// writing state machine sees self trigger after this number of clk
	parameter STDBITS = 3			// must correspond to STDELAY
)(
	input			adcclk,		// ADC clock
	input signed [15:0] 	data,		// ADC data after pedestal subtraction
	input 			inhibit,	// Inhibit triggers (includes mask, raw and inhibit itself)
	input [ABITS-1:0] 	threshold,	// Threshold
	input [15:0]		prescale,	// Prescale
	output reg		trig = 0,	// Resulting trigger (1 ADCCLK)
	output reg [9:0] 	counter	= 0	// Trigger counter
);

	reg			inh = 1;	// inhibit, relatched to ADCCLK
	reg 			discr = 0;	// signal above selftrigger threshold
	reg [STDBITS-1:0]	strig_del = 0;	// counter for selftrigger delay
	reg [15:0]		presc_cnt = 0;	// selftrigger prescale counter

	//		self trigger & prescale 
	always @ (posedge adcclk) begin
		inh <= inhibit;		// relatch inhibit to ADCCLK
		if (strig_del != 0) begin
			strig_del <= strig_del - 1;
		end
		if (strig_del == 1) begin
			trig <= 1;
		end else begin
			trig <= 0;
		end
		if (~inh) begin
			if (data > $signed({1'b0,threshold})) begin
				if (~discr) begin
					// crossing threshold (for the first time)
					discr <= 1;
					// prescale threshold crossings
					if (|presc_cnt) begin
						presc_cnt <= presc_cnt - 1;
					end else begin
						presc_cnt <= prescale;
						counter <= counter + 1;	// count self triggers after prescale independently of transmission
						if (strig_del == 0) begin
							strig_del <= STDELAY;
						end
					end
				end
			end else if (data <= $signed({1'b0,threshold[ABITS-1:1]})) begin
				// HALF threshold crossed back (noise reduction)
				discr <= 0;
			end 
		end else begin
			discr <= 0;
			strig_del <= 0;
		end
	end

endmodule
