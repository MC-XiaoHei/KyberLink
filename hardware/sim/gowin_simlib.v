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
    reg q0 = INIT, q1 = INIT;
    always @(posedge CLK or posedge CLEAR) begin
        if (CLEAR)
            q0 <= INIT;
        else if (TX) begin
            q0 <= D0;
            q1 <= D1;
        end
    end
    assign Q0 = q0;
    assign Q1 = q1;
endmodule
