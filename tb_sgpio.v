`timescale 1ns/1ps

module tb_sgpio;

reg clk, rst_n, en;
reg  [11:0] tx_led;
reg  SDI;

wire [11:0] rx_status;
wire done;
wire SCLK, SLOAD, SDO;

sgpio_initiator DUT(
    .clk(clk),
    .rst_n(rst_n),
    .en(en),
    .tx_led(tx_led),
    .rx_status(rx_status),
    .done(done),
    .SCLK(SCLK),
    .SLOAD(SLOAD),
    .SDO(SDO),
    .SDI(SDI)
);

// 50MHz clock
always #10 clk = ~clk;

// one full frame at HALF=5 => 17 * 5 * 2 * 10ns = 1700ns
// keeping HALF small so sim runs fast, change to 250 for real

defparam DUT.HALF = 5;


reg sclk_prev;
reg [4:0] tcnt;
reg synced;
reg [11:0] sdatain_pat;

initial begin
    sclk_prev    = 1;
    tcnt         = 0;
    synced       = 0;
    sdatain_pat  = 12'b000_000_001_000;
    SDI          = 1;
end

always @(posedge clk) begin
    sclk_prev <= SCLK;

    
    if(SCLK && !sclk_prev) begin
        if(SLOAD) begin
            synced <= 1;
            tcnt   <= 0;
            SDI    <= 1;
        end
        else if(synced) begin
            if(tcnt >= 4 && tcnt < 16)
                SDI <= sdatain_pat[tcnt - 4];
            else
                SDI <= 1;

            if(tcnt < 16)
                tcnt <= tcnt + 1;
        end
    end
end

integer fcount;

initial begin
    $dumpfile("sgpio_wave.vcd");
    $dumpvars(0, tb_sgpio);

    clk    = 0;
    rst_n  = 0;
    en     = 0;
    tx_led = 0;
    fcount = 0;

    #50;
    rst_n = 1;
    #30;

    
    en     = 1;
    tx_led = 12'b000_000_000_000;
    #5100;

    
    tx_led = 12'b000_000_000_001;
    #3400;

    
    tx_led = 12'b000_000_010_000;
    #3400;

    
    tx_led = 12'b000_100_000_000;
    #3400;

    
    tx_led = 12'b111_000_000_000;
    #3400;

    
    tx_led = 12'b111_100_010_001;
    #5100;

   
    en = 0;
    #3400;

    if(SCLK===1 && SLOAD===1 && SDO===1)
        $display("PASS - bus tristated after disable");
    else
        $display("FAIL - bus not tristated, SCLK=%b SLOAD=%b SDO=%b", SCLK, SLOAD, SDO);

    
    en     = 1;
    tx_led = 12'b111_111_111_111;
    #5100;

    $display("sim done, total frames = %0d", fcount);
    $stop;
end

always @(posedge clk) begin
    if(done) begin
        fcount = fcount + 1;
        $display("frame %0d  rx_status=%012b  time=%0t", fcount, rx_status, $time);

        $display("  D0: act=%b loc=%b err=%b", rx_status[0], rx_status[1], rx_status[2]);
        $display("  D1: act=%b loc=%b err=%b", rx_status[3], rx_status[4], rx_status[5]);
        $display("  D2: act=%b loc=%b err=%b", rx_status[6], rx_status[7], rx_status[8]);
        $display("  D3: act=%b loc=%b err=%b", rx_status[9], rx_status[10], rx_status[11]);

        if(fcount >= 2) begin
            if(rx_status === 12'b000_000_001_000)
                $display("  PASS");
            else
                $display("  FAIL - got %012b", rx_status);
        end
    end
end

initial
    $monitor("t=%0t SCLK=%b SLOAD=%b SDO=%b SDI=%b done=%b rx=%012b",
              $time, SCLK, SLOAD, SDO, SDI, done, rx_status);

endmodule
