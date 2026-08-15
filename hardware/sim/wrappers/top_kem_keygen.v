module top_kem_keygen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [255:0] d,
    input  wire [255:0] z,
    output wire        busy,
    output wire        done,
    output wire [9471:0]  ek_out,
    output wire [19199:0] dk_out
);
    wire [3:0] rv, rr, rd;
    wire [71:0] cfg;
    wire bv, br, ov, orr;
    wire [1343:0] bd, od;

    keccak_engine #(.N_REQ(4)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(rv), .req_ready(rr), .req_done(rd),
        .req_cfg(cfg),
        .blk_valid(bv), .blk_ready(br), .blk_data(bd),
        .out_valid(ov), .out_ready(orr), .out_data(od)
    );

    kem_keygen u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .d(d), .z(z),
        .busy(busy), .done(done), .ek_out(ek_out), .dk_out(dk_out),
        .shk_req(rv), .shk_cfg(cfg), .shk_ready(rr), .shk_done(rd),
        .shk_blk_valid(bv), .shk_blk_ready(br), .shk_blk_data(bd),
        .shk_out_valid(ov), .shk_out_ready(orr), .shk_out_data(od)
    );
endmodule
