`timescale 1ns/1ps

module sgpio_initiator(
    input clk,
    input rst_n,
    input en,
    input  [11:0] tx_led,
    output reg [11:0] rx_status,
    output reg done,
    output reg SCLK,
    output reg SLOAD,
    output reg SDO,
    input  SDI
);



parameter HALF = 250;

reg [7:0]  hcnt;
reg [4:0]  pos;
reg [11:0] tx_reg;
reg [11:0] rx_buf;
reg [1:0]  vid;

always @(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        hcnt      <= 0;
        pos       <= 0;
        tx_reg    <= 0;
        rx_buf    <= 0;
        rx_status <= 0;
        done      <= 0;
        SCLK      <= 1;
        SLOAD     <= 1;
        SDO       <= 1;
    end
    else begin
        done <= 0;

        if(!en) begin
            SCLK  <= 1;
            SLOAD <= 1;
            SDO   <= 1;
            hcnt  <= 0;
            pos   <= 0;
            tx_reg <= tx_led;
        end
        else begin
            if(hcnt < HALF - 1) begin
                hcnt <= hcnt + 1;
            end
            else begin
                hcnt <= 0;
                SCLK <= ~SCLK;

                
                if(SCLK == 1) begin
                    if(pos < 12)
                        rx_buf[pos] <= SDI;

                    if(pos == 12) begin
                        rx_status <= rx_buf;
                        done      <= 1;
                        tx_reg    <= tx_led;
                    end

                    if(pos == 16)
                        pos <= 0;
                    else
                        pos <= pos + 1;
                end

                
                else begin
                    if(pos < 12) begin
                        SLOAD <= 0;
                        SDO   <= tx_reg[pos];
                    end
                    else if(pos == 12) begin
                        SLOAD <= 1;
                        SDO   <= 0;
                    end
                    else begin
                        // vendor bits L0-L3 all zero (normal mode)
                        SLOAD <= 0;
                        SDO   <= 0;
                    end
                end

            end
        end
    end
end

endmodule
