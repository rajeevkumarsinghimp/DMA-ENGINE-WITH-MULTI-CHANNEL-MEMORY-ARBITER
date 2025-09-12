// dma_reg_if.v
// Minimal AXI4-Lite slave to control channels: start, desc_base, reset and read status
// For simplicity this is a very small register file addressing model: base offset per channel.

module dma_reg_if #(
    parameter NUM_CH = 4,
    parameter ADDR_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    // AXI-lite slave (simple)
    input  wire [31:0]              s_axi_awaddr,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    input  wire [31:0]              s_axi_wdata,
    input  wire [3:0]               s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    output reg [1:0]                s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    input  wire [31:0]              s_axi_araddr,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    output reg [31:0]               s_axi_rdata,
    output reg [1:0]                s_axi_rresp,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // per-channel control/status outputs
    output reg                      ch_start [0:NUM_CH-1],
    output reg [ADDR_WIDTH-1:0]     ch_desc_base [0:NUM_CH-1],
    output reg                      ch_reset [0:NUM_CH-1],
    input  wire [31:0]              ch_status [0:NUM_CH-1],

    // IRQ status input (capture)
    input  wire [NUM_CH-1:0]        irq_src
);

    // Simple register map (word addressed):
    // 0x000: global control
    // 0x100 + ch*0x10 + 0x0 : CH_CTRL (bit0=start, bit1=reset)
    // 0x100 + ch*0x10 + 0x4 : CH_DESC_BASE (32-bit)
    // 0x100 + ch*0x10 + 0x8 : CH_STATUS (read-only)
    // 0x200: IRQ status (NUM_CH bits)

    // write channel
    reg [31:0] addr_reg;
    reg aw_seen, w_seen, ar_seen;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            for (i=0;i<NUM_CH;i=i+1) begin
                ch_start[i] <= 1'b0;
                ch_desc_base[i] <= {ADDR_WIDTH{1'b0}};
                ch_reset[i] <= 1'b0;
            end
        end else begin
            // write address handshake
            if (!s_axi_awready && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
                addr_reg <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
            end

            // write data handshake
            if (!s_axi_wready && s_axi_wvalid) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            // completion response on successful write
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid) begin
                // decode address and write
                if (addr_reg >= 32'h100 && addr_reg < 32'h100 + NUM_CH*16) begin
                    integer ch;
                    ch = (addr_reg - 32'h100) / 16;
                    integer off;
                    off = (addr_reg - 32'h100) % 16;
                    if (off == 0) begin
                        // CH_CTRL
                        ch_start[ch] <= s_axi_wdata[0];
                        ch_reset[ch] <= s_axi_wdata[1];
                    end else if (off == 4) begin
                        ch_desc_base[ch] <= s_axi_wdata;
                    end
                end else if (addr_reg == 32'h200) begin
                    // clear IRQ status by writing 1s to bits
                    // Not implemented here (system could capture IRQ separately)
                end
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // read address handshake
            if (!s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                addr_reg <= s_axi_araddr;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // produce read data
            if (s_axi_arready && s_axi_arvalid) begin
                // decode
                if (addr_reg >= 32'h100 && addr_reg < 32'h100 + NUM_CH*16) begin
                    integer ch;
                    ch = (addr_reg - 32'h100) / 16;
                    integer off;
                    off = (addr_reg - 32'h100) % 16;
                    if (off == 0) begin
                        s_axi_rdata <= {30'd0, ch_reset[ch], ch_start[ch]};
                    end else if (off == 4) begin
                        s_axi_rdata <= ch_desc_base[ch];
                    end else if (off == 8) begin
                        s_axi_rdata <= ch_status[ch];
                    end else s_axi_rdata <= 32'd0;
                end else if (addr_reg == 32'h200) begin
                    s_axi_rdata <= {{(32-NUM_CH){1'b0}}, irq_src};
                end else begin
                    s_axi_rdata <= 32'd0;
                end
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
