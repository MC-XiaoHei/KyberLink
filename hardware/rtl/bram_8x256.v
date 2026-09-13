module bram_8x256 (
    input  wire       clk,
    input  wire [7:0] waddr,
    input  wire [7:0] wdata,
    input  wire       we,
    input  wire [7:0] raddr,
    output wire [7:0] rdata
);

  wire [15:0] do0, do1;
  wire [13:0] wa = {6'b000000, waddr, 2'b00};
  wire [13:0] ra = {6'b000000, raddr, 2'b00};

  DPB #(
      .BIT_WIDTH_0(8),
      .BIT_WIDTH_1(8)
  ) u0 (
      .DOA(),
      .DOB(do0),
      .DIA(wdata),
      .DIB(8'd0),
      .ADA(wa),
      .ADB(ra),
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
  assign rdata = do0[7:0];

endmodule
