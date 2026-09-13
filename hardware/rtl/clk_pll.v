module clk_pll (
    input  wire clk,
    output wire clk_sys,
    output wire locked
);

  wire gw_gnd;
  assign gw_gnd = 1'b0;

  // Fclkin=50MHz, Fpfd=50/IDIV=50MHz, Fvco=Fpfd*FBDIV*MDIV=1000MHz, Fclkout0=Fvco/ODIV0=125MHz
  PLLA #(
      .FCLKIN("50"),
      .IDIV_SEL(1),
      .FBDIV_SEL(1),
      .MDIV_SEL(20),
      .ODIV0_SEL(8),
      .CLKFB_SEL("INTERNAL"),
      .CLKOUT0_EN("TRUE")
  ) pll_inst (
      .CLKIN(clk),
      .CLKFB(gw_gnd),
      .CLKOUT0(clk_sys),
      .CLKOUT1(),
      .CLKOUT2(),
      .CLKOUT3(),
      .CLKOUT4(),
      .CLKOUT5(),
      .CLKOUT6(),
      .CLKFBOUT(),
      .MDRDO(),
      .LOCK(locked),
      .PSSEL({gw_gnd, gw_gnd, gw_gnd}),
      .PSDIR(gw_gnd),
      .PSPULSE(gw_gnd),
      .SSCPOL(gw_gnd),
      .SSCON(gw_gnd),
      .SSCMDSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .SSCMDSEL_FRAC({gw_gnd, gw_gnd, gw_gnd}),
      .MDWDI({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .MDCLK(gw_gnd),
      .MDOPC({gw_gnd, gw_gnd}),
      .MDAINC(gw_gnd),
      .RESET(gw_gnd),
      .PLLPWD(gw_gnd),
      .RESET_I(gw_gnd),
      .RESET_O(gw_gnd)
  );

endmodule
