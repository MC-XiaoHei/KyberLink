-- KyberLink Tang Primer 25K (GW5A-25) NEORV32 setup
-- RV32IMC + IMEM/DMEM + UART0/SPI/TRNG/XBUS + SMC(XIP) + I-Cache
-- Library references flattened to work for GowinSynthesis CLI
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.neorv32_package.all;

entity neorv32_setup_25k is
  generic (
    CLOCK_FREQUENCY : natural := 50000000;
    IMEM_SIZE       : natural := 16*1024;
    DMEM_SIZE       : natural := 8*1024
  );
  port (
    clk_i  : in std_ulogic;
    rstn_i : in std_ulogic;
    gpio_o : out std_ulogic_vector(7 downto 0);
    uart0_txd_o : out std_ulogic;
    uart0_rxd_i : in  std_ulogic;
    spi_clk_o   : out std_ulogic;
    spi_dat_o   : out std_ulogic;
    spi_dat_i   : in  std_ulogic;
    spi_csn_o   : out std_ulogic_vector(7 downto 0);
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
  signal kperm_in     : std_ulogic_vector(1599 downto 0);
  signal kperm_round  : std_ulogic_vector(4 downto 0);
  signal kperm_out    : std_ulogic_vector(1599 downto 0);
  signal k_dat_o      : std_ulogic_vector(31 downto 0);
  signal k_ack_o      : std_ulogic;
  signal bc_dat_o     : std_ulogic_vector(31 downto 0);
  signal bc_ack_o     : std_ulogic;

  component neorv32_keccak_xbus is
    port (
      clk            : in  std_logic;
      rst_n          : in  std_logic;
      xbus_adr_i     : in  std_logic_vector(31 downto 0);
      xbus_dat_i     : in  std_logic_vector(31 downto 0);
      xbus_we_i      : in  std_logic;
      xbus_stb_i     : in  std_logic;
      xbus_cyc_i     : in  std_logic;
      xbus_dat_o     : out std_logic_vector(31 downto 0);
      xbus_ack_o     : out std_logic;
      xbus_err_o     : out std_logic;
      perm_state_in  : out std_logic_vector(1599 downto 0);
      perm_round     : out std_logic_vector(4 downto 0);
      perm_state_out : in  std_logic_vector(1599 downto 0)
    );
  end component;

  component bridge_ctrl is
    port (
      clk            : in  std_logic;
      rst_n          : in  std_logic;
      xbus_adr_i     : in  std_logic_vector(31 downto 0);
      xbus_dat_i     : in  std_logic_vector(31 downto 0);
      xbus_we_i      : in  std_logic;
      xbus_stb_i     : in  std_logic;
      xbus_cyc_i     : in  std_logic;
      xbus_dat_o     : out std_logic_vector(31 downto 0);
      xbus_ack_o     : out std_logic;
      xbus_err_o     : out std_logic;
      cfg_key        : out std_logic_vector(255 downto 0);
      cfg_sa_en      : out std_logic;
      cfg_cmd_start  : out std_logic;
      data_sa_active : in  std_logic;
      data_count_tx  : in  std_logic_vector(31 downto 0);
      data_count_rx  : in  std_logic_vector(31 downto 0)
    );
  end component;

  component keccak_f1600_round is
    port (
      state_in  : in  std_logic_vector(1599 downto 0);
      round     : in  std_logic_vector(4 downto 0);
      state_out : out std_logic_vector(1599 downto 0)
    );
  end component;

begin

  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY  => CLOCK_FREQUENCY,
    BOOT_MODE_SELECT => 0,
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zbb    => true,
    RISCV_ISA_Zicntr => true,
    CPU_FAST_MUL_EN  => true,
    CPU_FAST_MUL_REGS => 1,
    CPU_FAST_SHIFT_EN => true,
    IMEM_EN          => true,
    IMEM_SIZE        => IMEM_SIZE,
    DMEM_EN          => true,
    DMEM_SIZE        => DMEM_SIZE,
    ICACHE_EN        => true,
    ICACHE_NUM_BLOCKS => 16,
    CACHE_BLOCK_SIZE => 64,
    DCACHE_EN        => true,
    DCACHE_NUM_BLOCKS => 16,
    SMC_EN           => true,
    IO_GPIO_NUM      => 8,
    IO_CLINT_EN      => true,
    IO_UART0_EN      => true,
    IO_SPI_EN        => true,
    IO_TRNG_EN       => true,
    XBUS_EN          => true
  )
  port map (
    clk_i       => clk_i,
    rstn_i      => rstn_i,
    gpio_o      => con_gpio_out,
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,
    spi_clk_o   => spi_clk_o,
    spi_dat_o   => spi_dat_o,
    spi_dat_i   => spi_dat_i,
    spi_csn_o   => spi_csn_o,
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

    keccak_inst: neorv32_keccak_xbus
    port map (
        clk            => clk_i,
        rst_n          => rstn_i,
        xbus_adr_i     => std_logic_vector(xbus_adr_s),
        xbus_dat_i     => std_logic_vector(xbus_dat_os),
        xbus_we_i      => std_logic(xbus_we_s),
        xbus_stb_i     => std_logic(xbus_stb_s),
        xbus_cyc_i     => std_logic(xbus_cyc_s),
        xbus_dat_o     => k_dat_o,
        xbus_ack_o     => k_ack_o,
        xbus_err_o     => xbus_err_s,
        perm_state_in  => kperm_in,
        perm_round     => kperm_round,
        perm_state_out => kperm_out
    );

    keccak_round_inst: keccak_f1600_round
    port map (
        state_in  => kperm_in,
        round     => kperm_round,
        state_out => kperm_out
    );

    bridge_ctrl_inst: bridge_ctrl
    port map (
        clk            => clk_i,
        rst_n          => rstn_i,
        xbus_adr_i     => std_logic_vector(xbus_adr_s),
        xbus_dat_i     => std_logic_vector(xbus_dat_os),
        xbus_we_i      => std_logic(xbus_we_s),
        xbus_stb_i     => std_logic(xbus_stb_s),
        xbus_cyc_i     => std_logic(xbus_cyc_s),
        xbus_dat_o     => bc_dat_o,
        xbus_ack_o     => bc_ack_o,
        xbus_err_o     => open,
        cfg_key        => open,
        cfg_sa_en      => open,
        cfg_cmd_start  => open,
        data_sa_active => '0',
        data_count_tx  => (others => '0'),
        data_count_rx  => (others => '0')
    );

    xbus_dat_is <= k_dat_o when (xbus_adr_s(31 downto 8) = x"F00000") else
                   bc_dat_o when (xbus_adr_s(31 downto 8) = x"F00001") else
                   (others => '0');
    xbus_ack_s  <= k_ack_o or bc_ack_o;

    xbus_adr_o <= xbus_adr_s;
    xbus_dat_o <= xbus_dat_os;
    xbus_we_o  <= xbus_we_s;
    xbus_stb_o <= xbus_stb_s;
    xbus_cyc_o <= xbus_cyc_s;

end architecture;
