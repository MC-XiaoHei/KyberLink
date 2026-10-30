module bram_128x16 (
    input  wire         clk,
    input  wire [  3:0] waddr,
    input  wire [127:0] wdata,
    input  wire         we,
    input  wire [  3:0] raddr,
    output wire [127:0] rdata
);

  wire [13:0] wa = {5'b00000, waddr, 1'b0, 4'b1111};
  wire [13:0] ra = {5'b00000, raddr, 5'b00000};
  wire [31:0] do0, do1, do2, do3;

  SDPB #(
      .BIT_WIDTH_0(32),
      .BIT_WIDTH_1(32)
  ) u0 (
      .DO(do0),
      .DI(wdata[31:0]),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000),
      .ADA(wa),
      .ADB(ra),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(we),
      .CEB(1'b1),
      .OCE(1'b1),
      .RESET(1'b0)
  );
  SDPB #(
      .BIT_WIDTH_0(32),
      .BIT_WIDTH_1(32)
  ) u1 (
      .DO(do1),
      .DI(wdata[63:32]),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000),
      .ADA(wa),
      .ADB(ra),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(we),
      .CEB(1'b1),
      .OCE(1'b1),
      .RESET(1'b0)
  );
  SDPB #(
      .BIT_WIDTH_0(32),
      .BIT_WIDTH_1(32)
  ) u2 (
      .DO(do2),
      .DI(wdata[95:64]),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000),
      .ADA(wa),
      .ADB(ra),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(we),
      .CEB(1'b1),
      .OCE(1'b1),
      .RESET(1'b0)
  );
  SDPB #(
      .BIT_WIDTH_0(32),
      .BIT_WIDTH_1(32)
  ) u3 (
      .DO(do3),
      .DI(wdata[127:96]),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000),
      .ADA(wa),
      .ADB(ra),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(we),
      .CEB(1'b1),
      .OCE(1'b1),
      .RESET(1'b0)
  );

  assign rdata = {do3, do2, do1, do0};

endmodule
