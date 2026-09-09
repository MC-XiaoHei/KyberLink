module bram_32x2048 (
    input  wire        clk,
    input  wire [10:0] waddr,
    input  wire [31:0] wdata,
    input  wire        we,
    input  wire [10:0] raddr,
    output wire [31:0] rdata
);

  wire [7:0] do0, do1, do2, do3;

  DPB #(
      .BIT_WIDTH_0(8),
      .BIT_WIDTH_1(8)
  ) u0 (
      .DOA(),
      .DOB(do0),
      .DIA(wdata[7:0]),
      .DIB(8'd0),
      .ADA({waddr[10:0], 3'b000}),
      .ADB({raddr[10:0], 3'b000}),
      .WREA(we),
      .WREB(1'b0),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(1'b1),
      .CEB(1'b1),
      .OCEA(1'b1),
      .OCEB(1'b1),
      .RESETA(1'b0),
      .RESETB(1'b0),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000)
  );
  DPB #(
      .BIT_WIDTH_0(8),
      .BIT_WIDTH_1(8)
  ) u1 (
      .DOA(),
      .DOB(do1),
      .DIA(wdata[15:8]),
      .DIB(8'd0),
      .ADA({waddr[10:0], 3'b000}),
      .ADB({raddr[10:0], 3'b000}),
      .WREA(we),
      .WREB(1'b0),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(1'b1),
      .CEB(1'b1),
      .OCEA(1'b1),
      .OCEB(1'b1),
      .RESETA(1'b0),
      .RESETB(1'b0),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000)
  );
  DPB #(
      .BIT_WIDTH_0(8),
      .BIT_WIDTH_1(8)
  ) u2 (
      .DOA(),
      .DOB(do2),
      .DIA(wdata[23:16]),
      .DIB(8'd0),
      .ADA({waddr[10:0], 3'b000}),
      .ADB({raddr[10:0], 3'b000}),
      .WREA(we),
      .WREB(1'b0),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(1'b1),
      .CEB(1'b1),
      .OCEA(1'b1),
      .OCEB(1'b1),
      .RESETA(1'b0),
      .RESETB(1'b0),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000)
  );
  DPB #(
      .BIT_WIDTH_0(8),
      .BIT_WIDTH_1(8)
  ) u3 (
      .DOA(),
      .DOB(do3),
      .DIA(wdata[31:24]),
      .DIB(8'd0),
      .ADA({waddr[10:0], 3'b000}),
      .ADB({raddr[10:0], 3'b000}),
      .WREA(we),
      .WREB(1'b0),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(1'b1),
      .CEB(1'b1),
      .OCEA(1'b1),
      .OCEB(1'b1),
      .RESETA(1'b0),
      .RESETB(1'b0),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000)
  );

  assign rdata = {do3, do2, do1, do0};

endmodule
