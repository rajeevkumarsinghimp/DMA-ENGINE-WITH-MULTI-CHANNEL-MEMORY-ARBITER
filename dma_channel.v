// dma_channel.v
// Per-channel descriptor-driven DMA engine (scatter-gather).
// It requests AXI bursts from arbiter and provides data to write or consumes read data.
// Descriptor format (128-bit):
// [127:96] reserved/flags
// [95:64]  transfer_length_bytes (32-bit)
// [63:32]  dest_or_src_addr (32-bit)  (depending on op)
// [31:0]   next_descriptor_addr (32-bit) // zero for end-of-chain
//
// For simplicity we assume descriptor fetch is handled outside or via descriptor fetcher using the arbiter.

module dma_channel #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,
    parameter DESC_WIDTH = 128
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // control
    input  wire                   start,
    input  wire [ADDR_WIDTH-1:0]  desc_base,
    input  wire                   reset_ch,

    // arbiter request interface
    output reg                    req,          // request AXI transaction
    output reg [1:0]              type,         // 0 read, 1 write
    output reg [ADDR_WIDTH-1:0]   addr,
    output reg [15:0]             burst_len,
    output reg [DATA_WIDTH-1:0]   wdata,
    output reg                    wlast,
    input  wire                   grant,
    input  wire                   done,
    input  wire                   error,

    // status
    output reg [31:0]             status_out,

    // interrupt request output (per-channel)
    output reg                    irq_out
);

    // Local state machine for descriptor chain processing
    localparam IDLE  = 0;
    localparam FETCH_DESC = 1;
    localparam START_XFER = 2;
    localparam WAIT_DONE  = 3;
    localparam COMPLETE   = 4;
    localparam ERROR      = 5;

    reg [2:0] state, next_state;

    reg [ADDR_WIDTH-1:0] cur_desc_addr;
    reg [DESC_WIDTH-1:0] cur_desc;
    reg                  desc_valid;

    // fields extracted from descriptor
    reg [31:0] xfer_len;
    reg [ADDR_WIDTH-1:0] xfer_addr;
    reg [ADDR_WIDTH-1:0] next_desc;

    // For simplicity, implement a local descriptor parser handshake with desc_fetcher via 'req/grant' for descriptor reads.
    // Here we'll model descriptor fetch as: when state==FETCH_DESC set req=1, type=0 (read) and addr=cur_desc_addr
    // The arbiter will provide read data via an external path (not modeled fully here). To keep module synthesizable,
    // we'll assume descriptor fetch completes immediately when grant asserted and done asserted. In a real design,
    // descriptor fetch would be a read via AXI with R channel returning cur_desc.

    // Counters
    reg [31:0] bytes_remaining;

    // initialize
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req <= 1'b0;
            type <= 2'b00;
            addr <= {ADDR_WIDTH{1'b0}};
            burst_len <= 16'd0;
            wdata <= {DATA_WIDTH{1'b0}};
            wlast <= 1'b0;
            status_out <= 32'd0;
            irq_out <= 1'b0;
            cur_desc_addr <= {ADDR_WIDTH{1'b0}};
            cur_desc <= {DESC_WIDTH{1'b0}};
            desc_valid <= 1'b0;
            xfer_len <= 32'd0;
            xfer_addr <= {ADDR_WIDTH{1'b0}};
            next_desc <= {ADDR_WIDTH{1'b0}};
            bytes_remaining <= 32'd0;
        end else begin
            state <= next_state;

            // clear one-shot request bits when grant seen
            if (grant) begin
                req <= 1'b0;
            end

            // status updates
            if (state == COMPLETE) begin
                status_out <= status_out + 1; // count completed transfers (simple)
                irq_out <= 1'b1;
            end else begin
                // one-cycle pulse clear
                irq_out <= 1'b0;
            end

            // reset handling
            if (reset_ch) begin
                state <= IDLE;
                cur_desc_addr <= {ADDR_WIDTH{1'b0}};
                desc_valid <= 1'b0;
                bytes_remaining <= 32'd0;
            end
        end
    end

    // next state logic (combinational)
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    cur_desc_addr = desc_base;
                    next_state = FETCH_DESC;
                end
            end

            FETCH_DESC: begin
                // request descriptor over AXI
                req = 1'b1;
                type = 2'b00; // read
                addr = cur_desc_addr;
                burst_len = 16'd((DESC_WIDTH/8)/ (DATA_WIDTH/8)); // assuming descriptor fits in burstsize
                if (grant && done) begin
                    // in this simplified model, assume data returned in 'cur_desc' externally
                    desc_valid = 1'b1;
                    // parse fields (we assume cur_desc is available)
                    xfer_len = cur_desc[95:64];
                    xfer_addr = cur_desc[63:32];
                    next_desc = cur_desc[31:0];
                    bytes_remaining = cur_desc[95:64];
                    next_state = START_XFER;
                end
            end

            START_XFER: begin
                // start actual data transfer(s)
                // decide read or write based on a flag in descriptor (here using top bits as flag)
                if (xfer_len == 0) begin
                    // nothing to do, go to next descriptor
                    if (next_desc != 0) begin
                        cur_desc_addr = next_desc;
                        next_state = FETCH_DESC;
                    end else begin
                        next_state = COMPLETE;
                    end
                end else begin
                    // for demonstration, assume type=read (0) meaning read from memory -> write to peripheral
                    type = 2'b00;
                    addr = xfer_addr;
                    // compute burst_len in beats: assume simple fixed beat size DATA_WIDTH/8
                    burst_len = (xfer_len + (DATA_WIDTH/8-1)) / (DATA_WIDTH/8);
                    req = 1'b1;
                    if (grant) begin
                        // wait for arbiter to assert done to indicate transfer finished
                        next_state = WAIT_DONE;
                    end
                end
            end

            WAIT_DONE: begin
                // wait for arbiter to report done or error
                if (done) begin
                    // update pointer
                    if (next_desc != 0) begin
                        cur_desc_addr = next_desc;
                        next_state = FETCH_DESC;
                    end else begin
                        next_state = COMPLETE;
                    end
                end else if (error) begin
                    next_state = ERROR;
                end
            end

            COMPLETE: begin
                // report and return IDLE
                next_state = IDLE;
            end

            ERROR: begin
                // keep error status until reset
                next_state = ERROR;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
