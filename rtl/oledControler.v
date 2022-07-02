`timescale 1ns / 1ps

// Description: Controller for the OLED Zedboard Display
//// OLED INITIALIZATION SEQUENCE ////
// 1) Aply reset and make VBAT = 1
// 2) Wait for 2ms
// 3) Send display off command (0xAE)
// 4) Wait for 2ms
// 5) Remove reset
// 6) Wait for 2 ms
// 7) Configure Charge Pump (0x8D, 0x14)
// 8) Configure pre-charge (0xD9, 0xF1)
// 9) Make VBAT = 0
// 10) Wait for 2 ms
// 11) Set Contrast (0x81, 0xFF)
// 12) Set segment remap (0xA0)
// 13) Set scan direction (0xC0)
// 14) Set COM pin (0xDA, 0x00)
// 15) Turn Display ON (0xAF)

module oledController(
    // Global signals
    input  clk                 ,     // 100MHz onboard clock
    input  reset               ,
    // Neural network module interface
    input       in_data_valid  ,
    input [3:0] in_data        ,
    output reg  sendDone       ,
    output reg  oled_ready     ,
    // OLED display interface
    output reg oled_vdd        , // Power Supply for Logic
    output reg oled_vbat       , // Power Supply for DC/DC Converter Circuit
    output reg oled_reset_n    , // Power Reset for Controller and Driver
    output reg oled_dc_n       , // Data/Command Control
    output wire oled_spi_clk   , // Serial Clock Input Signal
    output wire oled_spi_data    // Serial Data Input Signal
);

// Internal registers
reg [4:0] state;      // FSM current state
reg [4:0] nextState;  // FSM next state
reg       startDelay; // enable delay

reg       spiLoadData; // new data for transmission over SPI
reg [7:0] spiData;     // data for transmission over SPI

reg [1:0] currPage;    // which page is used for displaying
reg [7:0] columnAddr;  // column index on current 
reg [3:0] byteCounter; // count the bytes in a character bitmap
reg [6:0] clearLength; // 8x8 locations on display to clear
reg [3:0] reset_addr;  // Address for reset sequence in ascii ROM
reg [3:0] text_currIndex;
reg       writeTextEnable;
reg [7:0] charAddr;
reg       clearEnd;    // flag to indicate the end of clearing the screen
reg       textDone;    // flag which indicates that the initial text begins to be write on display 

// Interconnection wires
wire        delayDone;   // done signal from Delay Generator module
wire        spiDone;     // data has been sent over spi interface
wire [7:0]  in_ROM;      // address input for ascii ROM
wire [63:0] digitBitMap; // the bitmap of a digit (8 x 8)

// Assignments
assign in_ROM   = (writeTextEnable) ? charAddr : (clearEnd) ? (in_data + 'd48) : reset_addr;
assign clearLen = clearLength;

// FSM states
localparam  IDLE           = 'd0,
            DELAY          = 'd1,
            INIT           = 'd2,
            RESET          = 'd3,
            CHARGE_PUMP    = 'd4,
            CHARGE_PUMP1   = 'd5,
            WAIT_SPI       = 'd6,
            PRE_CHARGE     = 'd7,
            PRE_CHARGE1    = 'd8,
            VBAT_ON        = 'd9,
            CONTRAST       = 'd10,
            CONTRAST1      = 'd11,
            SEG_REMAP      = 'd12,
            SCAN_DIR       = 'd13,
            COM_PIN        = 'd14,
            COM_PIN1       = 'd15,
            DISPLAY_ON     = 'd16,
            FULL_DISPLAY   = 'd17,
            DONE           = 'd18,
            PAGE_ADDR      = 'd19,
            PAGE_ADDR1     = 'd20,
            PAGE_ADDR2     = 'd21,
            COLUMN_ADDR    = 'd22,
            SEND_DATA      = 'd23,
            CLEAR_DISPLAY  = 'd24,
            DISPLAY_TEXT   = 'd25;

// Default text on display
localparam digitText  = "Digit is ";
localparam textLenght = 9;

// clearEnd register definition
always @(posedge clk) begin
    if (reset)
        clearEnd <= 1'b0;
    else if ((clearLength == 0) && sendDone)
        clearEnd <= 1'b1;
end

// FSM definition
always @(posedge clk)
begin
    if (reset)
    begin
        state           <= IDLE;
        nextState       <= IDLE;
        oled_vdd        <= 1'b1;
        oled_vbat       <= 1'b1;
        oled_reset_n    <= 1'b1;
        oled_dc_n       <= 1'b1;
        startDelay      <= 1'b0;
        spiData         <= 8'd0;
        spiLoadData     <= 1'b0;
        oled_ready      <= 1'b0;
        clearLength     <= 'd64;
        text_currIndex  <= textLenght;
        reset_addr      <= 0;
        currPage        <= 0;
        sendDone        <= 0;
        columnAddr      <= 0;
        writeTextEnable <= 0;
        charAddr        <= 0;
        textDone        <= 0;
    end else
    begin
        case(state)
            IDLE: begin
                oled_vbat    <= 1'b1;
                oled_reset_n <= 1'b1;
                oled_dc_n    <= 1'b0;
                oled_vdd     <= 1'b0;
                state        <= DELAY;
                nextState    <= INIT;
            end
            DELAY: begin
                startDelay <= 1'b1;
                if (delayDone)
                begin
                    state      <= nextState;
                    startDelay <= 1'b0;
                end
            end
            INIT: begin
                spiData     <= 'hAE;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData  <= 1'b0;
                    oled_reset_n <= 1'b0;
                    state        <= DELAY;
                    nextState    <= RESET;
                end
            end
            RESET: begin
                oled_reset_n <= 1'b1;
                state        <= DELAY;
                nextState    <= CHARGE_PUMP;
            end
            CHARGE_PUMP: begin
                spiData     <= 'h8D;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= CHARGE_PUMP1;
                end
            end
            WAIT_SPI: begin
                if (!spiDone)
                begin
                    state <= nextState;
                end
            end
            CHARGE_PUMP1: begin
                spiData     <= 'h14;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= PRE_CHARGE;
                end
            end
            PRE_CHARGE: begin
                spiData     <= 'hD9;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= PRE_CHARGE1;
                end
            end
            PRE_CHARGE1: begin
                spiData     <= 'hF1;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= VBAT_ON;
                end
            end            
            VBAT_ON: begin
                oled_vbat <= 1'b0;
                state     <= DELAY;
                nextState <= CONTRAST;
            end
            CONTRAST: begin
                spiData     <= 'h81;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= CONTRAST1;
                end
            end  
            CONTRAST1: begin
                spiData     <= 'hFF;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= SEG_REMAP;
                end
            end            
            SEG_REMAP:begin
                spiData     <= 'hA0;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= SCAN_DIR;
                end
            end 
            SCAN_DIR: begin
                spiData     <= 'hC0;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= COM_PIN;
                end
            end 
            COM_PIN: begin
                spiData     <= 'hDA;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= COM_PIN1;
                end
            end
            COM_PIN1: begin
                spiData     <= 'h00;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= DISPLAY_ON;
                end
            end
            DISPLAY_ON: begin
                spiData     <= 'hAF;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= PAGE_ADDR;
                end
            end 
            PAGE_ADDR: begin
                spiData     <= 'h22;
                spiLoadData <= 1'b1;
                oled_dc_n   <= 1'b0;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= PAGE_ADDR1;
                end
            end
            PAGE_ADDR1: begin
                spiData     <= currPage;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    currPage    <= currPage + 1;
                    nextState   <= PAGE_ADDR2;
                end
            end  
            PAGE_ADDR2: begin
                spiData     <= currPage;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    nextState   <= COLUMN_ADDR;
                end
            end              
            COLUMN_ADDR: begin
                spiData     <= 'h10;
                spiLoadData <= 1'b1;
                if (spiDone)
                begin
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    if (clearLength == 0)
                        nextState <= DONE;
                    else
                        nextState <= CLEAR_DISPLAY;
                end
            end            
            CLEAR_DISPLAY: begin
                byteCounter <= 8;
                sendDone    <= 1'b0;
                if (columnAddr != 128 & !sendDone) begin
                    state       <= SEND_DATA;
                    clearLength <= clearLength - 1;
                end
                else if (columnAddr == 128 & !sendDone) begin
                    state      <= PAGE_ADDR;
                    columnAddr <= 0;
                end
            end
            DISPLAY_TEXT: begin
                byteCounter     <= 8;
                sendDone        <= 1'b0;
                writeTextEnable <= 1'b1;
                
                if (text_currIndex == 0) begin
                    state           <= DONE;
                    writeTextEnable <= 1'b0;
                    textDone        <= 1'b1;
                end else 
                    state <= SEND_DATA;

                charAddr       <= digitText[(text_currIndex * 8 - 1)-:8];
                text_currIndex <= text_currIndex - 1;
            end
            DONE: begin
                sendDone   <= 1'b0;
                oled_ready <= 1'b1;
                if (clearEnd & ~textDone)
                    state <= DISPLAY_TEXT;
                else if (in_data_valid & columnAddr != 128 & !sendDone)
                begin
                    state       <= SEND_DATA;
                    byteCounter <= 8;
                end
                else if (in_data_valid & columnAddr == 128 & !sendDone)
                begin
                    state       <= PAGE_ADDR;
                    columnAddr  <= 0;
                    byteCounter <= 8;
                end
            end   
            SEND_DATA: begin
                spiData     <= digitBitMap[(byteCounter*8 - 1)-:8];
                spiLoadData <= 1'b1;
                oled_dc_n   <= 1'b1;
                if (spiDone)
                begin
                    columnAddr  <= columnAddr + 1;
                    spiLoadData <= 1'b0;
                    state       <= WAIT_SPI;
                    if (byteCounter != 1)
                    begin
                        byteCounter <= byteCounter - 1;
                        nextState   <= SEND_DATA;
                    end
                    else
                    begin
                        if (clearLength == 0)
                            nextState <= DONE;
                        else
                            nextState <= CLEAR_DISPLAY;

                        sendDone  <= 1'b1;
                    end
                end
            end                   
        endcase
    end
end

// Instances
delayGen i_DG(
    .clk       (clk         ),
    .enable    (startDelay  ),
    .delayDone (delayDone   )
);

spiController i_SC(
    .clk       (clk           ), 
    .reset     (reset         ),
    .load_data (spiLoadData   ), 
    .data_in   (spiData       ),
    .spi_clock (oled_spi_clk  ),
    .spi_data  (oled_spi_data ),
    .done_send (spiDone       )
);

asciiROM i_ROM(
    .addr (in_ROM      ),
    .data (digitBitMap )
);

endmodule