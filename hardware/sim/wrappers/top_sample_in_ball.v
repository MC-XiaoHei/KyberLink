module top_sample_in_ball (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [383:0] ctilde,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [5887:0] coeffs
);
    wire sib_req, sib_ready, sib_done, sib_bv, sib_br, sib_ov, sib_or;
    wire [1343:0] sib_bd, sib_od;
    wire [17:0] sib_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(sib_req), .req_ready(sib_ready), .req_done(sib_done),
        .req_cfg(sib_cfg),
        .blk_valid(sib_bv), .blk_ready(sib_br), .blk_data(sib_bd),
        .out_valid(sib_ov), .out_ready(sib_or), .out_data(sib_od)
    );

    sample_in_ball u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .ctilde(ctilde),
        .busy(busy), .done(done), .error(error), .coeffs(coeffs),
        .shk_req(sib_req), .shk_cfg(sib_cfg), .shk_ready(sib_ready), .shk_done(sib_done),
        .shk_blk_valid(sib_bv), .shk_blk_ready(sib_br), .shk_blk_data(sib_bd),
        .shk_out_valid(sib_ov), .shk_out_ready(sib_or), .shk_out_data(sib_od)
    );
endmodule
