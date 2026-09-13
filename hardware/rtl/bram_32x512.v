module bram_32x512 (
    input  wire        clk,
    input  wire [ 8:0] waddr,
    input  wire [31:0] wdata,
    input  wire        we,
    input  wire [ 8:0] raddr,
    output wire [31:0] rdata
);

  SDPB #(
      .BIT_WIDTH_0(32),
      .BIT_WIDTH_1(32)
  ) u0 (
      .DO(rdata),
      .DI(wdata),
      .BLKSELA(3'b000),
      .BLKSELB(3'b000),
      .ADA({waddr[8:0], 1'b0, 4'b1111}),
      .ADB({raddr[8:0], 5'b00000}),
      .CLKA(clk),
      .CLKB(clk),
      .CEA(we),
      .CEB(1'b1),
      .OCE(1'b1),
      .RESET(1'b0)
  );

endmodule
