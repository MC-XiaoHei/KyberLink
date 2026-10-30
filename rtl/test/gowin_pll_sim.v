`timescale 1ps/1ps
module PLLA (
    output wire CLKOUT0,
    output wire CLKOUT1,
    output wire CLKOUT2,
    output wire CLKOUT3,
    output wire CLKOUT4,
    output wire CLKOUT5,
    output wire CLKOUT6,
    output wire CLKFBOUT,
    output wire [7:0] MDRDO,
    output wire LOCK,
    input  wire CLKIN,
    input  wire CLKFB,
    input  wire [2:0] PSSEL,
    input  wire PSDIR,
    input  wire PSPULSE,
    input  wire SSCPOL,
    input  wire SSCON,
    input  wire [6:0] SSCMDSEL,
    input  wire [2:0] SSCMDSEL_FRAC,
    input  wire [7:0] MDWDI,
    input  wire MDCLK,
    input  wire [1:0] MDOPC,
    input  wire MDAINC,
    input  wire RESET,
    input  wire PLLPWD,
    input  wire RESET_I,
    input  wire RESET_O
);
  parameter FCLKIN = "50";
  parameter FCLKIN_MHZ = 50;
  parameter IDIV_SEL = 1;
  parameter FBDIV_SEL = 1;
  parameter MDIV_SEL = 8;
  parameter ODIV0_SEL = 8;
  parameter ODIV1_SEL = 8;
  parameter ODIV2_SEL = 8;
  parameter ODIV3_SEL = 8;
  parameter ODIV4_SEL = 8;
  parameter ODIV5_SEL = 8;
  parameter ODIV6_SEL = 8;
  parameter ODIV0_FRAC_SEL = 0;
  parameter MDIV_FRAC_SEL = 0;
  parameter CLKFB_SEL = "INTERNAL";
  parameter CLKOUT0_EN = "TRUE";
  parameter CLKOUT1_EN = "FALSE";
  parameter CLKOUT2_EN = "FALSE";
  parameter CLKOUT3_EN = "FALSE";
  parameter CLKOUT4_EN = "FALSE";
  parameter CLKOUT5_EN = "FALSE";
  parameter CLKOUT6_EN = "FALSE";

  // HALF_PS = 1000000 / FCLKIN_MHZ * IDIV_SEL * ODIV0_SEL / (2 * FBDIV_SEL * MDIV_SEL)
  localparam integer HALF_PS =
      (1000000 / FCLKIN_MHZ) * IDIV_SEL * ODIV0_SEL / (2 * FBDIV_SEL * MDIV_SEL);

  reg clk0_r = 1'b0;
  reg lock_r = 1'b0;

  initial begin
    clk0_r = 1'b0;
    lock_r = 1'b0;
    #(HALF_PS * 16) lock_r = 1'b1;
    forever #(HALF_PS) clk0_r = ~clk0_r;
  end

  assign CLKOUT0  = clk0_r;
  assign CLKOUT1  = 1'b0;
  assign CLKOUT2  = 1'b0;
  assign CLKOUT3  = 1'b0;
  assign CLKOUT4  = 1'b0;
  assign CLKOUT5  = 1'b0;
  assign CLKOUT6  = 1'b0;
  assign CLKFBOUT = clk0_r;
  assign MDRDO    = 8'd0;
  assign LOCK     = lock_r;
endmodule
