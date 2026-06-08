/*
this testbench tests that the cache correctly evicts previous data to replace it with new data.

results:
# KERNEL: [TEST 3] Conflict eviction  (IDX_STRIDE=0x200)
# KERNEL:   Fill A (first read, miss)  : 18 cycles
# KERNEL:   Fill B (evict A, miss): 18 cycles
# KERNEL:   Re-read A (miss)   : 18 cycles
# KERNEL:   Re-read A (hit) : 2 cycles
*/

module tb;

  reg resetn;
  reg cpu_valid, cpu_ready, flash_valid, flash_ready;
  reg [23:0] cpu_addr;
  reg [31:0] cpu_rdata;
  reg [23:0] flash_addr;
  reg [31:0] flash_rdata;

  //clock toggling
  reg clk;
  always #2 clk <= ~clk;


  integer total_accesses, total_cycles, hit_count, miss_count;
  localparam INDEX_BITS = 5; //there are 32 bits so 2**5
  localparam IDX_STRIDE = 1 << (4 + INDEX_BITS);   // 0x200

  // temporaries
  integer     i, j;
  reg [23:0]  addr_a, addr_b;
  reg [31:0]  rdata_a, rdata_b;
  integer     cyc_a, cyc_b;
  integer     errors;


  initial begin
    clk = 0;
    resetn = 0;
    cpu_valid = 0;
    flash_ready = 0;

    repeat(4) @(posedge clk);
    @(negedge clk); resetn = 1;
    @(posedge clk);



    $display("\n[TEST 3] Conflict eviction  (IDX_STRIDE=0x%03X)",
             IDX_STRIDE);
    addr_a = 24'h003000;
    addr_b = addr_a + IDX_STRIDE; // same index, tag differs

    cpu_read(addr_a, rdata_a, cyc_a);
    $display("  Fill A (first read, miss)  : %0d cycles", cyc_a);

    cpu_read(addr_b, rdata_b, cyc_b);
    $display("  Fill B (evict A, miss): %0d cycles", cyc_b);

    // Re-read A — must miss (evicted by B)
    cpu_read(addr_a, rdata_a, cyc_a);
    $display("  Re-read A (miss)   : %0d cycles", cyc_a);

    cpu_read(addr_a, rdata_a, cyc_a);
    $display("  Re-read A (hit) : %0d cycles", cyc_a);

    $finish;
  end

  initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
  end


  //---------- check data is correct ---------
  reg [31:0] data;

  task check;
    input [23:0] addr;
    input [31:0] exp_data;
    input [63:0] label; 
    begin
      integer cycles;
      cpu_read(addr, data, cycles);

      if (data !== exp_data) begin
        $display("FAIL  addr=0x%06X  got=0x%08X  exp=0x%08X", addr, data, exp_data);
        errors = errors + 1;
      end else
        $display("PASS  addr=0x%06X  data=0x%08X, cycles = %2d", addr, data, cycles);
    end
  endtask


  //------ flash sim ----------
  localparam FLASH_LAT = 1;        // cycles per word
  integer flash_cnt;
  initial begin flash_cnt = 0; end


  always @(posedge clk) begin
    //start 
    if (!resetn) begin
      flash_ready <= 0;
      flash_rdata <= 0;
      flash_cnt   <= 0;

    end else if (!flash_valid) begin //waiting for flash_valid
      flash_ready <= 0;
      flash_cnt <= 0;

    end else if (flash_cnt == FLASH_LAT) begin
      flash_ready <= 1; //only ready once latency sim finished
      flash_rdata <= flash_addr + 1;

      flash_cnt <= 0; //reset
    end else begin
      flash_cnt <= flash_cnt + 1; //counter
      flash_ready <= 0;
    end
  end

  //--------- CPU sim ----------------
  task cpu_read;
    input [23:0] addr;
    output [31:0] rdata;
    output integer cycles;
    begin
      @(negedge clk);
      cpu_valid = 1;
      cpu_addr  = addr;
      cycles = 0;

      @(posedge clk);  // IDLE → EVAL
      cycles = cycles + 1;


      //       $display("waiting");
      while (!cpu_ready) @(posedge clk) cycles = cycles + 1;
      rdata = cpu_rdata;

      //       $display("reading");

      @(negedge clk);
      cpu_valid = 0;
      @(posedge clk);

    end
  endtask


  //device under test
  dcache #(.NSETS(32)) dut (
    .clk        (clk),
    .resetn     (resetn),
    .cpu_valid  (cpu_valid),
    .cpu_addr   (cpu_addr),
    .cpu_ready  (cpu_ready),
    .cpu_rdata  (cpu_rdata),
    .flash_valid(flash_valid),
    .flash_addr (flash_addr),
    .flash_ready(flash_ready),
    .flash_rdata(flash_rdata)
  );


endmodule

