module top_rej_bounded (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] rho,
    input  wire [15:0]  idx_in,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [5887:0] coeffs
);
    wire rb_req, rb_ready, rb_done, rb_bv, rb_br, rb_ov, rb_or;
    wire [1343:0] rb_bd, rb_od;
    wire [17:0] rb_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(rb_req), .req_ready(rb_ready), .req_done(rb_done),
        .req_cfg(rb_cfg),
        .blk_valid(rb_bv), .blk_ready(rb_br), .blk_data(rb_bd),
        .out_valid(rb_ov), .out_ready(rb_or), .out_data(rb_od)
    );

    rej_bounded u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .rho(rho), .idx_in(idx_in),
        .busy(busy), .done(done), .error(error), .coeffs(coeffs),
        .shk_req(rb_req), .shk_cfg(rb_cfg), .shk_ready(rb_ready), .shk_done(rb_done),
        .shk_blk_valid(rb_bv), .shk_blk_ready(rb_br), .shk_blk_data(rb_bd),
        .shk_out_valid(rb_ov), .shk_out_ready(rb_or), .shk_out_data(rb_od)
    );
endmodule
