// Lean testbench: instantiates picosoc directly (no SB_IO, no VCD),
// tristate wires to spiflash, UART decoder, debug probes.
`timescale 1 ns / 1 ps
module testbench;
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // resetn held low for 64 cycles
    reg [6:0] reset_cnt = 0;
    wire resetn = &reset_cnt;
    always @(posedge clk) reset_cnt <= reset_cnt + !resetn;

    // Flash tristate wires
    wire flash_csb, flash_clk;
    wire flash_io0_oe, flash_io0_do; wire flash_io0_di;
    wire flash_io1_oe, flash_io1_do; wire flash_io1_di;
    wire flash_io2_oe, flash_io2_do; wire flash_io2_di;
    wire flash_io3_oe, flash_io3_do; wire flash_io3_di;

    wire flash_io0 = flash_io0_oe ? flash_io0_do : 1'bz;
    wire flash_io1 = flash_io1_oe ? flash_io1_do : 1'bz;
    wire flash_io2 = flash_io2_oe ? flash_io2_do : 1'bz;
    wire flash_io3 = flash_io3_oe ? flash_io3_do : 1'bz;
    assign flash_io0_di = flash_io0;
    assign flash_io1_di = flash_io1;
    assign flash_io2_di = flash_io2;
    assign flash_io3_di = flash_io3;

    // IO memory (GPIO/7seg — just absorb writes, return 0)
    reg iomem_ready; reg [31:0] iomem_rdata;
    wire iomem_valid; wire [3:0] iomem_wstrb;
    wire [31:0] iomem_addr, iomem_wdata;
    always @(posedge clk) begin
        iomem_ready <= 0;
        if (iomem_valid && !iomem_ready && iomem_addr[31:24]==8'h03)
            iomem_ready <= 1;
    end
    assign iomem_rdata = 0;

    wire ser_tx;

    picosoc #(
        .BARREL_SHIFTER(0), .ENABLE_MUL(0), .ENABLE_DIV(0),
        .ENABLE_FAST_MUL(1), .ENABLE_COMPRESSED(0),
        .MEM_WORDS(256)          // 1 kB — same as icebreaker_tb.v
    ) soc (
        .clk(clk), .resetn(resetn),
        .ser_tx(ser_tx), .ser_rx(1'b1),
        .flash_csb(flash_csb), .flash_clk(flash_clk),
        .flash_io0_oe(flash_io0_oe), .flash_io1_oe(flash_io1_oe),
        .flash_io2_oe(flash_io2_oe), .flash_io3_oe(flash_io3_oe),
        .flash_io0_do(flash_io0_do), .flash_io1_do(flash_io1_do),
        .flash_io2_do(flash_io2_do), .flash_io3_do(flash_io3_do),
        .flash_io0_di(flash_io0_di), .flash_io1_di(flash_io1_di),
        .flash_io2_di(flash_io2_di), .flash_io3_di(flash_io3_di),
        .irq_5(1'b0), .irq_6(1'b0), .irq_7(1'b0),
        .iomem_valid(iomem_valid), .iomem_ready(iomem_ready),
        .iomem_wstrb(iomem_wstrb), .iomem_addr(iomem_addr),
        .iomem_wdata(iomem_wdata), .iomem_rdata(iomem_rdata)
    );

    spiflash flash (
        .csb(flash_csb), .clk(flash_clk),
        .io0(flash_io0), .io1(flash_io1),
        .io2(flash_io2), .io3(flash_io3)
    );

    // UART decoder: clkdiv=104 → half-period=52 cycles at 100MHz
    localparam ser_half_period = 52;
    reg [7:0] ser_buf;
    integer got_result = 0;

    always begin
        @(negedge ser_tx);
        repeat (ser_half_period) @(posedge clk);
        // start bit — now sample 8 data bits
        repeat (8) begin
            repeat (ser_half_period) @(posedge clk);
            repeat (ser_half_period) @(posedge clk);
            ser_buf = {ser_tx, ser_buf[7:1]};
        end
        repeat (ser_half_period) @(posedge clk);
        repeat (ser_half_period) @(posedge clk);
        if (ser_buf >= 32 && ser_buf < 127)
            $write("%c", ser_buf);
        else
            $write("[%0d]", ser_buf);
        if (ser_buf == "\n") begin
            $write("\n");
            $fflush;
        end
        // Stop once we see 'Result:' (enough data to compute speedup)
        if (ser_buf == "1" || ser_buf == "2" || ser_buf == "3") begin
            // crude: any digit in "Result: 0xNN" — keep running
        end
    end

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // Debug: first flash CSB deassert, first UART bit
    reg first_flash = 0, first_uart = 0;
    always @(posedge clk) begin
        if (!flash_csb && !first_flash) begin
            first_flash <= 1;
            $display("[cyc %0d] spimemio started (flash_csb low)", cyc);
        end
        if (!ser_tx && !first_uart) begin
            first_uart <= 1;
            $display("[cyc %0d] first UART TX bit", cyc);
        end
    end

    initial begin
        // Run for 5M cycles then stop
        repeat (30_000_000) @(posedge clk);
        $display("\n[cyc %0d] simulation limit reached", cyc);
        $finish;
    end
endmodule
