// Instruction cache: 8-set, 2-way set-associative, 8-word (32-byte) lines.
//
// Data arrays use SYNCHRONOUS (registered) reads so Yosys maps them to iCE40
// EBR block RAM instead of logic-cell flip-flops. Consequence: a hit takes
// 2 cycles (cycle 0 = lookup / issue BRAM read, cycle 1 = compare + serve).
// Tags/valid/LRU stay as registers (small) for combinational hit detection.
//
// Miss: fetch 8 words from flash into the LRU-evicted way, then serve the
// requested word. flash_valid is driven from registered FSM state, so there
// is no combinational loop back through spimemio.ready.

module icache #(parameter NSETS = 8) (
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
    localparam INDEX_BITS = $clog2(NSETS);            // 3
    localparam TAG_BITS   = 24 - INDEX_BITS - 3 - 2; // 16
    localparam LADDR_BITS = INDEX_BITS + 3;          // {index,word} = 6 bits → 64 entries
    // Address layout: [1:0] byte | [4:2] word-in-line | [INDEX] index | [..23] tag

    localparam CACHE_EN = 1'b1;
    //localparam CACHE_EN = 1'b0; // bypass cache for baseline measurement

    localparam S_IDLE  = 3'd0,
               S_EVAL  = 3'd1,
               S_FILL  = 3'd2,
               S_GAP   = 3'd3,
               S_SERVE = 3'd4;

    // -------------------------------------------------------
    // Tag / valid / LRU — registers (combinational read)
    reg [TAG_BITS-1:0] tag0   [0:NSETS-1];
    reg [TAG_BITS-1:0] tag1   [0:NSETS-1];
    reg                valid0 [0:NSETS-1];
    reg                valid1 [0:NSETS-1];
    reg                lru    [0:NSETS-1]; // 0 = evict way0 next, 1 = evict way1 next

    // Data — synchronous-read memories → inferred as EBR block RAM
    reg [31:0] data0 [0:(NSETS*8)-1];
    reg [31:0] data1 [0:(NSETS*8)-1];

    integer kk;
    initial begin
        for (kk = 0; kk < NSETS; kk = kk+1) begin
            valid0[kk] = 0;
            valid1[kk] = 0;
            lru[kk]    = 0;
        end
    end

    // -------------------------------------------------------
    // Live address decomposition
    wire [2:0]            word  = cpu_addr[4:2];
    wire [INDEX_BITS-1:0] index = cpu_addr[4+INDEX_BITS:5];
    wire [TAG_BITS-1:0]   tag   = cpu_addr[23:5+INDEX_BITS];

    // Combinational hit detection (tags are registers)
    wire hit0_c = CACHE_EN && cpu_valid && valid0[index] && (tag0[index] == tag);
    wire hit1_c = CACHE_EN && cpu_valid && valid1[index] && (tag1[index] == tag);

    // Synchronous BRAM read port (reads the live address every cycle)
    reg  [31:0] rdata0_q, rdata1_q;
    wire [LADDR_BITS-1:0] rd_addr = {index, word};
    always @(posedge clk) begin
        rdata0_q <= data0[rd_addr];
        rdata1_q <= data1[rd_addr];
    end

    // -------------------------------------------------------
    // FSM state and captured lookup info
    reg [2:0]             state;
    reg                   hit0_r, hit1_r;
    reg [INDEX_BITS-1:0]  index_r;
    reg [TAG_BITS-1:0]    tag_r;
    reg [2:0]             word_r;
    reg [2:0]             fc;      // fill word counter
    reg                   evict_r; // way to evict for this fill
    reg [31:0]            ret;     // requested word captured during fill

    // -------------------------------------------------------
    // Outputs
    assign cpu_ready = (state == S_EVAL && (hit0_r || hit1_r)) || (state == S_SERVE);
    assign cpu_rdata = (state == S_SERVE) ? ret :
                       (hit0_r ? rdata0_q : rdata1_q);

    assign flash_valid = (state == S_FILL);
    assign flash_addr  = {tag_r, index_r, fc, 2'b00};

    // -------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < NSETS; i = i+1) begin
                valid0[i] <= 0;
                valid1[i] <= 0;
                lru[i]    <= 0;
            end
            state <= S_IDLE;
            fc    <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cpu_valid) begin
                        // BRAM read of live addr is in flight; capture lookup
                        hit0_r  <= hit0_c;
                        hit1_r  <= hit1_c;
                        index_r <= index;
                        tag_r   <= tag;
                        word_r  <= word;
                        evict_r <= lru[index];
                        state   <= S_EVAL;
                    end
                end

                S_EVAL: begin
                    if (hit0_r || hit1_r) begin
                        // Hit served this cycle (cpu_ready combinational). Touch LRU.
                        lru[index_r] <= hit0_r ? 1'b1 : 1'b0;
                        state <= S_IDLE;
                    end else begin
                        fc    <= 0;
                        state <= S_FILL;
                    end
                end

                S_FILL: begin
                    if (flash_ready) begin
                        // Write fetched word into the evicted way's BRAM
                        if (evict_r == 1'b0) data0[{index_r, fc}] <= flash_rdata;
                        else                 data1[{index_r, fc}] <= flash_rdata;

                        if (fc == word_r) ret <= flash_rdata;

                        if (fc == 3'd7) begin
                            // Line complete — commit tag/valid, flip LRU
                            if (evict_r == 1'b0) begin
                                tag0[index_r]   <= tag_r;
                                valid0[index_r] <= 1'b1;
                            end else begin
                                tag1[index_r]   <= tag_r;
                                valid1[index_r] <= 1'b1;
                            end
                            lru[index_r] <= ~evict_r;
                            state <= S_SERVE;
                        end else begin
                            state <= S_GAP;
                        end
                    end
                end

                S_GAP: begin
                    // One cycle with flash_valid=0 so spimemio sees a fresh
                    // transaction for the next word
                    fc    <= fc + 1;
                    state <= S_FILL;
                end

                S_SERVE: begin
                    // cpu_ready asserted this cycle; return the captured word
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
