// pulse_sync.v
module pulse_sync (
    input  wire clk_dst,
    input  wire rst_n,
    input  wire pulse_in,
    output reg  pulse_out
);
    reg sync1, sync2;
    reg flag;

    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            flag  <= 1'b0;
            pulse_out <= 1'b0;
        end else begin
            sync1 <= pulse_in;
            sync2 <= sync1;
            if (sync2 & ~flag) begin
                pulse_out <= 1'b1;
                flag <= 1'b1;
            end else begin
                pulse_out <= 1'b0;
            end
            if (!sync2) flag <= 1'b0;
        end
    end
endmodule
