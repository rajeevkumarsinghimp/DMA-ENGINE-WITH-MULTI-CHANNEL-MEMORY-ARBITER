// interrupt_ctrl.v
// Simple OR-tree of channel interrupts -> single IRQ line (edge-detected)
module interrupt_ctrl #(
    parameter NUM_CH = 4
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [NUM_CH-1:0]   irq_in,
    output reg                 irq_out
);
    reg [NUM_CH-1:0] irq_sync1, irq_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_sync1 <= {NUM_CH{1'b0}};
            irq_sync2 <= {NUM_CH{1'b0}};
            irq_out <= 1'b0;
        end else begin
            irq_sync1 <= irq_in;
            irq_sync2 <= irq_sync1;
            irq_out <= |irq_sync2;
        end
    end
endmodule
