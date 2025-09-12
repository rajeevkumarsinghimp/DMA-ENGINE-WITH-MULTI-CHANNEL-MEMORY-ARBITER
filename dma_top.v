// dma_top.v
// Top-level DMA Engine with multi-channel arbiter and AXI master
// Parameters: NUM_CH channels (each can do descriptor-driven scatter-gather transfers)

module dma_top #(
    parameter NUM_CH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,       // master data width (in bits)
    parameter DESC_WIDTH = 128       // descriptor width in bits (a descriptor may contain addr/len/flags)
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // System AXI4-Lite for control/status (connect to dma_reg_if)
    // AXI4-Lite slave interface (common simple subset)
    input  wire [31:0]              s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    output wire [1:0]               s_axi_bresp,
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,
    input  wire [31:0]              s_axi_araddr,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,
    output wire [31:0]              s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,

    // External interrupt line (to CPU)
    output wire                     irq,

    // AXI4 master interface (to system memory)
    // AW
    output wire [3:0]               m_axil_awid,   // optional, tied zero if unused
    output wire [ADDR_WIDTH-1:0]    m_axil_awaddr,
    output wire [7:0]               m_axil_awlen,
    output wire [2:0]               m_axil_awsize,
    output wire [1:0]               m_axil_awburst,
    output wire                     m_axil_awvalid,
    input  wire                     m_axil_awready,
    // W
    output wire [DATA_WIDTH-1:0]    m_axil_wdata,
    output wire [DATA_WIDTH/8-1:0]  m_axil_wstrb,
    output wire                     m_axil_wlast,
    output wire                     m_axil_wvalid,
    input  wire                     m_axil_wready,
    // B
    input  wire [1:0]               m_axil_bresp,
    input  wire                     m_axil_bvalid,
    output wire                     m_axil_bready,
    // AR
    output wire [3:0]               m_axil_arid,
    output wire [ADDR_WIDTH-1:0]    m_axil_araddr,
    output wire [7:0]               m_axil_arlen,
    output wire [2:0]               m_axil_arsize,
    output wire [1:0]               m_axil_arburst,
    output wire                     m_axil_arvalid,
    input  wire                     m_axil_arready,
    // R
    input  wire [DATA_WIDTH-1:0]    m_axil_rdata,
    input  wire [1:0]               m_axil_rresp,
    input  wire                     m_axil_rlast,
    input  wire                     m_axil_rvalid,
    output wire                     m_axil_rready
);

    // Internal buses and wires
    // Control/status reg interface
    wire                          reg_start_ch [0:NUM_CH-1];
    wire [ADDR_WIDTH-1:0]         reg_desc_base [0:NUM_CH-1];
    wire                          reg_reset_ch [0:NUM_CH-1];
    wire [31:0]                   reg_status [0:NUM_CH-1];

    // Channel -> Arbiter request signals
    wire                          ch_req     [0:NUM_CH-1];
    wire [1:0]                    ch_type    [0:NUM_CH-1]; // 0: read,1:write
    wire [ADDR_WIDTH-1:0]         ch_addr    [0:NUM_CH-1];
    wire [15:0]                   ch_burst_len [0:NUM_CH-1];
    wire [DATA_WIDTH-1:0]         ch_wdata   [0:NUM_CH-1];
    wire                          ch_wlast   [0:NUM_CH-1];
    wire                          ch_grant   [0:NUM_CH-1];
    wire                          ch_done    [0:NUM_CH-1];
    wire                          ch_error   [0:NUM_CH-1];

    // Interrupt lines and perf counters
    wire [NUM_CH-1:0]             irq_req;
    wire [NUM_CH-1:0]             done_vec;
    wire [NUM_CH-1:0]             err_vec;

    genvar i;
    generate
        for (i=0; i<NUM_CH; i=i+1) begin : CH_GEN
            // instantiate per-channel DMA engine
            dma_channel #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .DESC_WIDTH(DESC_WIDTH)
            ) u_dma_channel (
                .clk           (clk),
                .rst_n         (rst_n),

                .start         (reg_start_ch[i]),
                .desc_base     (reg_desc_base[i]),
                .reset_ch      (reg_reset_ch[i]),

                // arbitration request interface
                .req           (ch_req[i]),
                .type          (ch_type[i]),
                .addr          (ch_addr[i]),
                .burst_len     (ch_burst_len[i]),
                .wdata         (ch_wdata[i]),
                .wlast         (ch_wlast[i]),
                .grant         (ch_grant[i]),
                .done          (ch_done[i]),
                .error         (ch_error[i]),

                // status
                .status_out    (reg_status[i]),

                // perf counters
                .irq_out       (irq_req[i])
            );
        end
    endgenerate

    // Arbiter: connects channel requests to the single AXI master
    arbiter #(
        .NUM_CH(NUM_CH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_arbiter (
        .clk(clk),
        .rst_n(rst_n),

        // channel side
        .ch_req(ch_req),
        .ch_type(ch_type),
        .ch_addr(ch_addr),
        .ch_burst_len(ch_burst_len),
        .ch_wdata(ch_wdata),
        .ch_wlast(ch_wlast),
        .ch_grant(ch_grant),
        .ch_done(ch_done),
        .ch_error(ch_error),

        // AXI master side (connect directly to top-level AXI)
        .m_axil_awid(m_axil_awid),
        .m_axil_awaddr(m_axil_awaddr),
        .m_axil_awlen(m_axil_awlen),
        .m_axil_awsize(m_axil_awsize),
        .m_axil_awburst(m_axil_awburst),
        .m_axil_awvalid(m_axil_awvalid),
        .m_axil_awready(m_axil_awready),

        .m_axil_wdata(m_axil_wdata),
        .m_axil_wstrb(m_axil_wstrb),
        .m_axil_wlast(m_axil_wlast),
        .m_axil_wvalid(m_axil_wvalid),
        .m_axil_wready(m_axil_wready),

        .m_axil_bresp(m_axil_bresp),
        .m_axil_bvalid(m_axil_bvalid),
        .m_axil_bready(m_axil_bready),

        .m_axil_arid(m_axil_arid),
        .m_axil_araddr(m_axil_araddr),
        .m_axil_arlen(m_axil_arlen),
        .m_axil_arsize(m_axil_arsize),
        .m_axil_arburst(m_axil_arburst),
        .m_axil_arvalid(m_axil_arvalid),
        .m_axil_arready(m_axil_arready),

        .m_axil_rdata(m_axil_rdata),
        .m_axil_rresp(m_axil_rresp),
        .m_axil_rlast(m_axil_rlast),
        .m_axil_rvalid(m_axil_rvalid),
        .m_axil_rready(m_axil_rready)
    );

    // Registers and control via AXI-lite
    dma_reg_if #(
        .NUM_CH(NUM_CH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_reg_if (
        .clk(clk),
        .rst_n(rst_n),
        // AXI-lite slave
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // per-channel control/status
        .ch_start(reg_start_ch),
        .ch_desc_base(reg_desc_base),
        .ch_reset(reg_reset_ch),
        .ch_status(reg_status),

        // interrupt status capture
        .irq_src(irq_req)
    );

    // Interrupt controller
    interrupt_ctrl #(
        .NUM_CH(NUM_CH)
    ) u_irq (
        .clk(clk),
        .rst_n(rst_n),
        .irq_in(irq_req),
        .irq_out(irq)
    );

    // perf counters aggregate
    // (For brevity placing a simple parallel-perf counter could be added here)

endmodule
