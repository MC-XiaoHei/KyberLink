module bw_dual (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_a,
    input  wire [255:0] key,
    input  wire [95:0] nonce_a,
    input  wire [11:0] pt_len_a,
    input  wire        pt_valid_a,
    output wire        pt_ready_a,
    input  wire [127:0] pt_data_a,
    output wire        ct_valid_a,
    input  wire        ct_ready_a,
    output wire [127:0] ct_data_a,
    output wire        tag_valid_a,
    output wire [127:0] tag_a
);

    gcm_stream u_enc (
        .clk(clk), .rst_n(rst_n),
        .start(start_a), .key_refresh(1'b1), .key(key), .nonce(nonce_a),
        .aad(128'd0), .aad_len(5'd0), .pt_len(pt_len_a),
        .pt_valid(pt_valid_a), .pt_ready(pt_ready_a), .pt_data(pt_data_a),
        .ct_valid(ct_valid_a), .ct_ready(ct_ready_a), .ct_data(ct_data_a),
        .tag_valid(tag_valid_a), .tag(tag_a),
        .decrypt(1'b0), .tag_in(128'd0), .tag_ok(), .busy(), .done()
    );

endmodule
