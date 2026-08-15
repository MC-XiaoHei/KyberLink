module top_mldsa_verify (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,
    input  wire [15615:0] vk_in,
    input  wire [511:0]   mu_b,
    input  wire [26471:0] sig_in,
    output wire           busy,
    output wire           done,
    output wire           valid_out
);
    wire [2:0]  v_req, v_ready, v_done;
    wire [53:0] v_cfg;
    wire        v_bv, v_br, v_ov, v_or;
    wire [1343:0] v_bd, v_od;

    keccak_engine #(.N_REQ(3)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(v_req), .req_ready(v_ready), .req_done(v_done),
        .req_cfg(v_cfg),
        .blk_valid(v_bv), .blk_ready(v_br), .blk_data(v_bd),
        .out_valid(v_ov), .out_ready(v_or), .out_data(v_od)
    );

    mldsa_verify u_dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .vk_in(vk_in), .mu_b(mu_b), .sig_in(sig_in),
        .busy(busy), .done(done), .valid_out(valid_out),
        .shk_req(v_req), .shk_cfg(v_cfg), .shk_ready(v_ready), .shk_done(v_done),
        .shk_blk_valid(v_bv), .shk_blk_ready(v_br), .shk_blk_data(v_bd),
        .shk_out_valid(v_ov), .shk_out_ready(v_or), .shk_out_data(v_od)
    );
endmodule
