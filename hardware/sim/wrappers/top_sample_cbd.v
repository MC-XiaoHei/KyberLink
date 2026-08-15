module top_sample_cbd (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   i,
    output wire         busy,
    output wire         done,
    output wire [767:0] coeffs
);
    wire req, ready, done_w, bv, br, ov, or_w;
    wire [1343:0] bd, od;
    wire [17:0] cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req), .req_ready(ready), .req_done(done_w),
        .req_cfg(cfg),
        .blk_valid(bv), .blk_ready(br), .blk_data(bd),
        .out_valid(ov), .out_ready(or_w), .out_data(od)
    );

    sample_cbd u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .rho(rho), .i(i),
        .busy(busy), .done(done), .coeffs(coeffs),
        .shk_req(req), .shk_cfg(cfg), .shk_ready(ready), .shk_done(done_w),
        .shk_blk_valid(bv), .shk_blk_ready(br), .shk_blk_data(bd),
        .shk_out_valid(ov), .shk_out_ready(or_w), .shk_out_data(od)
    );
endmodule
