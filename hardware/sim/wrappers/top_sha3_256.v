module top_sha3_256 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [11:0]  len,
    input  wire         msg_wr,
    input  wire [11:0]  msg_waddr,
    input  wire [7:0]   msg_wdata,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [255:0] digest
);
    wire shk_req, shk_ready, shk_done, shk_bv, shk_br, shk_ov, shk_or;
    wire [1343:0] shk_bd, shk_od;
    wire [17:0] shk_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(shk_req), .req_ready(shk_ready), .req_done(shk_done),
        .req_cfg(shk_cfg),
        .blk_valid(shk_bv), .blk_ready(shk_br), .blk_data(shk_bd),
        .out_valid(shk_ov), .out_ready(shk_or), .out_data(shk_od)
    );

    sha3_256 u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .len(len),
        .msg_wr(msg_wr), .msg_waddr(msg_waddr), .msg_wdata(msg_wdata),
        .busy(busy), .done(done), .error(error), .digest(digest),
        .shk_req(shk_req), .shk_cfg(shk_cfg), .shk_ready(shk_ready), .shk_done(shk_done),
        .shk_blk_valid(shk_bv), .shk_blk_ready(shk_br), .shk_blk_data(shk_bd),
        .shk_out_valid(shk_ov), .shk_out_ready(shk_or), .shk_out_data(shk_od)
    );
endmodule
