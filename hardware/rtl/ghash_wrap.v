module ghash_wrap (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [127:0] h,
    input  wire [127:0] d,
    input  wire dv,
    input  wire [7:0] nb,
    output wire busy,
    output wire done,
    output wire ready,
    output wire accept,
    output wire [127:0] tag
);
    ghash u_ghash (
        .clk(clk), .rst_n(rst_n), .start(start), .h(h), .data_in(d),
        .data_valid(dv), .nblocks(nb), .busy(busy), .done(done),
        .ready(ready), .block_done(), .accept(accept), .tag(tag)
    );
endmodule
