`timescale 1ns/1ps

module tb_sgpio;

parameter N=4;
parameter HALF=5;
parameter TBASE=80;

localparam DB=N*3;
localparam FL=DB+5;
localparam TCLK=10;
localparam TF=TCLK*HALF*2*FL;

reg clk,rst_n,en;
reg[3:0] bga_rate, bgb_rate, frc_off, max_on, str_off, str_on;
reg[(N*8)-1:0] gpio_tx;
reg[N-1:0] sof_r, eof_r;
reg SDI;

wire[(N*3)-1:0] gpio_rx;
wire rx_rdy;
wire SCLK,SLOAD,SDO;

sgpio_initiator #(.N(N), .HALF(HALF), .TBASE(TBASE)) DUT (
    .clk(clk),.rst_n(rst_n),.en(en),.bga_rate(bga_rate),.bgb_rate(bgb_rate),.frc_off(frc_off),.max_on(max_on),
    .str_off(str_off),.str_on(str_on),.gpio_tx(gpio_tx),.sof(sof_r),.eof(eof_r),
    .gpio_rx(gpio_rx),.rx_rdy(rx_rdy),.SCLK(SCLK),.SLOAD(SLOAD),.SDO(SDO),.SDI(SDI));

initial clk=0;
always #(TCLK/2) clk=~clk;

localparam [DB-1:0] ID_PAT = 12'b000_000_001_000;
localparam RST64 = TBASE * 8;

reg sclk_d;
reg[7:0]tcnt;
reg synced;
reg[19:0]rst_timer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sclk_d <=1;
        tcnt<=0;
        synced<=0;
        SDI<=1;
        rst_timer<=0;
    end else begin
        sclk_d<=SCLK;

        if (SCLK && SLOAD && SDO) begin
            if (rst_timer >= RST64 - 1) begin
                $display("[TGT %0t] 64ms reset detected", $time);
                rst_timer<=0;
            end else
                rst_timer<=rst_timer+1;
        end else
            rst_timer<=0;

        if (SCLK && !sclk_d) begin
            if (SLOAD) begin
                synced<=1;
                tcnt<=0;
                SDI<=1;
            end else if(synced) begin
                if (tcnt>=4 && tcnt<4+DB)
                    SDI<=ID_PAT[tcnt-4];
                else
                    SDI<=1;
                if(tcnt<FL-1) tcnt<=tcnt+1;
            end
        end
    end
end

integer fc;
initial fc = 0;

always @(posedge clk) begin
    if (rx_rdy) begin
        fc=fc+1;
        $display("frame %2d @ %0t  rx=%012b", fc, $time, gpio_rx);
        if (fc>=2) begin
            if(gpio_rx===ID_PAT) $display("  PASS rx");
            else $display("  FAIL rx: got %012b  exp %012b", gpio_rx, ID_PAT);
        end
    end
end

initial begin
    $dumpfile("sgpio_wave.vcd");
    $dumpvars(0, tb_sgpio);

    clk=0; rst_n=0; en=0;
    bga_rate=4'h0; bgb_rate=4'h1;
    frc_off=4'h1; max_on=4'h2;
    str_off=4'h0; str_on=4'h0;
    gpio_tx={N{8'b000_00_000}};
    sof_r=0; eof_r=0; SDI=1; fc=0;

    #50;
    rst_n=1;
    $display("--- reset released ---");
    #30;

    $display("--- T1: bus idle en=0 ---");
    en = 0;
    #(TF*3);
    if (SCLK===0 && SLOAD===0)
        $display("PASS T1: SCLK=0 SLOAD=0");
    else
        $display("FAIL T1: SCLK=%b SLOAD=%b", SCLK, SLOAD);

    $display("--- T2: all LEDs off ---");
    gpio_tx={N{8'b000_00_000}};
    en = 1;
    #(TF*4);

    $display("--- T3: all LEDs always-on ---");
    gpio_tx={N{8'b001_01_001}};
    #(TF*3);

    $display("--- T4: activity blink gen A on-first ---");
    gpio_tx={N{8'b010_00_000}};
    #(TF*6);

    $display("--- T5: activity blink gen A off-first ---");
    gpio_tx={N{8'b011_00_000}};
    #(TF*6);

    $display("--- T6: activity blink gen B on-first ---");
    gpio_tx={N{8'b110_00_000}};
    #(TF*6);

    $display("--- T7: locate on ---");
    gpio_tx={N{8'b000_01_000}};
    #(TF*3);
    $display("--- T7b: locate blink gen A ---");
    gpio_tx={N{8'b000_10_000}};
    #(TF*5);

    $display("--- T8: error on ---");
    gpio_tx={N{8'b000_00_001}};
    #(TF*3);
    $display("--- T8b: error blink gen A ---");
    gpio_tx={N{8'b000_00_010}};
    #(TF*5);
    $display("--- T8c: error blink gen B ---");
    gpio_tx={N{8'b000_00_110}};
    #(TF*5);

    $display("--- T9: SOF auto-flash D0 mode 101 ---");
    gpio_tx={N{8'b101_00_000}};
    #(TF*3);
    sof_r=4'b0001; #(TCLK*6); sof_r=0;
    #(TF*12);
    sof_r=4'b0001; #(TCLK*4); sof_r=0;
    #(TF*12);

    $display("--- T10: EOF auto-flash D2 mode 100 ---");
    gpio_tx={N{8'b100_00_000}};
    #(TF*2);
    eof_r=4'b0100; #(TCLK*4); eof_r=0;
    #(TF*12);

    $display("--- T11: mixed pattern ---");
    gpio_tx={8'b001_00_001,8'b010_00_110,8'b000_10_001,8'b101_01_000};
    #(TF*3);
    sof_r = 4'b0001; #(TCLK*4); sof_r=0;
    #(TF*8);

    $display("--- T12: disable ---");
    en = 0;
    #(TF*3);
    if (SCLK===0 && SLOAD===0)
        $display("PASS T12: SCLK=0 SLOAD=0");
    else
        $display("FAIL T12: SCLK=%b SLOAD=%b", SCLK, SLOAD);

    en=1;
    gpio_tx={N{8'b001_01_001}};
    #(TF*4);

    $display("--- T13: full reset tristate ---");
    rst_n=0;
    #(TF*3);
    if (SCLK===1 && SLOAD===1 && SDO===1)
        $display("PASS T13: SCLK=SLOAD=SDO=1 tristate");
    else
        $display("FAIL T13: SCLK=%b SLOAD=%b SDO=%b", SCLK, SLOAD, SDO);

    rst_n=1; #30;
    en = 1;
    gpio_tx={N{8'b001_01_001}};
    #(TF*4);

    $display("--- sim done, frames=%0d ---", fc);
    $stop;
end

initial
    $monitor("t=%0t SCLK=%b SLOAD=%b SDO=%b SDI=%b rdy=%b rx=%012b",
              $time, SCLK, SLOAD, SDO, SDI, rx_rdy, gpio_rx);

endmodule
