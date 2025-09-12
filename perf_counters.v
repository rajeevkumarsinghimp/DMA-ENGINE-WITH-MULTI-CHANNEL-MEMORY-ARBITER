// perf_counters.v
// Example: per-channel simple completed-transfer counters
module perf_counters #(
    parameter NUM_CH = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [NUM_CH-1:0]      ch_done,
    input  wire [NUM_CH-1:0]      ch_error,
    output reg [31:0]             perf_done [0:NUM_CH-1],
    output reg [31:0]             perf_err  [0:NUM_CH-1]
);
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0;i<NUM_CH;i=i+1) begin
                perf_done[i] <= 32'd0;
                perf_err[i]  <= 32'd0;
            end
        end else begin
            for (i=0;i<NUM_CH;i=i+1) begin
                if (ch_done[i]) perf_done[i] <= perf_done[i] + 1;
                if (ch_error[i]) perf_err[i] <= perf_err[i] + 1;
            end
        end
    end
endmodule
