/*
This code was used for the direct mapped cache in dcache.v. It simulates CPU and flash memory to test how the cache handles hits and misses. The value of FLASH_LAT is taken from experimental results

simulation results:

# KERNEL: ---  first reads (all misses)  ---
# KERNEL: PASS  addr=0x000000  data=0x00000001, cycles = 18
# KERNEL: PASS  addr=0x000010  data=0x00000011, cycles = 18
# KERNEL: --- repeat reads ---
# KERNEL: PASS  addr=0x000000  data=0x00000001, cycles =  2
# KERNEL: PASS  addr=0x000010  data=0x00000011, cycles =  2
# KERNEL: --- new read ---
# KERNEL: PASS  addr=0x000020  data=0x00000021, cycles = 18

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
  
    initial begin
      clk = 0;
      resetn = 0;
      cpu_valid = 0;
      flash_ready = 0;
  
      repeat(4) @(posedge clk);
      @(negedge clk); resetn = 1;
      @(posedge clk);
 
      
      $display("data = address + 1");
      $display("---  first reads (all misses)  ---");
      check(24'h000000, 32'h000001, "miss0");
      check(24'h000010, 32'h000011, "miss1"); 

 
      $display("--- repeat reads ---");
        check(24'h000000, 24'h000001, "hit0");
        check(24'h000010, 24'h000011, "hit1");
      
      $display("--- new read ---");
      check(24'h000020, 24'h000021, "miss2");
 
      if (errors > 0) $display("FAILED — %0d error(s)", errors);
 
        $finish;
    end
 
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

  
  //---------- check data is correct ---------
  integer errors = 0;
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
  
  