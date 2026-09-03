module bram_128x256 (
    input  wire        clk,
    input  wire [7:0]  waddr,
    input  wire [127:0] wdata,
    input  wire        we,
    input  wire [7:0]  raddr,
    output wire [127:0] rdata
);

    wire [15:0] do0, do1, do2, do3, do4, do5, do6, do7;
    wire [13:0] wa = {2'b00, waddr, 2'b00, 2'b11};
    wire [13:0] ra = {2'b00, raddr, 2'b00, 2'b11};

    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u0 (
        .DOA(), .DOB(do0), .DIA(wdata[15:0]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u1 (
        .DOA(), .DOB(do1), .DIA(wdata[31:16]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u2 (
        .DOA(), .DOB(do2), .DIA(wdata[47:32]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u3 (
        .DOA(), .DOB(do3), .DIA(wdata[63:48]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u4 (
        .DOA(), .DOB(do4), .DIA(wdata[79:64]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u5 (
        .DOA(), .DOB(do5), .DIA(wdata[95:80]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u6 (
        .DOA(), .DOB(do6), .DIA(wdata[111:96]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));
    DPB #(.BIT_WIDTH_0(16), .BIT_WIDTH_1(16)) u7 (
        .DOA(), .DOB(do7), .DIA(wdata[127:112]), .DIB(16'd0),
        .ADA(wa), .ADB(ra), .WREA(we), .WREB(1'b0),
        .CLKA(clk), .CLKB(clk), .CEA(1'b1), .CEB(1'b1),
        .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0),
        .BLKSELA(3'b000), .BLKSELB(3'b000));

    assign rdata = {do7, do6, do5, do4, do3, do2, do1, do0};

endmodule
