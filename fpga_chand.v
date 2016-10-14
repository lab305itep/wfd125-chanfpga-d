`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    14:05:44 09/30/2014 
// Design Name: 
// Module Name:    fpga_chan 
// Project Name:   WFD125
// Target Devices: XC6S
// Tool versions: 
// Description:    Main module for channel FPGA pair-trigger disign.
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//  	ICX usage:
//  0,1 - external reference clock - 125/8 MHz (differential)
//  2  - XSPI frame
//  3  - XSPI data
//  4  - XSPI clock
//  5  - WB reset
//  6  - inhibit
//  7  - test pulse
//		GTP channel usage
//		Output:
//  0   - sending data blocks, commas as spacer. 
//  3:1 - unused
//		Input :
//  0   - data (not comma) indicates soft trigger
//  3:1 - unused
//		CSR bits:
//  3:0 - pattern for ADC receiver checks
//  6:4 - counter max = 2**(16 + 2*CSR[6:4]) for ADC receiver checks
//  7   - check start - edge sensitive  (ready on read)
//  8   - reset external frequency DCM  (auto reset)
//  9   - reset exteral frequency counter
//  11  - test mode - do short pulses on testpulses (ICX[7])
//  12  - ped mode: 
//		0 - pedestals are calculated independently of signal level and calculated value is direcly used for subtraction
//		1 - pedestals are calculated only if the signal is different from the current value by 5 ADCU, current value
//			  is changed by 1 ADCU only dependent on the difference sign
//  13  - ped inhibit: 0 - current value (according to ped mode) is used as soon as it changes, 1 - current ped is fixed at the last
//		value before setting this bit, but current calculated value can be read from ped array; selftrigger block
//		always gives ped value, which is really currently in use.
//  14  - enable sum64 history block on master trigger - unused
//  15  - raw mode: no selftrigger or pair trigger, raw data blocks on soft trigger 
//`
//		Array registers:
// 0  - pair trigger mask
// 1  - selftrigger mask
// 2  - sum mask - unused
// 3  - signal inversion mask
// 4  - channel threshold
// 5  - self trigger threshold
// 6  - pair sum threshold
// 7  - selftrigger prescale
// 8  - window length for waveform
// 9  - pair/soft trigger window begin
// 10 - self trigger window begin
// 11 - trigger history window begin - unused
// 12 - delay of local sum for adding to other X's -unused
//
//////////////////////////////////////////////////////////////////////////////////
module fpga_chand(
	// ADC A
	input [15:0] ADA,
	input [1:0] ACA,
	input [1:0] AFA,
	// ADC B
	input [15:0] ADB,
	input [1:0] ACB,
	input [1:0] AFB,
	// ADC C
	input [15:0] ADC,
	input [1:0] ACC,
	input [1:0] AFC,
	// ADC D
	input [15:0] ADD,
	input [1:0] ACD,
	input [1:0] AFD,
	// I2C to clock buffer
	inout I2CCLK,
	inout I2CDAT,
	// SPI to ADCs
	output SPICLK,
	inout SPIDAT,
	output [3:0] SPISEL,
	// Analog input control
	output [3:0] ACNTR,
	// Fast serial connections and CLK
	// Main Clock
	input [1:0] RCLK,
	// Recievers
	input [1:0] RX0,
	input [1:0] RX1,
	input [1:0] RX2,
	input [1:0] RX3,
	// Transmitters
	output [1:0] TX0,
	output [1:0] TX1,
	output [1:0] TX2,
	output [1:0] TX3,
	// Stone number
	input [1:0] CHN,
	// Common lines to other FPGA
	inout [15:0] ICX,
	// Configuration pins
	input INIT,
	input DOUT,
	input CCLK,
	input DIN,
	// Test points
	output reg [5:1] TP
);

`include "fpga_chan.vh"
`include "version.vh"

	localparam		NFIFO = 17;
