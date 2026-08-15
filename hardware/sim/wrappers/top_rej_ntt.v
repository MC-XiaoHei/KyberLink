module top_rej_ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   s,
    input  wire [7:0]   r,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [5887:0] coeffs
);
    wire rej_req, rej_ready, rej_done, rej_bv, rej_br, rej_ov, rej_or;
    wire [1343:0] rej_bd, rej_od;
    wire [17:0] rej_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(rej_req), .req_ready(rej_ready), .req_done(rej_done),
        .req_cfg(rej_cfg),
        .blk_valid(rej_bv), .blk_ready(rej_br), .blk_data(rej_bd),
        .out_valid(rej_ov), .out_ready(rej_or), .out_data(rej_od)
    );

    rej_ntt u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .rho(rho), .s(s), .r(r),
        .busy(busy), .done(done), .error(error), .coeffs(coeffs),
        .shk_req(rej_req), .shk_cfg(rej_cfg), .shk_ready(rej_ready), .shk_done(rej_done),
        .shk_blk_valid(rej_bv), .shk_blk_ready(rej_br), .shk_blk_data(rej_bd),
        .shk_out_valid(rej_ov), .shk_out_ready(rej_or), .shk_out_data(rej_od)
    );
endmodule
