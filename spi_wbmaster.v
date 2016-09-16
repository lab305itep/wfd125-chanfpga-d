`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    15:10:40 10/02/2014 
// Design Name: 	 wfd125
// Module Name:    spi_wbmaster 
// Project Name:   chanfpga
// Target Devices: XC6S45T
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//		perform WB single read or write cycle on 4-byte SPI command
//		SPI :
//		- latch data on rising edge SPICLK
//		- change data on falling edge SPICLK
//		- data MSB first
//		- SPIFR active LOW during whole command
//		- SPIFR going high interrupts the command and causes IDLE state
//		SPI commands (D - data from SPI master, d - data to SPI master):
//			Write:   0 S1 S0 A12 A11 A10 A9 A8   A7..A0  D15..D8  D7..D0 -> WB write cycle
//			Read:    1 S1 S0 A12 A11 A10 A9 A8   A7..A0 -> WB read cycle -> d15..d8  d7..d0
//		WB address A[12:0],	WB data D[15:0], crystal is addressed when S[1:0] = STADR[1:0]
//
//
//
//////////////////////////////////////////////////////////////////////////////////
module spi_wbmaster(
	 // System and WB clock, 125 MHz
    input CLK,
	 // SPI clock
    input SPICLK,		// active raising edge
	 // SPI serial data
    inout SPIDAT,
	 // SPI frame
    input SPIFR,		// active low
	 // Stone number
    input [1:0] STADDR,
	 // WB standard signals
    output reg [12:0] wb_adr_o,
    output reg [15:0] wb_dat_o,
    output [3:0] wb_sel_o,
    output reg wb_we_o,
    output reg wb_cyc_o,
    output reg wb_stb_o,
    output [2:0] wb_cti_o,
    output [1:0] wb_bte_o,
    input [15:0] wb_dat_i,
    input wb_ack_i,
    input wb_err_i,
    input wb_rty_i
    );

`define IDLE			4'h0
`define GET_OP			4'h1
`define WB_INITREAD	4'h2
`define WB_READ		4'h3
`define WAIT_SEND		4'h4
`define SEND_DATA		4'h5
`define GET_DATA		4'h6
`define WB_INITWRITE	4'h7
`define WB_WRITE		4'h8
`define WAIT_END		4'h9
`define WBTIMEOUT		100

	reg [3:0] state = `IDLE;
	reg [15:0] isreg = 0;
	reg [15:0] osreg = 0;
	reg [4:0] bit_cnt = 0;
	reg [7:0] timeout_cnt = 0;
	reg spi_fr_d = 1'b1;
	reg spi_clk_d = 1'b1;
	reg spi_clk_dd = 1'b1;
	reg spi_dat_d = 1'b1;
	wire spi_clk_pos;
	wire spi_clk_neg;

	assign wb_sel_o = 4'b0011;
	assign wb_cti_o = 3'b000;	// Classic cycle
	assign wb_bte_o = 2'b00;
	assign SPIDAT = (state == `SEND_DATA) ? osreg[15] : 1'bZ;
	
	assign spi_clk_pos = spi_clk_d & !spi_clk_dd;
	assign spi_clk_neg = !spi_clk_d & spi_clk_dd;
	
	always @ (posedge CLK) begin
		spi_fr_d <= SPIFR;
		spi_dat_d <= SPIDAT;
		spi_clk_d <= SPICLK;
		spi_clk_dd <= spi_clk_d;
		wb_stb_o <= 1'b0;
		wb_cyc_o <= 1'b0;
		
		if (spi_fr_d && state != `WB_WRITE && state != `WB_INITWRITE) begin
			state <= `IDLE;
		end else begin
			case (state) 
			`IDLE : begin
				if (!spi_fr_d) begin
					bit_cnt <= 0;
					state <= `GET_OP;
				end
			end
			`GET_OP : begin
				if (spi_clk_pos) begin
					isreg <= {isreg[14:0], spi_dat_d};
					if (bit_cnt < 15) begin
						bit_cnt <= bit_cnt + 1;
					end else begin
						bit_cnt <= 0;
						if (isreg[13:12] == STADDR) begin	// the last shift isn't finished - address in bits 12,13
							if (isreg[14]) begin					// read/write bit 14
								state <= `WB_INITREAD;
							end else begin							// write - get the data
								state <= `GET_DATA;
							end
						end else begin
							state <= `WAIT_END;					// this is not for us
						end
					end
				end
			end
			`WB_INITREAD : begin
				wb_adr_o <= isreg[12:0];
				timeout_cnt <= `WBTIMEOUT;
				state <= `WB_READ;
				wb_we_o <= 1'b0;
			end
			`WB_READ : begin
				wb_cyc_o <= 1'b1;
				wb_stb_o <= 1'b1;
				if (wb_ack_i || wb_err_i || wb_rty_i || !timeout_cnt) begin	// end on any result :-(
					state <= `WAIT_SEND;
					osreg <= wb_dat_i;
					wb_cyc_o <= 1'b0;
					wb_stb_o <= 1'b0;
				end else begin
					timeout_cnt <= timeout_cnt - 1;
				end
			end
			`WAIT_SEND : begin
				if (spi_clk_neg) begin	// wait till first falling edge of spi_clk before taking control of spi_dat
					bit_cnt <= 0;
					state <= `SEND_DATA;
				end
			end
			`SEND_DATA : begin
				if (spi_clk_pos) begin
					osreg <= {osreg[14:0], 1'b0};
					if (bit_cnt < 15) begin
						bit_cnt <= bit_cnt + 1;
					end else begin
						state <= `WAIT_END;
					end
				end
			end
			`GET_DATA : begin
				if (spi_clk_pos) begin
					osreg <= {osreg[14:0], spi_dat_d};
					if (bit_cnt < 15) begin
						bit_cnt <= bit_cnt + 1;
					end else begin
						state <= `WB_INITWRITE;
					end
				end	
			end
			`WB_INITWRITE : begin
				wb_adr_o <= isreg[12:0];
				wb_dat_o <= osreg;
				timeout_cnt <= `WBTIMEOUT;
				state <= `WB_WRITE;
				wb_we_o <= 1'b1;
			end
			`WB_WRITE : begin
				wb_cyc_o <= 1'b1;
				wb_stb_o <= 1'b1;
				if (wb_ack_i || wb_err_i || wb_rty_i || !timeout_cnt) begin	// end on any result :-(
					state <= `WAIT_END;
					wb_cyc_o <= 1'b0;
					wb_stb_o <= 1'b0;
				end else begin
					timeout_cnt <= timeout_cnt - 1;
				end				
			end
			`WAIT_END : begin
				if (spi_fr_d) begin
					state <= `IDLE;
				end
			end
			endcase
		end
	end
	
endmodule
