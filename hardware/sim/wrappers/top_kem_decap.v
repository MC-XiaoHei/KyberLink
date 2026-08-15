module top_kem_decap (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [19199:0] dk_in,
    input  wire [8703:0]  c_in,
    output wire         busy,
    output wire         done,
    output wire [255:0] k_out
);
    wire [3:0] k_req;
    wire [3:0] k_ready;
    wire [3:0] k_done;
    wire [71:0] k_cfg;
    wire k_bv;
    wire k_br;
    wire [1343:0] k_bd;
    wire k_ov;
    wire k_or;
    wire [1343:0] k_od;

    keccak_engine #(.N_REQ(4)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(k_req), .req_ready(k_ready), .req_done(k_done),
        .req_cfg(k_cfg),
        .blk_valid(k_bv), .blk_ready(k_br), .blk_data(k_bd),
        .out_valid(k_ov), .out_ready(k_or), .out_data(k_od)
    );

    kem_decap u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .dk_in(dk_in), .c_in(c_in),
        .busy(busy), .done(done), .k_out(k_out),
        .shk_req(k_req), .shk_cfg(k_cfg),
        .shk_ready(k_ready), .shk_done(k_done),
        .shk_blk_valid(k_bv), .shk_blk_ready(k_br), .shk_blk_data(k_bd),
        .shk_out_valid(k_ov), .shk_out_ready(k_or), .shk_out_data(k_od)
    );
endmodule
