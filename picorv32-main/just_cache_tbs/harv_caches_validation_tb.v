/*
currently this just checks validation
*/`

timescale 1ns/1ps

module tb;

// ----------------- i cache ------------------------------------------
  reg        clk, resetn, mem_instr;
  reg [31:0] data_line;
  
reg        ic_cpu_valid;
reg [23:0] ic_cpu_addr;
wire       ic_cpu_ready;
wire[31:0] ic_cpu_rdata;
wire       ic_flash_valid;
wire[23:0] ic_flash_addr;
reg        ic_flash_ready;
reg [31:0] ic_flash_rdata;

icache uut_ic (
    .clk        (clk),
    .resetn     (resetn),
    .cpu_valid  (ic_cpu_valid),
    .cpu_addr   (ic_cpu_addr),
    .cpu_ready  (ic_cpu_ready),
    .cpu_rdata  (ic_cpu_rdata),
    .flash_valid(ic_flash_valid),
    .flash_addr (ic_flash_addr),
    .flash_ready(ic_flash_ready),
    .flash_rdata(ic_flash_rdata)
);


// ----------------- d cache ------------------------------------------

reg        dc_cpu_valid;
reg [23:0] dc_cpu_addr;
wire       dc_cpu_ready;
wire[31:0] dc_cpu_rdata;
wire       dc_flash_valid;
wire[23:0] dc_flash_addr;
reg        dc_flash_ready;
reg [31:0] dc_flash_rdata;

dcache uut_dc (
    .clk        (clk),
    .resetn     (resetn),
    .cpu_valid  (dc_cpu_valid),
    .cpu_addr   (dc_cpu_addr),
    .cpu_ready  (dc_cpu_ready),
    .cpu_rdata  (dc_cpu_rdata),
    .flash_valid(dc_flash_valid),
    .flash_addr (dc_flash_addr),
    .flash_ready(dc_flash_ready),
    .flash_rdata(dc_flash_rdata)
);

// clock
initial clk = 0;  always #5 clk <= ~clk;


integer errors;

  //---------flash sim ---------------
integer dc_flash_cnt, ic_flash_cnt;
  localparam FLASH_LAT = 2;
  
  initial begin dc_flash_cnt = 0; end

  always @(posedge clk) begin
    //start 
    if (!resetn) begin
      dc_flash_ready <= 0;
      dc_flash_rdata <= 0;
      dc_flash_cnt   <= 0;
      
    end else if (!dc_flash_valid) begin //waiting for flash_valid
      dc_flash_ready <= 0;
      dc_flash_cnt <= 0;
      
    end else if (dc_flash_cnt == FLASH_LAT) begin
      dc_flash_ready <= 1; //only ready once latency sim finished
      dc_flash_rdata <= dc_flash_addr + 1;
      
      dc_flash_cnt <= 0; //reset
    end else begin
      dc_flash_cnt <= dc_flash_cnt + 1; //counter
      dc_flash_ready <= 0;
    end
  end

  
  initial begin ic_flash_cnt = 0; end

  always @(posedge clk) begin
    //start 
    if (!resetn) begin
      ic_flash_ready <= 0;
      ic_flash_rdata <= 0;
      ic_flash_cnt   <= 0;
      
    end else if (!ic_flash_valid) begin //waiting for flash_valid
      ic_flash_ready <= 0;
      ic_flash_cnt <= 0;

    end else if (ic_flash_cnt == FLASH_LAT) begin
      ic_flash_ready <= 1; //only ready once latency sim finished
      ic_flash_rdata <= ic_flash_addr + 1;

      ic_flash_cnt <= 0; //reset
    end else begin
      ic_flash_cnt <= ic_flash_cnt + 1; //counter
      ic_flash_ready <= 0;
    end
  end
  


// simulated cpu
reg [31:0] ic_result, dc_result;

task ic_read;
    input [23:0] addr;
    integer timeout;
    begin
        @(negedge clk); 
        ic_cpu_valid = 1;
        ic_cpu_addr  = addr;
        timeout = 0;
        while (!ic_cpu_ready) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 200) begin
                $error("[IC] Timeout waiting for cpu_ready, addr=%h", addr);
                errors = errors + 1;
                ic_cpu_valid = 0;
                disable ic_read;
            end
        end
        ic_result = ic_cpu_rdata;
        @(negedge clk);
        ic_cpu_valid = 0;
    end
endtask

task dc_read;
    input [23:0] addr;
    integer timeout;
    begin
        @(negedge clk);
        dc_cpu_valid = 1;
        dc_cpu_addr  = addr;
        timeout = 0;
        while (!dc_cpu_ready) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 200) begin
                $error("[DC] Timeout waiting for cpu_ready, addr=%h", addr);
                errors = errors+1;
                dc_cpu_valid = 0;
                disable dc_read;
            end
        end
        dc_result = dc_cpu_rdata;
        @(negedge clk);
        dc_cpu_valid = 0;
    end
endtask

  task display_results;
    input [31:0] results;
    input [31:0] exp;

    if (results !== exp) begin
      $display("FAIL  exp=0x%06X  got=0x%08X", exp, results);
      errors = errors + 1;
    end else $display("PASS  exp=0x%06X  data=0x%08X", exp, results);
  endtask


  
// ============= Main test body ==========
integer i;

initial begin
    errors = 0;
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    // Reset both caches
    resetn = 0; ic_cpu_valid = 0; ic_flash_ready = 0; ic_flash_rdata = 0;
    dc_cpu_valid = 0; dc_flash_ready = 0; dc_flash_rdata = 0;
    repeat(4) @(posedge clk);
    resetn = 1;
    @(posedge clk); #1;

    // ---------------Validating IC --------------------------

  $display("IC - Cold miss then warm hit");
   ic_read(24'h000018);

  display_results(ic_result, 24'h000019);
  
  ic_read(24'h000018); 
  
  display_results(ic_result, 24'h000019);

 
   // ---------------Validating DC ---------------------

  $display("DC - Cold miss then warm hit");
  dc_read(24'h000014); 

  display_results(dc_result, 24'h000015);

   dc_read(24'h000014);

  display_results(dc_result, 24'h000015);


end

// timeout in case gets stuck in loop
initial begin
    #100000;
    $error("GLOBAL TIMEOUT");
    $finish;
end

endmodule