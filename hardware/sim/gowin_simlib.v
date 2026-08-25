module ODDRC #(
    parameter INIT = 1'b0
) (
    output wire Q0,
    output wire Q1,
    input  wire D0,
    input  wire D1,
    input  wire TX,
    input  wire CLK,
    input  wire CLEAR
);
    reg d0_reg = INIT, d1_reg = INIT;
    reg q1 = INIT;
    always @(posedge CLK or posedge CLEAR) begin
        if (CLEAR) begin
            d0_reg <= INIT;
            q1 <= INIT;
        end else if (TX) begin
            d0_reg <= D0;
            q1 <= D1;
        end
    end
    always @(negedge CLK or posedge CLEAR) begin
        if (CLEAR)
            d1_reg <= INIT;
        else if (TX)
            d1_reg <= D1;
    end
    assign Q0 = CLK ? d0_reg : d1_reg;
    assign Q1 = q1;
endmodule
