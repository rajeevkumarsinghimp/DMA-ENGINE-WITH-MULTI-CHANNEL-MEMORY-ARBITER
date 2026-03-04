`timescale 1ns/1ps

module tb_dma_top;

parameter NUM_CH     = 4;
parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 64;

reg clk;
reg rst_n;

/* AXI Lite signals */
reg  [31:0] s_axi_awaddr;
reg  s_axi_awvalid;
wire s_axi_awready;

reg  [31:0] s_axi_wdata;
reg  [3:0]  s_axi_wstrb;
reg  s_axi_wvalid;
wire s_axi_wready;

wire [1:0] s_axi_bresp;
wire s_axi_bvalid;
reg  s_axi_bready;

reg  [31:0] s_axi_araddr;
reg  s_axi_arvalid;
wire s_axi_arready;

wire [31:0] s_axi_rdata;
wire [1:0]  s_axi_rresp;
wire s_axi_rvalid;
reg  s_axi_rready;

/* AXI MASTER MEMORY SIDE */

wire [ADDR_WIDTH-1:0] m_axil_awaddr;
wire m_axil_awvalid;
reg  m_axil_awready;

wire [DATA_WIDTH-1:0] m_axil_wdata;
wire m_axil_wvalid;
reg  m_axil_wready;
wire m_axil_wlast;

reg  [1:0] m_axil_bresp;
reg  m_axil_bvalid;
wire m_axil_bready;

wire [ADDR_WIDTH-1:0] m_axil_araddr;
wire m_axil_arvalid;
reg  m_axil_arready;

reg [DATA_WIDTH-1:0] m_axil_rdata;
reg m_axil_rvalid;
reg m_axil_rlast;
wire m_axil_rready;

wire irq;


/* DUT */

dma_top #(
.NUM_CH(NUM_CH),
.ADDR_WIDTH(ADDR_WIDTH),
.DATA_WIDTH(DATA_WIDTH)
) dut (

.clk(clk),
.rst_n(rst_n),

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

.irq(irq),

.m_axil_awaddr(m_axil_awaddr),
.m_axil_awvalid(m_axil_awvalid),
.m_axil_awready(m_axil_awready),

.m_axil_wdata(m_axil_wdata),
.m_axil_wvalid(m_axil_wvalid),
.m_axil_wready(m_axil_wready),
.m_axil_wlast(m_axil_wlast),

.m_axil_bresp(m_axil_bresp),
.m_axil_bvalid(m_axil_bvalid),
.m_axil_bready(m_axil_bready),

.m_axil_araddr(m_axil_araddr),
.m_axil_arvalid(m_axil_arvalid),
.m_axil_arready(m_axil_arready),

.m_axil_rdata(m_axil_rdata),
.m_axil_rvalid(m_axil_rvalid),
.m_axil_rlast(m_axil_rlast),
.m_axil_rready(m_axil_rready)
);



/* CLOCK */

initial begin
clk = 0;
forever #5 clk = ~clk;
end



/* RESET */

initial begin
rst_n = 0;
#100;
rst_n = 1;
end



/* SIMPLE AXI MEMORY MODEL */

always @(posedge clk) begin

/* read address accepted */
if(m_axil_arvalid) begin
m_axil_arready <= 1;
end else
m_axil_arready <= 0;


/* read data */
if(m_axil_arvalid) begin
m_axil_rvalid <= 1;
m_axil_rlast  <= 1;
m_axil_rdata  <= 64'hDEADBEEFCAFEBABE;
end
else begin
m_axil_rvalid <= 0;
m_axil_rlast  <= 0;
end


/* write channel */
if(m_axil_awvalid)
m_axil_awready <= 1;
else
m_axil_awready <= 0;

if(m_axil_wvalid)
m_axil_wready <= 1;
else
m_axil_wready <= 0;


/* write response */
if(m_axil_wvalid) begin
m_axil_bvalid <= 1;
m_axil_bresp  <= 2'b00;
end
else
m_axil_bvalid <= 0;

end



/* AXI LITE WRITE TASK */

task axi_write;
input [31:0] addr;
input [31:0] data;

begin

@(posedge clk);
s_axi_awaddr  <= addr;
s_axi_awvalid <= 1;

s_axi_wdata  <= data;
s_axi_wvalid <= 1;

wait(s_axi_awready);
wait(s_axi_wready);

@(posedge clk);

s_axi_awvalid <= 0;
s_axi_wvalid  <= 0;

s_axi_bready <= 1;
wait(s_axi_bvalid);

@(posedge clk);
s_axi_bready <= 0;

end
endtask



/* TEST SEQUENCE */

initial begin

s_axi_awvalid = 0;
s_axi_wvalid  = 0;
s_axi_arvalid = 0;

m_axil_awready = 0;
m_axil_wready  = 0;
m_axil_arready = 0;

m_axil_bvalid  = 0;

wait(rst_n);

#50;


/* configure channel 0 descriptor */
axi_write(32'h100 + 4, 32'h00001000);

/* start channel 0 */
axi_write(32'h100, 32'h1);


/* configure channel 1 descriptor */
axi_write(32'h110 + 4, 32'h00002000);

/* start channel 1 */
axi_write(32'h110, 32'h1);


/* wait transfers */

#5000;

$display("DMA test complete");

$finish;

end

endmodule