//		Wires and registers

	// ADC clocks, frames and data organized into buses
	wire	[7:0]		ACLK;		// input clocks from ADC
	wire	[7:0]		AFRM;		// input frame from ADC
	wire	[63:0]		ADAT;		// input data from ADC
	assign	ACLK = {ACD, ACC, ACB, ACA};
	assign	AFRM = {AFD, AFC, AFB, AFA};
	assign	ADAT = {ADD, ADC, ADB, ADA};

	wire 			CLK125;		// GTP reciever clock = system clock
	wire 	[3:0] 		ADCCLK;		// clocks accompanying ADC deserialized data
	wire 	[191:0] 	ADCDAT;		// deserialized data from ADC
	wire 	[63:0]  	gtp_data_i;	// data to GTP
	wire 	[3:0]   	gtp_comma_i;	// k-char signature to GTP
	wire 	[63:0]  	gtp_data_o; 	// data ftom GTP
	wire 	[3:0]   	gtp_comma_o;	// k-char signature from GTP
	wire 	[31:0]  	CSR;		// command and status register
	wire			seq_enable;	// check enable (check interval)
	
	wire [16*NFIFO-1:0]	d2arb;		// data from channel fifo's to sending arbitter
	wire [NFIFO-1:0]	arb_want;	// arbitter data request to fifo's
	wire [NFIFO-1:0] 	fifo_have;	// fifo's reply to arbitter if they have data
	wire [15:0]		fifo_missed;	// data fifo's missed trigger because of full
	wire			err_ovr;	// arbitter detected overrun condition -- no CW when expected
	wire			err_undr;	// arbitter detected underrun condition -- CW earlier than expected

	wire 			sertrig;	// serial trigger as accepted from ICX[1:0] - 125/8 MHz here
	wire			ext_freq;	// external frequency x8 = 125 MHz
	wire [11:0]		trig_time;	// external frequency phase

	wire [511:0]  		par_array;
	wire [255:0]  		adc_ped;
	
	wire [255:0]		dpdata;		// data from channels to double channel trigger
	wire [7:0]		ddiscr;		// discriminator outputs from DCT
//		WB-bus
	wire			wb_clk;
	reg			wb_rst;
	
	wire [15:0]		DBG;
	reg [4:0]		DBGR;
	
