library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.neorv32_package.all;

entity neorv32_setup_25k is
  generic (
    CLOCK_FREQUENCY : natural := 50000000;
    IMEM_SIZE       : natural := 14*1024;
    DMEM_SIZE       : natural := 6*1024
  );
  port (
    clk_i  : in std_ulogic;
    rstn_i : in std_ulogic;
    gpio_o : out std_ulogic_vector(7 downto 0);
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

architecture neorv32_setup_25k_rtl of neorv32_setup_25k is

  signal con_gpio_out : std_ulogic_vector(31 downto 0);
  signal xbus_adr_s   : std_ulogic_vector(31 downto 0);
  signal xbus_dat_os  : std_ulogic_vector(31 downto 0);
  signal xbus_dat_is  : std_ulogic_vector(31 downto 0);
  signal xbus_we_s    : std_ulogic;
  signal xbus_stb_s   : std_ulogic;
  signal xbus_cyc_s   : std_ulogic;
  signal xbus_ack_s   : std_ulogic;
  signal xbus_err_s   : std_ulogic;

begin

  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY  => CLOCK_FREQUENCY,
    BOOT_MODE_SELECT => 2,
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zbb    => false,
    RISCV_ISA_Zicntr => false,
    CPU_FAST_MUL_EN  => true,
    CPU_FAST_MUL_REGS => 1,
    CPU_FAST_SHIFT_EN => true,
    IMEM_EN          => true,
    IMEM_SIZE        => IMEM_SIZE,
    DMEM_EN          => true,
    DMEM_SIZE        => DMEM_SIZE,
    ICACHE_EN        => true,
    ICACHE_NUM_BLOCKS => 32,
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
    gpio_o      => con_gpio_out,
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,
    smc_sck_o   => smc_sck_o,
    smc_csn_o   => smc_csn_o,
    smc_sdo_o   => smc_sdo_o,
    smc_sdi_i   => smc_sdi_i,
    xbus_adr_o  => xbus_adr_s,
    xbus_dat_o  => xbus_dat_os,
    xbus_we_o   => xbus_we_s,
    xbus_sel_o  => xbus_sel_o,
    xbus_stb_o  => xbus_stb_s,
    xbus_cyc_o  => xbus_cyc_s,
    xbus_dat_i  => xbus_dat_is,
    xbus_ack_i  => xbus_ack_s,
    xbus_err_i  => xbus_err_s
  );

  gpio_o <= con_gpio_out(7 downto 0);

    xbus_dat_is <= xbus_dat_i;
    xbus_ack_s  <= xbus_ack_i;
    xbus_err_s  <= xbus_err_i;

    xbus_adr_o <= xbus_adr_s;
    xbus_dat_o <= xbus_dat_os;
    xbus_we_o  <= xbus_we_s;
    xbus_stb_o <= xbus_stb_s;
    xbus_cyc_o <= xbus_cyc_s;

end architecture;
