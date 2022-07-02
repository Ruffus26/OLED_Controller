`timescale 1ns / 1ps

// Description: Controller for the SPI interface

module spiController (
    input       clk       ,  // On-board Zynq clock (100 MHz)
    input       reset     ,
    input       load_data ,  // Signal that indicates new data for transmission
    input [7:0] data_in   ,  // Data to be sent over spi interface
    output      spi_clock ,  // 10MHz max - should be only activated during transmission
    output reg  spi_data  ,  // Serial data
    output reg  done_send    // Signal that indicates data has been sent over spi interface
);

// Internal registers
reg [2:0] counter = 0 ;
reg [2:0] dataCount   ;
reg [7:0] shiftReg    ;  // Shift register
reg [1:0] state       ;  // FSM state
reg       clock_10    ;  // SPI clock
reg       CE          ;  // Chip Enable

assign spi_clock = (CE == 1) ? clock_10 : 1'b1;

// Counter used for dividing the frequency
always @(posedge clk)
begin
    if(counter != 4)
        counter <= counter + 1;
    else
        counter <= 0;
end

// Define a 10 MHz clock signal
initial
    clock_10 <= 0;

always @(posedge clk)
begin
    if(counter == 4)
        clock_10 <= ~clock_10;
end

// Parameters
localparam IDLE = 'd0;
localparam SEND = 'd1;
localparam DONE = 'd2;

// FSM
always @(negedge clock_10)
begin
    if(reset)
    begin
        state     <= IDLE;
        dataCount <= 0;
        done_send <= 1'b0;
        CE        <= 0;
        spi_data  <= 1'b1;
    end else
    begin
        case(state)
            IDLE: begin
                if(load_data)
                begin
                    shiftReg  <= data_in;
                    state     <= SEND;
                    dataCount <= 0;
                end
            end
            SEND: begin
                spi_data <= shiftReg[7];
                shiftReg <= {shiftReg[6:0], 1'b0}; // Shift left operation
                CE <= 1;
                if (dataCount != 7)
                    dataCount <= dataCount + 1;
                else
                    state <= DONE;
            end
            DONE: begin
                CE <= 0;
                done_send <= 1'b1;
                if(!load_data)
                begin
                    done_send <= 1'b0;
                    state     <= IDLE;
                end
            end
        endcase
    end
end

endmodule