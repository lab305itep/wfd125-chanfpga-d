`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 ITEP
// Engineer: 		 SvirLex
// 
// Create Date:    18:47:04 28/04/2015 
// Design Name: 	 fpga_chan
// Module Name:    adc1rcvd 
// Project Name: 	 wfd125
// Target Devices: s6
// Revision 0.01 - File Created
// Additional Comments: 
//		to recieve ONE adc bit line (6 bits DDR) with variable delay
//
//////////////////////////////////////////////////////////////////////////////////
module adc1rcvd # (
		parameter IOSTD = "LVDS_25"
	)
	(
		input 		CLK,	// General FPGA clock for SERDES and its bitslip timing
		input  [1:0] 	CLKIN,	// clocks from ADC
		input  [1:0] 	DIN,	// one line data from ADC
		output [5:0] 	DOUT,	// deserialized data to FPGA
		input IOCE,		// SERDESSTROBE
		input BS,					// bitslip enable
		input SRST,					// asyncronous reset to ISERDES
		input DINC,					// increment command to IODELAY
		input DCAL,					// CAL command to IODELAY
		input DRST					// reset command to IODELAY
   );

	wire DIN_s;
	wire DIN_d;
	wire M2S;

   IBUFDS #(
      .DIFF_TERM("TRUE"),  // Differential Termination
      .IOSTANDARD(IOSTD) 	// Specify the input I/O standard
   ) IBUFDS_inst (
      .O(DIN_s),  			// Buffer output
      .I(DIN[0]),  			// Diff_p buffer input (connect directly to top-level port)
      .IB(DIN[1]) 			// Diff_n buffer input (connect directly to top-level port)
   );

   IODELAY2 #(
//      .COUNTER_WRAPAROUND("STAY_AT_LIMIT"), 	// "STAY_AT_LIMIT" or "WRAPAROUND" 
      .COUNTER_WRAPAROUND("WRAPAROUND"), 		// "STAY_AT_LIMIT" or "WRAPAROUND" 
      .DATA_RATE("DDR"),                 		// "SDR" or "DDR" (probably doesn't matter untill cal)
      .DELAY_SRC("IDATAIN"),                 // "IO", "ODATAIN" or "IDATAIN" 
      .IDELAY2_VALUE(0),                 		// Delay value when IDELAY_MODE="PCI" (0-255)
      .IDELAY_MODE("NORMAL"),            		// "NORMAL" or "PCI" 
      .IDELAY_TYPE("VARIABLE_FROM_ZERO"),    // "FIXED", "DEFAULT", "VARIABLE_FROM_ZERO", "VARIABLE_FROM_HALF_MAX" 
															// or "DIFF_PHASE_DETECTOR" 
      .IDELAY_VALUE(0),                  		// Amount of taps for fixed input delay (0-255)
      .ODELAY_VALUE(0),                  		// Amount of taps fixed output delay (0-255)
      .SERDES_MODE("NONE"),              		// "NONE", "MASTER" or "SLAVE" 
      .SIM_TAPDELAY_VALUE(75)            		// Per tap delay used for simulation in ps
   )
   IODELAY2_inst (
      .BUSY(BUSY),         // 1-bit output: Busy output after CAL
      .DATAOUT(DIN_d),   	// 1-bit output: Delayed data output to ISERDES/input register
      .DATAOUT2(), 			// 1-bit output: Delayed data output to general FPGA fabric
      .DOUT(),         		// 1-bit output: Delayed data output
      .TOUT(),         		// 1-bit output: Delayed 3-state output
      .CAL(DCAL),          // 1-bit input: Initiate calibration input
      .CE(DINC),           // 1-bit input: Enable INC input
      .CLK(CLK),           // 1-bit input: Clock input
      .IDATAIN(DIN_s),     // 1-bit input: Data input (connect to top-level port or I/O buffer)
      .INC(DINC),          // 1-bit input: Increment / decrement input
      .IOCLK0(CLKIN[0]),   // 1-bit input: Input from the I/O clock network
      .IOCLK1(CLKIN[1]),   // 1-bit input: Input from the I/O clock network
      .ODATAIN(1'b0),	   // 1-bit input: Output data input from output register or OSERDES2.
      .RST(DRST),          // 1-bit input: Reset to zero or 1/2 of total delay period
      .T(1'b1)             // 1-bit input: 3-state input signal
   );

  ISERDES2 #(
      .BITSLIP_ENABLE("TRUE"),      // Enable Bitslip Functionality (TRUE/FALSE)
      .DATA_RATE("DDR"),             // Data-rate ("SDR" or "DDR")
      .DATA_WIDTH(6),                // Parallel data width selection (2-8)
      .INTERFACE_TYPE("RETIMED"), // "NETWORKING", "NETWORKING_PIPELINED" or "RETIMED" 
      .SERDES_MODE("MASTER")           // "NONE", "MASTER" or "SLAVE" 
   )
   ISERDES2_master (
      .CFB0(),           // 1-bit output: Clock feed-through route output
      .CFB1(),           // 1-bit output: Clock feed-through route output
      .DFB(),            // 1-bit output: Feed-through clock output
      .FABRICOUT(), 		 // 1-bit output: Unsynchrnonized data output
		.INCDEC(),       	 // 1-bit output: Phase detector output
      // Q1 - Q4: 1-bit (each) output: Registered outputs to FPGA logic
      .Q1(DOUT[3]),
      .Q2(DOUT[2]),
      .Q3(DOUT[1]),
      .Q4(DOUT[0]),
      .SHIFTOUT(M2S),   // 1-bit output: Cascade output signal for master/slave I/O
      .VALID(),         // 1-bit output: Output status of the phase detector
      .BITSLIP(BS),     // 1-bit input: Bitslip enable input
      .CE0(1'b1),       // 1-bit input: Clock enable input
      .CLK0(CLKIN[0]),  // 1-bit input: I/O clock network input
      .CLK1(CLKIN[1]),  // 1-bit input: Secondary I/O clock network input
      .CLKDIV(CLK),     // 1-bit input: FPGA logic domain clock input
      .D(DIN_d),        // 1-bit input: Input data
      .IOCE(IOCE),      // 1-bit input: Data strobe input
      .RST(SRST),      // 1-bit input: Asynchronous reset input
      .SHIFTIN(1'b0)    // 1-bit input: Cascade input signal for master/slave I/O
   );
	
  ISERDES2 #(
      .BITSLIP_ENABLE("TRUE"),      // Enable Bitslip Functionality (TRUE/FALSE)
      .DATA_RATE("DDR"),             // Data-rate ("SDR" or "DDR")
      .DATA_WIDTH(6),                // Parallel data width selection (2-8)
      .INTERFACE_TYPE("RETIMED"), // "NETWORKING", "NETWORKING_PIPELINED" or "RETIMED" 
      .SERDES_MODE("SLAVE")           // "NONE", "MASTER" or "SLAVE" 
   )
   ISERDES2_slave (
      .CFB0(),           // 1-bit output: Clock feed-through route output
      .CFB1(),           // 1-bit output: Clock feed-through route output
      .DFB(),            // 1-bit output: Feed-through clock output
      .FABRICOUT(), // 1-bit output: Unsynchrnonized data output
      .INCDEC(),       // 1-bit output: Phase detector output
      // Q1 - Q4: 1-bit (each) output: Registered outputs to FPGA logic
      .Q1(),
      .Q2(),
      .Q3(DOUT[5]),
      .Q4(DOUT[4]),
      .SHIFTOUT(),      // 1-bit output: Cascade output signal for master/slave I/O
      .VALID(),         // 1-bit output: Output status of the phase detector
      .BITSLIP(BS),     // 1-bit input: Bitslip enable input
      .CE0(1'b1),       // 1-bit input: Clock enable input
      .CLK0(CLKIN[0]),  // 1-bit input: I/O clock network input
      .CLK1(CLKIN[1]),  // 1-bit input: Secondary I/O clock network input
      .CLKDIV(CLK),     // 1-bit input: FPGA logic domain clock input
      .D(1'b0),        		// 1-bit input: Input data
      .IOCE(IOCE),      // 1-bit input: Data strobe input
      .RST(SRST),      // 1-bit input: Asynchronous reset input
      .SHIFTIN(M2S)     // 1-bit input: Cascade input signal for master/slave I/O
   );
endmodule
