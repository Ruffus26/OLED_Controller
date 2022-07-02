`timescale 1ns / 1ps

// Description: generate 2ms needed delay for OLED controller on a 100MHz clock frequency

module delayGen (
    input      clk       ,
    input      enable    ,
    output reg delayDone
);

reg [17:0] counter;

always @(posedge clk)
begin
    if (enable & (counter != 200000))
        counter <= counter + 1;
    else
        counter <= 0;
end

always @(posedge clk)
begin
    if(enable & (counter == 200000))
        delayDone <= 1'b1;
    else
        delayDone <= 1'b0;
end

endmodule