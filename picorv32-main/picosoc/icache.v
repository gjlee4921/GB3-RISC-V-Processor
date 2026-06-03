module icache #(parameter NSETS = 16) (
    input         clk,
    input         resetn,

    // CPU side
    input         cpu_valid,
    input  [23:0] cpu_addr,
    output        cpu_ready,
    output [31:0] cpu_rdata,

    // Flash side
    output        flash_valid,
    output [23:0] flash_addr,
    input         flash_ready,
    input  [31:0] flash_rdata
);
    localparam INDEX_BITS = $clog2(NSETS);        // 4
    localparam TAG_BITS   = 24 - INDEX_BITS - 2;  // 18

    reg [TAG_BITS-1:0] tag_array   [0:NSETS-1];
    reg                valid_array [0:NSETS-1];
    reg [31:0]         data_array  [0:NSETS-1];

    integer i;
    initial begin
        for (i = 0; i < NSETS; i = i+1) begin
            valid_array[i] = 0;
            tag_array[i]   = 0;
            data_array[i]  = 0;
        end
    end

    wire [INDEX_BITS-1:0] index = cpu_addr[INDEX_BITS+1:2];  // bits [5:2]
    wire [TAG_BITS-1:0]   tag   = cpu_addr[23:INDEX_BITS+2]; // bits [23:6]

    //wire hit = cpu_valid && valid_array[index] && (tag_array[index] == tag);
    wire hit = 1'b0; // for baseline without cache
    
    // Serve hits from cache (1 cycle), misses from flash (write on fill)
    assign flash_valid = cpu_valid && !hit;
    assign flash_addr  = cpu_addr;
    assign cpu_ready   = hit ? 1'b1 : flash_ready;
    assign cpu_rdata   = hit ? data_array[index] : flash_rdata;

    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < NSETS; i = i+1)
                valid_array[i] <= 0;
        end else if (flash_ready) begin
            data_array[index]  <= flash_rdata;
            tag_array[index]   <= tag;
            valid_array[index] <= 1;
        end
    end
endmodule