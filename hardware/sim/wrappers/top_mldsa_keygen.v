module top_mldsa_keygen (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  seed,
    output wire          busy,
    output wire          done,
    output wire [15615:0] vk_out,
    output wire [32255:0] sk_out
);
    wire [3:0]    kg_req, kg_ready, kg_done;
    wire [71:0]   kg_cfg;
    wire          kg_bv, kg_br, kg_ov, kg_or;
    wire [1343:0] kg_bd, kg_od;

    keccak_engine #(.N_REQ(4)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(kg_req), .req_ready(kg_ready), .req_done(kg_done),
        .req_cfg(kg_cfg),
        .blk_valid(kg_bv), .blk_ready(kg_br), .blk_data(kg_bd),
        .out_valid(kg_ov), .out_ready(kg_or), .out_data(kg_od)
    );

    mldsa_keygen u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .seed(seed),
        .busy(busy), .done(done), .vk_out(vk_out), .sk_out(sk_out),
        .shk_req(kg_req), .shk_cfg(kg_cfg),
        .shk_ready(kg_ready), .shk_done(kg_done),
        .shk_blk_valid(kg_bv), .shk_blk_ready(kg_br), .shk_blk_data(kg_bd),
        .shk_out_valid(kg_ov), .shk_out_ready(kg_or), .shk_out_data(kg_od)
    );
endmodule
