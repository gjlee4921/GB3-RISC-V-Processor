// Data cache: 8-set, DIRECT-MAPPED, 4-word (16-byte) lines.
//
// Caches READ-ONLY data fetches from SPI flash (the .rodata section:
// static const arrays such as the Kalman filter matrices). All writes
// bypass the cache and are not seen here (data writes go to SRAM, not flash).
//
// DIRECT-MAPPED (not 2-way) on purpose: with ENABLE_DIV turned on for the full
// Kalman filter, the logic-cell budget is tight. A direct-mapped cache needs
// only one tag array and one comparator and no LRU, costing roughly half the
// logic of a 2-way design. Because .rodata is read largely sequentially, the
// 4-word lines capture the spatial locality and conflict misses are rare, so
// the direct-mapped form keeps almost all of the benefit at much lower area.
//
// Capacity: 8 sets × 4 words × 4 bytes = 128 bytes. Data array is a
// synchronous-read memory so Yosys maps it to EBR block RAM.

module dcache #(parameter NSETS = 8) (
    input         clk,
    input         resetn,

    // CPU side (data read requests from flash address space)
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
    localparam INDEX_BITS = $clog2(NSETS);
    localparam TAG_BITS   = 24 - INDEX_BITS - 2 - 2;
    localparam LADDR_BITS = INDEX_BITS + 2;

    localparam DCACHE_EN = 1'b1;
    //localparam DCACHE_EN = 1'b0; // bypass for baseline measurement

    localparam S_IDLE  = 3'd0,
               S_EVAL  = 3'd1,
               S_FILL  = 3'd2,
               S_GAP   = 3'd3,
               S_SERVE = 3'd4;

    // Tag / valid — registers (combinational read). One way only.
    reg [TAG_BITS-1:0] tag   [0:NSETS-1];
    reg                valid [0:NSETS-1];

    // Data — synchronous-read memory → inferred as EBR block RAM
    reg [31:0] data [0:(NSETS*4)-1];

    integer kk;
    initial begin
        for (kk = 0; kk < NSETS; kk = kk+1)
            valid[kk] = 0;
    end

    // Live address decomposition
    wire [1:0]            word  = cpu_addr[3:2];
    wire [INDEX_BITS-1:0] index = cpu_addr[3+INDEX_BITS:4];
    wire [TAG_BITS-1:0]   tagv  = cpu_addr[23:4+INDEX_BITS];

    // Combinational hit detection (single comparator)
    wire hit_c = DCACHE_EN && cpu_valid && valid[index] && (tag[index] == tagv);

    // Synchronous BRAM read (registered, one cycle latency)
    reg  [31:0] rdata_q;
    wire [LADDR_BITS-1:0] rd_addr = {index, word};
    always @(posedge clk)
        rdata_q <= data[rd_addr];

    // FSM state and captured lookup info
    reg [2:0]             state;
    reg                   hit_r;
    reg [INDEX_BITS-1:0]  index_r;
    reg [TAG_BITS-1:0]    tag_r;
    reg [1:0]             word_r;
    reg [1:0]             fc;
    reg [31:0]            ret;

    // Outputs
    assign cpu_ready = (state == S_EVAL && hit_r) || (state == S_SERVE);
    assign cpu_rdata = (state == S_SERVE) ? ret : rdata_q;

    assign flash_valid = (state == S_FILL);
    assign flash_addr  = {tag_r, index_r, fc, 2'b00};

    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < NSETS; i = i+1)
                valid[i] <= 0;
            state <= S_IDLE;
            fc    <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cpu_valid) begin
                        hit_r   <= hit_c;
                        index_r <= index;
                        tag_r   <= tagv;
                        word_r  <= word;
                        state   <= S_EVAL;
                    end
                end

                S_EVAL: begin
                    if (hit_r) begin
                        state <= S_IDLE;
                    end else begin
                        fc    <= 0;
                        state <= S_FILL;
                    end
                end

                S_FILL: begin
                    if (flash_ready) begin
                        data[{index_r, fc}] <= flash_rdata;

                        if (fc == word_r) ret <= flash_rdata;

                        if (fc == 2'd3) begin
                            tag[index_r]   <= tag_r;
                            valid[index_r] <= 1'b1;
                            state <= S_SERVE;
                        end else begin
                            state <= S_GAP;
                        end
                    end
                end

                S_GAP: begin
                    fc    <= fc + 1;
                    state <= S_FILL;
                end

                S_SERVE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
