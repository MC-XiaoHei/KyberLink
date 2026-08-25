`timescale 1ns/1ps
module nrv_xip_top (
    input  wire        clk_i,
    input  wire        rstn_i,
    output wire [31:0] gpio_o,
    output wire        uart0_txd_o,
    input  wire        uart0_rxd_i
);
    wire smc_sck;
    wire [1:0] smc_csn;
    wire smc_sdo;
    wire smc_sdi;

    neorv32_wrapper u_nrv (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .gpio_o(gpio_o),
        .uart0_txd_o(uart0_txd_o),
        .uart0_rxd_i(uart0_rxd_i),
        .smc_sck_o(smc_sck),
        .smc_csn_o(smc_csn),
        .smc_sdo_o(smc_sdo),
        .smc_sdi_i(smc_sdi)
    );

    w25q64_model u_flash (
        .sck(smc_sck),
        .csn(smc_csn[0]),
        .sdo(smc_sdo),
        .sdi(smc_sdi)
    );
endmodule
