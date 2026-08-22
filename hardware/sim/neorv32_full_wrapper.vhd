-- NEORV32 wrapper for VHDL-to-Verilog conversion (full SoC, XBUS + SMC).
-- Configuration mirrors neorv32_setup_25k; used by full_top (replace VHDL setup).
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.neorv32_package.all;

entity neorv32_full_wrapper is
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;
    gpio_o      : out std_ulogic_vector(31 downto 0);
    uart0_txd_o : out std_ulogic;
    uart0_rxd_i : in  std_ulogic;
    smc_sck_o   : out std_ulogic;
    smc_csn_o   : out std_ulogic_vector(1 downto 0);
    smc_sdo_o   : out std_ulogic;
    smc_sdi_i   : in  std_ulogic;
    xbus_adr_o  : out std_ulogic_vector(31 downto 0);
    xbus_dat_o  : out std_ulogic_vector(31 downto 0);
    xbus_we_o   : out std_ulogic;
    xbus_sel_o  : out std_ulogic_vector(3 downto 0);
    xbus_stb_o  : out std_ulogic;
    xbus_cyc_o  : out std_ulogic;
    xbus_dat_i  : in  std_ulogic_vector(31 downto 0);
    xbus_ack_i  : in  std_ulogic;
    xbus_err_i  : in  std_ulogic
  );
end entity;

architecture neorv32_full_wrapper_rtl of neorv32_full_wrapper is

begin

  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY  => 50000000,
    BOOT_MODE_SELECT => 0,
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zbb    => false,
    RISCV_ISA_Zicntr => true,
    CPU_FAST_MUL_EN  => true,
    CPU_FAST_MUL_REGS => 1,
    CPU_FAST_SHIFT_EN => true,
    IMEM_EN          => true,
    IMEM_SIZE        => 14*1024,
    DMEM_EN          => true,
    DMEM_SIZE        => 6*1024,
    ICACHE_EN        => false,
    ICACHE_NUM_BLOCKS => 16,
    CACHE_BLOCK_SIZE => 64,
    DCACHE_EN        => false,
    DCACHE_NUM_BLOCKS => 16,
    SMC_EN           => true,
    IO_GPIO_NUM      => 8,
    IO_CLINT_EN      => true,
    IO_UART0_EN      => true,
    IO_SPI_EN        => false,
    IO_TRNG_EN       => false,
    XBUS_EN          => true
  )
  port map (
    clk_i       => clk_i,
    rstn_i      => rstn_i,
    gpio_o      => gpio_o,
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,
    smc_sck_o   => smc_sck_o,
    smc_csn_o   => smc_csn_o,
    smc_sdo_o   => smc_sdo_o,
    smc_sdi_i   => smc_sdi_i,
    xbus_adr_o  => xbus_adr_o,
    xbus_dat_o  => xbus_dat_o,
    xbus_we_o   => xbus_we_o,
    xbus_sel_o  => xbus_sel_o,
    xbus_stb_o  => xbus_stb_o,
    xbus_cyc_o  => xbus_cyc_o,
    xbus_dat_i  => xbus_dat_i,
    xbus_ack_i  => xbus_ack_i,
    xbus_err_i  => xbus_err_i
  );

end architecture;
