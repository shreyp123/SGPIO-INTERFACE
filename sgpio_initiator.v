`timescale 1ns/1ps

module sgpio_initiator
  #(parameter N = 4,
    parameter HALF= 250,
    parameter TBASE= 6250000) 
   (input clk,
    input rst_n,
    input en,
    input[3:0]bga_rate,
    input[3:0]bgb_rate,
    input[3:0]frc_off,
    input[3:0]max_on,
    input[3:0]str_off,
    input[3:0]str_on,
    input[(N*8)-1:0] gpio_tx,
    input[N-1:0] sof,
    input[N-1:0] eof,
    output reg[(N*3)-1:0]gpio_rx,
    output reg rx_rdy,
    output reg SCLK,
    output reg SLOAD,
    output reg SDO,
    input SDI);

localparam FL=N*3+5;

wire[31:0] T_STRON= (str_on+1)*(TBASE>>3);
wire[31:0] T_STROFF= str_off*(TBASE>>3);
wire[31:0] T_MAXON= max_on*(TBASE<<1);
wire[31:0] T_FRCOFF= frc_off*TBASE;
wire[31:0] T_BGA=(bga_rate+1)*TBASE;
wire[31:0] T_BGB=(bgb_rate+1)*TBASE;

reg[27:0] bga_cnt, bgb_cnt;
reg bga, bgb;
reg[N-1:0] abit_r;
reg[N*3-1:0]od_bits;
reg[N*3-1:0]od_snap;
reg[17:0]hcnt;
reg[7:0]pos;
reg[N*3-1:0]rx_buf; 

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bga_cnt<= 0;
        bga<= 0;
    end else if(bga_cnt>=T_BGA-1)begin
        bga_cnt<=0;
        bga<=~bga;
    end else
        bga_cnt<=bga_cnt+1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bgb_cnt <= 0;
        bgb <= 0;
    end else if (bgb_cnt >= T_BGB - 1) begin
        bgb_cnt<= 0;
        bgb<=~bgb;
    end else
        bgb_cnt<= bgb_cnt+1;
end

genvar gi;
generate
    for (gi=0;gi<N;gi=gi+1) begin:drv

        wire[2:0]act_m=gpio_tx[gi*8+5+:3];

        reg[2:0]ast;
        reg[27:0]acnt;

        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                ast<=0;
                acnt<=0;
                abit_r[gi]<= 0;
            end else begin
                case (ast)
                    3'd0:begin
                        abit_r[gi]<= 0;
                        acnt<= 0;
                        if ((act_m==3'b100 && eof[gi])||(act_m==3'b101 && sof[gi])) begin
                            ast <= 3'd1;
                            abit_r[gi]<=1;
                        end
                    end
                    3'd1:begin
                        abit_r[gi]<=1;
                        if (acnt >= T_STRON-1) begin
                            ast<=3'd2;
                            acnt<=0;
                        end else
                            acnt<=acnt+1;
                    end
                    3'd2: begin
                        abit_r[gi]<= 1;
                        if ((act_m==3'b100 && eof[gi])||(act_m==3'b101 && sof[gi]))
                            acnt <= 0;
                        else if (T_MAXON != 0 && acnt>=T_MAXON-1) begin
                            ast<=3'd3;
                            acnt<=0;
                            abit_r[gi] <= 0;
                        end else
                            acnt<=acnt+1;
                    end
                    3'd3: begin
                        abit_r[gi]<=0;
                        if (T_FRCOFF==0 || acnt>=T_FRCOFF-1) begin
                            ast<=3'd4;
                            acnt<=0;
                        end else
                            acnt<=acnt+1;
                    end
                    3'd4: begin
                        abit_r[gi]<=0;
                        if (T_STROFF==0 || acnt>=T_STROFF-1) begin
                            ast<= 3'd0;
                            acnt<=0;
                        end else
                            acnt<=acnt+1;
                    end
                    default: ast<= 0;
                endcase
            end
        end
    end
endgenerate

integer ci;
always @(*) begin
    for (ci=0; ci<N; ci=ci+1) begin
        case (gpio_tx[ci*8+5+:3])
            3'd0:od_bits[ci*3]=1'b0;
            3'd1:od_bits[ci*3]=1'b1;
            3'd2:od_bits[ci*3]= bga;
            3'd3:od_bits[ci*3]=~bga;
            3'd4:od_bits[ci*3]=abit_r[ci];
            3'd5:od_bits[ci*3]=abit_r[ci];
            3'd6:od_bits[ci*3]=bgb;
            default:od_bits[ci*3]=~bgb;
        endcase

        case (gpio_tx[ci*8+3+:2])
            2'd0:od_bits[ci*3+1]=1'b0;
            2'd1:od_bits[ci*3+1]=1'b1;
            2'd2:od_bits[ci*3+1]=bga;
            default:od_bits[ci*3+1]=~bga;
        endcase

        case (gpio_tx[ci*8+:3])
            3'd0:od_bits[ci*3+2]=1'b0;
            3'd1:od_bits[ci*3+2]=1'b1;
            3'd2:od_bits[ci*3+2]=bga;
            3'd3:od_bits[ci*3+2]=~bga;
            3'd6:od_bits[ci*3+2]=bgb;
            3'd7:od_bits[ci*3+2]=~bgb;
            default:od_bits[ci*3+2]=1'b0;
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hcnt<=0;
        pos<=0;
        rx_buf<=0;
        gpio_rx<=0;
        rx_rdy<=0;
        od_snap<=0;
        SCLK<=1;
        SLOAD<=1;
        SDO<=1;
    end else begin
        rx_rdy<=0;

        if(!en) begin
            SCLK<=0;
            SLOAD<=0;
            SDO<=1;
            hcnt<=0;
            pos<=0;
            od_snap<=od_bits;
        end else begin
            if (hcnt<HALF-1) begin
                hcnt<=hcnt+1;
            end else begin
                hcnt<=0;
                SCLK<=~SCLK;

                if(SCLK)begin
                    if (pos<N*3)
                        rx_buf[pos]<=SDI;

                    if (pos==N*3) begin
                        gpio_rx<=rx_buf;
                        rx_rdy<=1;
                        od_snap<=od_bits;
                    end

                    pos<=(pos==FL-1) ? 8'd0 : pos+1;

                end else begin
                    if (pos<N*3) begin
                        SLOAD<=0;
                        SDO<=od_snap[pos];
                    end else if(pos==N*3) begin
                        SLOAD<=1;
                        SDO<=0;
                    end else begin
                        SLOAD<=0;
                        SDO<=0;
                    end
                end
            end
        end
    end
end

endmodule
