module top_mldsa_sign (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [32255:0] sk_in,
    input  wire [511:0]  mu_b,
    input  wire [255:0]  rnd_in,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [26471:0] sig_out
);
    wire [3:0] s_req, s_ready, s_done;
    wire [71:0] s_cfg;
    wire s_bv, s_br, s_ov, s_or;
    wire [1343:0] s_bd, s_od;

    keccak_engine #(.N_REQ(4)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(s_req), .req_ready(s_ready), .req_done(s_done),
        .req_cfg(s_cfg),
        .blk_valid(s_bv), .blk_ready(s_br), .blk_data(s_bd),
        .out_valid(s_ov), .out_ready(s_or), .out_data(s_od)
    );

    mldsa_sign u_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .sk_in(sk_in), .mu_b(mu_b), .rnd_in(rnd_in),
        .busy(busy), .done(done), .error(error), .sig_out(sig_out),
        .shk_req(s_req), .shk_cfg(s_cfg), .shk_ready(s_ready), .shk_done(s_done),
        .shk_blk_valid(s_bv), .shk_blk_ready(s_br), .shk_blk_data(s_bd),
        .shk_out_valid(s_ov), .shk_out_ready(s_or), .shk_out_data(s_od)
    );
endmodule
