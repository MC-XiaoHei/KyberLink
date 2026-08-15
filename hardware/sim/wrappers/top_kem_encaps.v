module top_kem_encaps (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [9471:0] ek_in,
    input  wire [255:0]  m,
    output wire          busy,
    output wire          done,
    output wire [255:0]  k_out,
    output wire [8703:0] c_out
);
    wire [3:0] shk_req, shk_ready, shk_done;
    wire [71:0] shk_cfg;
    wire shk_bv, shk_br, shk_ov, shk_or;
    wire [1343:0] shk_bd, shk_od;

    keccak_engine #(.N_REQ(4)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(shk_req), .req_ready(shk_ready), .req_done(shk_done),
        .req_cfg(shk_cfg),
        .blk_valid(shk_bv), .blk_ready(shk_br), .blk_data(shk_bd),
        .out_valid(shk_ov), .out_ready(shk_or), .out_data(shk_od)
    );

    kem_encaps u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .ek_in(ek_in), .m(m),
        .busy(busy), .done(done), .k_out(k_out), .c_out(c_out),
        .shk_req(shk_req), .shk_cfg(shk_cfg), .shk_ready(shk_ready), .shk_done(shk_done),
        .shk_blk_valid(shk_bv), .shk_blk_ready(shk_br), .shk_blk_data(shk_bd),
        .shk_out_valid(shk_ov), .shk_out_ready(shk_or), .shk_out_data(shk_od)
    );
endmodule
