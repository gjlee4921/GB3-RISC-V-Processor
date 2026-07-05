
/*
this code loops through the cache, where it should all be hits, 64 times.

results:
# KERNEL: [TEST 5] Hot-loop throughput (64 reads)
# KERNEL: --------------------------------------------
# KERNEL: TEST: Hot loop x64
# KERNEL:   Accesses  : 64
# KERNEL:   Cycles    : 128  (avg 2.00 cyc/access)
# KERNEL:   Hits      : 64
# KERNEL:   Misses    : 0
# KERNEL:   Hit rate  : 100.0%

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
 
    // Temporaries
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
 

      $display("\n[TEST 5] Hot-loop throughput (64 reads)");
      total_accesses=0; total_cycles=0; hit_count=0; miss_count=0;
      addr_a = 24'h020000;
      cpu_read(addr_a, rdata_a, cyc_a); // prime

      for (i = 0; i < 64; i = i+1) begin
        cpu_read(addr_a, rdata_b, cyc_b);
        total_accesses = total_accesses + 1;
        total_cycles   = total_cycles   + cyc_b;
        if (cyc_b <= 4) hit_count = hit_count + 1;
        else            miss_count = miss_count + 1;
      end
      print_perf("Hot loop x64",
                 total_accesses, total_cycles, hit_count, miss_count);

 
        $finish;
    end
 
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

 // ---- printing results ----
  
      task print_perf;
        input [8*24-1:0] label;
        input integer    accesses, cycles, hits, misses;
        begin
            $display("--------------------------------------------");
            $display("TEST: %0s", label);
            $display("  Accesses  : %0d", accesses);
            $display("  Cycles    : %0d  (avg %.2f cyc/access)",
                     cycles, (1.0*cycles)/accesses);
            $display("  Hits      : %0d", hits);
            $display("  Misses    : %0d", misses);
            $display("  Hit rate  : %.1f%%", (100.0*hits)/accesses);
        end
    endtask

  
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
  
  