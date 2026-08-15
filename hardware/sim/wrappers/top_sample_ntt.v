module top_sample_ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   i,
    input  wire [7:0]   j,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [3071:0] coeffs
);
    wire sntt_req, sntt_ready, sntt_done, sntt_bv, sntt_br, sntt_ov, sntt_or;
    wire [1343:0] sntt_bd, sntt_od;
    wire [17:0] sntt_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(sntt_req), .req_ready(sntt_ready), .req_done(sntt_done),
        .req_cfg(sntt_cfg),
        .blk_valid(sntt_bv), .blk_ready(sntt_br), .blk_data(sntt_bd),
        .out_valid(sntt_ov), .out_ready(sntt_or), .out_data(sntt_od)
    );

    sample_ntt u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .rho(rho), .i(i), .j(j),
        .busy(busy), .done(done), .error(error), .coeffs(coeffs),
        .shk_req(sntt_req), .shk_cfg(sntt_cfg), .shk_ready(sntt_ready), .shk_done(sntt_done),
        .shk_blk_valid(sntt_bv), .shk_blk_ready(sntt_br), .shk_blk_data(sntt_bd),
        .shk_out_valid(sntt_ov), .shk_out_ready(sntt_or), .shk_out_data(sntt_od)
    );
endmodule
