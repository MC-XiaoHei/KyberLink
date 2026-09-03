module br_min (
    input  wire clk,
    input  wire rst_n,
    input  wire start_i,
    input  wire [255:0] key,
    input  wire [95:0] nonce,
    input  wire [127:0] aad_i,
    input  wire [11:0] pt_len,
    input  wire pt_valid,
    input  wire [127:0] pt_data,
    input  wire ct_ready,
    output wire [127:0] tag_o,
    output wire tag_valid_o
);
    wire pt_ready, ct_valid, busy, done, idle;
    wire [127:0] ct_data;
    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n), .start(start_i), .key(key), .nonce(nonce),
        .aad(aad_i), .aad_len(5'd8), .pt_len(pt_len), .pt_valid(pt_valid),
        .pt_ready(pt_ready), .pt_data(pt_data), .ct_valid(ct_valid), .ct_ready(ct_ready),
        .ct_data(ct_data), .tag_valid(tag_valid_o), .tag(tag_o),
        .decrypt(1'b0), .busy(busy), .done(done), .idle(idle)
    );
endmodule