`include "wb_intercon.vh"
	always @ (posedge wb_clk) wb_rst <= ICX[5];

	assign ACNTR = 4'bzzzz;

//		GTP communication module
	
	gtprcv4 # (.WB_DIVIDE(2), .WB_MULTIPLY(2)) UGTP (	// 125 MHz for clkwb
		.rxpin		({RX3, RX2, RX1, RX0}),		// input data pins
		.txpin		({TX3, TX2, TX1, TX0}),		// output data pins
		.clkpin		(RCLK),				// input clock pins - tile0 package pins A10/B10
		.clkout		(CLK125),			// output 125 MHz clock
		.clkwb   	(),				// output clock ( previously for wishbone )
		.gck_o		(),				// not used here
		.data_o		(gtp_data_o),			// data received
		.charisk_o	(gtp_comma_o),			
		.data_i		(gtp_data_i),			// data send
		.charisk_i	(gtp_comma_i),
		.locked  	()
	);
	assign gtp_data_i[63:16] = 0;
	assign gtp_comma_i[3:1]  = 3'b111;

	// wb_clk is now equivalent to CLK125 !!!
	assign wb_clk = CLK125;

	// accept external frequency from ICX[1:0]
	IBUFDS #(
		.DIFF_TERM("FALSE"),   	// Differential Termination
		.IOSTANDARD("BLVDS_25") // Specify the input I/O standard
	) IBUFDS_trig (
		.O	(sertrig),  	// Buffer output
		.I	(ICX[0]),	// Diff_p buffer input (connect directly to top-level port)
		.IB	(ICX[1])	// Diff_n buffer input (connect directly to top-level port)
	);


//		SPI from the master Xilinx - master on the WB-bus
	spi_wbmaster spi_master(
		.CLK 		(wb_clk),
		.SPICLK 	(ICX[4]),
		.SPIDAT		(ICX[3]),
		.SPIFR		(ICX[2]),
		.STADDR		(CHN),
		.wb_adr_o 	(wb_m2s_spi_master_adr[14:2]),
		.wb_dat_o  	(wb_m2s_spi_master_dat[15:0]),
		.wb_sel_o  	(wb_m2s_spi_master_sel),
		.wb_we_o	(wb_m2s_spi_master_we),
		.wb_cyc_o  	(wb_m2s_spi_master_cyc),
		.wb_stb_o   	(wb_m2s_spi_master_stb),
		.wb_cti_o   	(wb_m2s_spi_master_cti),
		.wb_bte_o   	(wb_m2s_spi_master_bte),
		.wb_dat_i   	(wb_s2m_spi_master_dat[15:0]),
		.wb_ack_i   	(wb_s2m_spi_master_ack),
		.wb_err_i   	(wb_s2m_spi_master_err),
		.wb_rty_i   	(wb_s2m_spi_master_rty)
	);

	assign wb_m2s_spi_master_adr[1:0] = 2'b00;
	assign wb_m2s_spi_master_adr[31:15] = 17'h00000;
	assign wb_m2s_spi_master_dat[31:16] = 16'h0000;
	assign ICX[15:4] = 12'hZZZ;
	assign ICX[2:0] = 3'bZZZ;

//		CSR
	inoutreg reg_csr (
		.wb_clk		(wb_clk), 
		.wb_adr		(wb_m2s_reg_csr_adr[2]), 
		.wb_dat_i  	(wb_m2s_reg_csr_dat), 
		.wb_dat_o  	(wb_s2m_reg_csr_dat),
		.wb_we     	(wb_m2s_reg_csr_we),
		.wb_stb    	(wb_m2s_reg_csr_stb),
		.wb_cyc    	(wb_m2s_reg_csr_cyc), 
		.wb_ack    	(wb_s2m_reg_csr_ack), 
		.reg_i	   	({CSR[31:8], ~seq_enable, CSR[6:0]}),
		.reg_o	   	(CSR)
	);
	assign wb_s2m_reg_csr_err = 0;
	assign wb_s2m_reg_csr_rty = 0;
	
//		Version
	inoutreg reg_ver (
		.wb_clk    	(wb_clk), 
		.wb_adr    	(wb_m2s_reg_ver_adr[2]), 
		.wb_dat_i  	(wb_m2s_reg_ver_dat), 
		.wb_dat_o  	(wb_s2m_reg_ver_dat),
		.wb_we     	(wb_m2s_reg_ver_we),
		.wb_stb    	(wb_m2s_reg_ver_stb),
		.wb_cyc    	(wb_m2s_reg_ver_cyc), 
		.wb_ack    	(wb_s2m_reg_ver_ack), 
		.reg_i		(VERSION),
		.reg_o	  	()
	);
	assign wb_s2m_reg_csr_err = 0;
	assign wb_s2m_reg_csr_rty = 0;

//		SPI to ADCs
	wire [3:0]		empty_spi_cs;
	xspi_master  #(
		.CLK_DIV 	(49),
		.CLK_POL 	(1'b0)
	) adc_spi (
		.wb_rst    	(wb_rst),
		.wb_clk   	(wb_clk),
		.wb_we   	(wb_m2s_adc_spi_we),
		.wb_dat_i	(wb_m2s_adc_spi_dat[15:0]),
		.wb_dat_o	(wb_s2m_adc_spi_dat[15:0]),
		.wb_cyc		(wb_m2s_adc_spi_cyc),
		.wb_stb		(wb_m2s_adc_spi_stb),
		.wb_ack		(wb_s2m_adc_spi_ack),
		.spi_dat	(SPIDAT),
		.spi_clk	(SPICLK),
		.spi_cs    	({empty_spi_cs, SPISEL}),
		.wb_adr		(wb_m2s_adc_spi_adr[2])
	);
	assign wb_s2m_adc_spi_err = 0;
	assign wb_s2m_adc_spi_rty = 0;	
	assign wb_s2m_adc_spi_dat[31:16] = 0;

//		I2C to clock chip
	wire 			I2CCLK_o;
	wire 			I2CCLK_en;
	wire 			I2CDAT_o;
	wire 			I2CDAT_en;
	assign wb_s2m_i2c_clk_err = 0;
	assign wb_s2m_i2c_clk_rty = 0;
	assign wb_s2m_i2c_clk_dat[31:8] = 0;
	
	i2c_master_slave i2c_clk (
		.wb_clk_i  	(wb_clk), 
		.wb_rst_i  	(wb_rst),		// active high 
		.arst_i    	(1'b0), 		// active high
		.wb_adr_i  	(wb_m2s_i2c_clk_adr[4:2]), 
		.wb_dat_i  	(wb_m2s_i2c_clk_dat[7:0]), 
		.wb_dat_o  	(wb_s2m_i2c_clk_dat[7:0]),
		.wb_we_i   	(wb_m2s_i2c_clk_we),
		.wb_stb_i  	(wb_m2s_i2c_clk_stb),
		.wb_cyc_i  	(wb_m2s_i2c_clk_cyc), 
		.wb_ack_o  	(wb_s2m_i2c_clk_ack), 
		.wb_inta_o 	(),
		.scl_pad_i 	(I2CCLK), 
		.scl_pad_o 	(I2CCLK_o), 
		.scl_padoen_o 	(I2CCLK_en), 		// active low ?
		.sda_pad_i 	(I2CDAT), 
		.sda_pad_o 	(I2CDAT_o), 
		.sda_padoen_o 	(I2CDAT_en)		// active low ?
	);

	assign I2CCLK = (!I2CCLK_en) ? (I2CCLK_o) : 1'bz;
	assign I2CDAT = (!I2CDAT_en) ? (I2CDAT_o) : 1'bz;
	
// error register
	capreg #(.ADRBITS(1)) reg_err (
		.wb_clk    	(wb_clk), 
		.wb_adr    	(wb_m2s_reg_err_adr[2]), 
		.wb_dat_i  	(wb_m2s_reg_err_dat[15:0]), 
		.wb_dat_o  	(wb_s2m_reg_err_dat[15:0]),
		.wb_we     	(wb_m2s_reg_err_we),
		.wb_stb    	(wb_m2s_reg_err_stb),
		.wb_cyc    	(wb_m2s_reg_err_cyc), 
		.wb_ack    	(wb_s2m_reg_err_ack), 
		.inbits	  	({err_undr, err_ovr, 13'h0, hfifo_missed, fifo_missed})
	);
	assign wb_s2m_reg_err_err = 0;
	assign wb_s2m_reg_err_rty = 0;
	assign wb_s2m_reg_err_dat[31:16] = 16'h0000;
	
	
//		register array
	parreg16 #(.ADRBITS(4)) reg_array (
		.wb_clk    	(wb_clk), 
		.wb_adr    	(wb_m2s_reg_array_adr[5:2]), 
		.wb_dat_i  	(wb_m2s_reg_array_dat[15:0]), 
		.wb_dat_o  	(wb_s2m_reg_array_dat[15:0]),
		.wb_we     	(wb_m2s_reg_array_we),
		.wb_stb    	(wb_m2s_reg_array_stb),
		.wb_cyc    	(wb_m2s_reg_array_cyc), 
		.wb_ack    	(wb_s2m_reg_array_ack), 
		.reg_o	  	(par_array[255:0])
	);
	assign wb_s2m_reg_array_err = 0;
	assign wb_s2m_reg_array_rty = 0;
	assign wb_s2m_reg_array_dat[31:16] = 16'h0000;

//		input array for pedestals
	inpreg16 #(.ADRBITS(4)) ped_array (
		.wb_clk    	(wb_clk), 
		.wb_adr    	(wb_m2s_ped_array_adr[5:2]), 
		.wb_dat_i  	(wb_m2s_ped_array_dat[15:0]), 
		.wb_dat_o  	(wb_s2m_ped_array_dat[15:0]),
		.wb_we     	(wb_m2s_ped_array_we),
		.wb_stb    	(wb_m2s_ped_array_stb),
		.wb_cyc    	(wb_m2s_ped_array_cyc), 
		.wb_ack    	(wb_s2m_ped_array_ack), 
		.reg_i	   	(adc_ped)
	);
	assign wb_s2m_ped_array_err = 0;
	assign wb_s2m_ped_array_rty = 0;
	assign wb_s2m_ped_array_dat[31:16] = 16'h0000;

	// ADC data recievers

	wire [3:0]		wb_adc_rcv_ack;
	assign wb_s2m_adc_rcv_ack = |wb_adc_rcv_ack;

	genvar i;
	generate
		for (i=0; i<4; i = i + 1) begin: URCV
			adcrcvd ADCRCVD(
				// inputs from ADC
				.CLKIN		(ACLK[2*i+1:2*i]),	// input clock from ADC (375 MHz)
				.DIN		(ADAT[16*i+15:16*i]),	// Input data from ADC
				.FR		(AFRM[2*i+1:2*i]),	// Input frame from ADC 
				// outputs to further processing
				.CLK		(ADCCLK[i]),		// data clock derived from ADC clock
				.DOUT		(ADCDAT[48*i+47:48*i]),	// output data (CLK clocked)
				// this ADC trigger
				.sertrig	(ext_freq),		// as from ICX - external frequency
				.trtime		(trig_time[3*i+2:3*i]),	// external frequency phase
				//	WB interface
				.wb_clk		(wb_clk),
				.wb_cyc		(wb_m2s_adc_rcv_cyc),
				.wb_stb		(wb_m2s_adc_rcv_stb & (wb_m2s_adc_rcv_adr[7:6] == i)),
				.wb_we		(wb_m2s_adc_rcv_we),
				.wb_adr		(wb_m2s_adc_rcv_adr[5:2]),
				.wb_dat_i	(wb_m2s_adc_rcv_dat),
				.wb_ack		(wb_adc_rcv_ack[i]),
				.wb_dat_o	(wb_s2m_adc_rcv_dat),
				// checking signals
				.chk_type	(CSR[3:0]),		// test pattern number to check (from main CSR)
				.chk_run	(seq_enable)		// enable checking (checking interval, from checkseq)
			);
		end
	endgenerate
	
//		channel processing
	wire [199:0]		gtime_l;
	generate
		for (i=0; i<16; i = i + 1) begin: UPRC1
			prc1chand UCHAN (
				.clk		(CLK125),
				.num		({CHN, i[3:0]}), 
				// ADC data from its reciever
				.ADCCLK		(ADCCLK[i/4]),
				.ADCDAT		(ADCDAT[12*i+11:12*i]), 
				// data processing programmable parameters
				.sthr		(par_array[PAR_STTHR*16+11:PAR_STTHR*16]), 
				.prescale	(par_array[PAR_STPRC*16+15:PAR_STPRC*16]), 
				.mwinbeg	(par_array[PAR_MTWINBEG*16+9:PAR_MTWINBEG*16]), 
				.swinbeg	(par_array[PAR_STWINBEG*16+9:PAR_STWINBEG*16]), 
				.winlen		(par_array[PAR_WINLEN*16+8:PAR_WINLEN*16]), 
				.stmask		(par_array[PAR_STMASK*16+i]),
				.invert		(par_array[PAR_INVMASK*16+i]),
				.raw		(CSR[15]),
				// pedestal
				.pedmode	(CSR[12]),			// pedestal mode
				.pedinh		(CSR[13]),			// disable pedestal update
				.ped		(adc_ped[16*i+11:16*i]), 	// pedestal for readout
				// to double channel trigger
				.dpdata		(dpdata[16*i+15:16*i]),		// data to pair trigger
				.gtime		(gtime_l[25*(i/2)+24:25*(i/2)]),	// latched global time 
				.ptrig		(ddiscr[i/2]),			// pair trigger
				// inhibit
				.inhibit	(ICX[6]),
				// arbitter interface for data output
				.give		(arb_want[i]), 
				.have		(fifo_have[i]), 
				.dout		(d2arb[16*i+15:16*i]), 
				.missed		(fifo_missed[i]),
				// to sumtrig
				.testmode	(CSR[11]),
				.testpulse	(ICX[7]),
				.debug		(DBG[i])
			);		
			assign adc_ped[16*i+15:16*i+12] = 0;
		end
	endgenerate

// double trigger generator
	reg [7:0]		dt_inhibit = 8'hFF;
	wire [22:0]		gtime;			// Global time from external frequency
	generate
		for (i=0; i<8; i = i + 1) begin: UDTC1
			always @ (posedge CLK125) begin
				dt_inhibit[i] <= CSR[15] || par_array[PAR_MTMASK*16+i] || ICX[6];
			end
			doubletrig UDTC (
				.ADCCLK		(ADCCLK[i/2]),					// ADC clock, common for each 2 pairs of channels
				.dpdata		(dpdata[32*i+31:32*i]),				// data from 2 prc1chan's, ADC clocked, ped subtracted
				.ithr		(par_array[PAR_MTTHR*16+15:PAR_MTTHR*16]),	// individual channel threshold
				.sthr		(par_array[PAR_SUTHR*16+15:PAR_SUTHR*16]),	// two channel sum threshold
				.inhibit	(dt_inhibit[i]),				// total inhibit
				.exttrig	(~gtp_comma_o[0]),				// external trigger
				.trig		(ddiscr[i])					// discriminator output		
			);
			gtlatch UGTL (
				.extclk		(ext_freq),
				.gtin		(gtime),
				.trig		(ddiscr[i]),
				.phase		(trig_time[3*(i/2)+2:3*(i/2)]),
				.gtout		(gtime_l[25*i+24:25*i])
			);
		end
	endgenerate

	extfreq UFREQ (
		.freqin		(sertrig),
		.freqout	(ext_freq),
		.counter	(gtime),
		.reset		(CSR[9]),
		.inhibit	(ICX[6]),
		.dcmreset	(CSR[8])
	);

//		arbitter
	snd_arb  # (
		.NFIFO			(NFIFO)
	) UARB (
		.clk			(CLK125),
		// fifo control and data
		.arb_want		(arb_want),
		.fifo_have		(fifo_have),
		.datain			(d2arb),
		.err_undr		(err_undr),		// underrun error -- CW accepted earlier than expected
		.err_ovr		(err_ovr),		// overrun error -- CW accepted later than expected
		// trigger from summing to be sent to main
		.trig			(0),
		// GTP data for sending
		.dataout		(gtp_data_i[15:0]),
		.kchar			(gtp_comma_i[0])
	);

//		Pattern check sequencer
	checkseq USEQ(
		.clk(CLK125),			// system clock
		.start(CSR[7]),			// start
		.cntmax(CSR[6:4]),
		.enable(seq_enable)
	);

//		Test points
	generate
		for (i=0; i<4; i = i + 1) begin: UTP
			always @ (posedge CLK125) begin
				DBGR[i] <= | DBG[4*i+3:4*i];
			end
		end
	endgenerate
	
	always @ (posedge CLK125) begin
		TP <= {1'b0, DBGR};
	end
endmodule
