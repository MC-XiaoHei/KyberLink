module basemul_core (
    input wire [11:0] a0,
    input wire [11:0] a1,
    input wire [11:0] b0,
    input wire [11:0] b1,
    input wire [11:0] gamma,
    output wire [11:0] c0,
    output wire [11:0] c1
);
    localparam Q = 13'd3329;

    function [11:0] barrett;
        input [23:0] x;
        reg [38:0] m39;
        reg [25:0] r2;
        reg [25:0] r3;
        begin
            m39 = {15'd0, x} * 15'd20158;
            r2 = {2'b0, x} - {13'd0, m39[38:26]} * {13'd0, Q};
            r3 = (r2 >= {13'd0, Q}) ? r2 - {13'd0, Q} : r2;
            barrett = r3[11:0];
        end
    endfunction

    wire [11:0] t0 = barrett({12'd0, a0} * {12'd0, b0});
    wire [11:0] t1 = barrett({12'd0, a1} * {12'd0, b1});
    wire [11:0] t1g = barrett({12'd0, t1} * {12'd0, gamma});
    wire [11:0] t2 = barrett({12'd0, a0} * {12'd0, b1});
    wire [11:0] t3 = barrett({12'd0, a1} * {12'd0, b0});

    wire [12:0] c0s = {1'b0, t0} + {1'b0, t1g};
    wire [12:0] c1s = {1'b0, t2} + {1'b0, t3};
    wire [12:0] c0r = (c0s >= Q) ? c0s - Q : c0s;
    wire [12:0] c1r = (c1s >= Q) ? c1s - Q : c1s;
    assign c0 = c0r[11:0];
    assign c1 = c1r[11:0];
endmodule
