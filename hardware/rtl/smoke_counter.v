module smoke_counter #(parameter W = 8) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       incr,
    output reg  [W-1:0] count
);
    always @(posedge clk) begin
        if (!rst_n)
            count <= 0;
        else if (incr)
            count <= count + 1;
    end
endmodule
