module top_hkdf_sha3_256 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] h4_in,
    input  wire [255:0] ss_i_in,
    input  wire [255:0] ss_r_in,
    input  wire [31:0]  spi_i_in,
    input  wire [31:0]  spi_r_in,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [767:0] okm
);
    wire h_req, h_ready, h_done, h_bv, h_br, h_ov, h_or;
    wire [1343:0] h_bd, h_od;
    wire [17:0] h_cfg;

    keccak_engine #(.N_REQ(1)) u_eng (
        .clk(clk), .rst_n(rst_n),
        .req_valid(h_req), .req_ready(h_ready), .req_done(h_done),
        .req_cfg(h_cfg),
        .blk_valid(h_bv), .blk_ready(h_br), .blk_data(h_bd),
        .out_valid(h_ov), .out_ready(h_or), .out_data(h_od)
    );

    hkdf_sha3_256 u_dut (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .h4_in(h4_in), .ss_i_in(ss_i_in), .ss_r_in(ss_r_in),
        .spi_i_in(spi_i_in), .spi_r_in(spi_r_in),
        .busy(busy), .done(done), .error(error), .okm(okm),
        .shk_req(h_req), .shk_cfg(h_cfg), .shk_ready(h_ready), .shk_done(h_done),
        .shk_blk_valid(h_bv), .shk_blk_ready(h_br), .shk_blk_data(h_bd),
        .shk_out_valid(h_ov), .shk_out_ready(h_or), .shk_out_data(h_od)
    );
endmodule
