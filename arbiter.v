// arbiter.v
// Round-robin arbiter that accepts simple transfer requests from multiple channels
// and drives the AXI master interface. For simplicity each request is treated as a
// single AXI burst transaction. The arbiter holds ownership of the AXI until the
// transaction completes (done/asserted).

module arbiter #(
    parameter NUM_CH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // channel side arrays (vectors of signals)
    input  wire [NUM_CH-1:0]            ch_req,
    input  wire [2*NUM_CH-1:0]          ch_type_flat, // flattened types (2 bits per ch)
    input  wire [NUM_CH*ADDR_WIDTH-1:0] ch_addr_flat,
    input  wire [NUM_CH*16-1:0]         ch_burst_len_flat,
    input  wire [NUM_CH*DATA_WIDTH-1:0] ch_wdata_flat,
    input  wire [NUM_CH-1:0]            ch_wlast_flat,
    output reg [NUM_CH-1:0]             ch_grant,
    output reg [NUM_CH-1:0]             ch_done,
    output reg [NUM_CH-1:0]             ch_error,

    // AXI master simplified interface (tie-through)
    output reg [3:0]                    m_axil_awid,
    output reg [ADDR_WIDTH-1:0]         m_axil_awaddr,
    output reg [7:0]                    m_axil_awlen,
    output reg [2:0]                    m_axil_awsize,
    output reg [1:0]                    m_axil_awburst,
    output reg                          m_axil_awvalid,
    input  wire                         m_axil_awready,

    output reg [DATA_WIDTH-1:0]         m_axil_wdata,
    output reg [DATA_WIDTH/8-1:0]       m_axil_wstrb,
    output reg                          m_axil_wlast,
    output reg                          m_axil_wvalid,
    input  wire                         m_axil_wready,

    input  wire [1:0]                   m_axil_bresp,
    input  wire                         m_axil_bvalid,
    output reg                          m_axil_bready,

    output reg [3:0]                    m_axil_arid,
    output reg [ADDR_WIDTH-1:0]         m_axil_araddr,
    output reg [7:0]                    m_axil_arlen,
    output reg [2:0]                    m_axil_arsize,
    output reg [1:0]                    m_axil_arburst,
    output reg                          m_axil_arvalid,
    input  wire                         m_axil_arready,

    input  wire [DATA_WIDTH-1:0]        m_axil_rdata,
    input  wire [1:0]                   m_axil_rresp,
    input  wire                         m_axil_rlast,
    input  wire                         m_axil_rvalid,
    output reg                          m_axil_rready
);

    // internal pointers
    integer idx;
    reg [clog2(NUM_CH)-1:0] ptr; // current RR pointer
    reg [clog2(NUM_CH)-1:0] cur_ch;
    reg busy;

    // helper: extract per-channel fields from flat arrays
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2=0;
            for (i=0; 2**i<value; i=i+1) clog2 = i+1;
        end
    endfunction

    // unpack helpers
    function [1:0] ch_type;
        input integer ch;
        begin
            ch_type = ch_type_flat[(ch*2)+:2];
        end
    endfunction

    function [ADDR_WIDTH-1:0] ch_addr;
        input integer ch;
        begin
            ch_addr = ch_addr_flat[(ch*ADDR_WIDTH)+:ADDR_WIDTH];
        end
    endfunction

    function [15:0] ch_burst_len;
        input integer ch;
        begin
            ch_burst_len = ch_burst_len_flat[(ch*16)+:16];
        end
    endfunction

    function [DATA_WIDTH-1:0] ch_wdata;
        input integer ch;
        begin
            ch_wdata = ch_wdata_flat[(ch*DATA_WIDTH)+:DATA_WIDTH];
        end
    endfunction

    function ch_wlast_f;
        input integer ch;
        begin
            ch_wlast_f = ch_wlast_flat[ch];
        end
    endfunction

    // state machine: simple stepwise arbitration
    localparam S_IDLE = 0;
    localparam S_REQ  = 1;
    localparam S_XFER = 2;
    localparam S_WAIT_RESP = 3;
    reg [1:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            ptr <= 0;
            busy <= 1'b0;
            m_axil_awvalid <= 1'b0;
            m_axil_wvalid <= 1'b0;
            m_axil_arvalid <= 1'b0;
            m_axil_rready <= 1'b0;
            m_axil_bready <= 1'b0;
            for (idx=0; idx<NUM_CH; idx=idx+1) begin
                ch_grant[idx] <= 1'b0;
                ch_done[idx] <= 1'b0;
                ch_error[idx] <= 1'b0;
            end
        end else begin
            state <= next_state;
            // clear done/error pulses
            for (idx=0; idx<NUM_CH; idx=idx+1) begin
                ch_done[idx] <= 1'b0;
                ch_error[idx] <= 1'b0;
            end
        end
    end

    // combinational next-state and outputs
    always @(*) begin
        next_state = state;
        // default idle outputs
        m_axil_awvalid = 1'b0;
        m_axil_wvalid  = 1'b0;
        m_axil_arvalid = 1'b0;
        m_axil_bready  = 1'b0;
        m_axil_rready  = 1'b0;
        for (idx=0; idx<NUM_CH; idx=idx+1) ch_grant[idx] = 1'b0;

        case (state)
            S_IDLE: begin
                // round-robin pick next request
                for (idx=0; idx<NUM_CH; idx=idx+1) begin
                    integer c = (ptr + idx) % NUM_CH;
                    if (ch_req[c]) begin
                        cur_ch = c[clog2(NUM_CH)-1:0];
                        next_state = S_REQ;
                        disable for;
                    end
                end
            end

            S_REQ: begin
                // grant to selected channel and start AXI transaction based on type
                ch_grant[cur_ch] = 1'b1;
                // decode fields
                if (ch_type(cur_ch) == 2'b00) begin
                    // read: issue AR
                    m_axil_araddr = ch_addr(cur_ch);
                    m_axil_arlen  = ch_burst_len(cur_ch) - 1;
                    m_axil_arsize = clog2(DATA_WIDTH/8);
                    m_axil_arburst= 2'b01; // INCR
                    m_axil_arvalid= 1'b1;
                    if (m_axil_arready) begin
                        next_state = S_XFER;
                        m_axil_rready = 1'b1;
                    end
                end else begin
                    // write: issue AW + W beats
                    m_axil_awaddr = ch_addr(cur_ch);
                    m_axil_awlen  = ch_burst_len(cur_ch) - 1;
                    m_axil_awsize = clog2(DATA_WIDTH/8);
                    m_axil_awburst= 2'b01;
                    m_axil_awvalid= 1'b1;
                    if (m_axil_awready) begin
                        // feed write data in this cycle (simplified)
                        m_axil_wdata = ch_wdata(cur_ch);
                        m_axil_wstrb = {DATA_WIDTH/8{1'b1}};
                        m_axil_wlast = ch_wlast_flat[cur_ch];
                        m_axil_wvalid = 1'b1;
                        if (m_axil_wready) begin
                            next_state = S_WAIT_RESP;
                            m_axil_bready = 1'b1;
                        end
                    end
                end
            end

            S_XFER: begin
                // handle read data until last beat then signal done
                m_axil_rready = 1'b1;
                if (m_axil_rvalid && m_axil_rlast) begin
                    ch_done[cur_ch] = 1'b1;
                    ptr = cur_ch + 1;
                    next_state = S_IDLE;
                end
            end

            S_WAIT_RESP: begin
                // wait for write response
                m_axil_bready = 1'b1;
                if (m_axil_bvalid) begin
                    if (m_axil_bresp == 2'b00) begin
                        ch_done[cur_ch] = 1'b1;
                    end else begin
                        ch_error[cur_ch] = 1'b1;
                    end
                    ptr = cur_ch + 1;
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
