-- dma_top.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_top is
  generic (
    NUM_CH     : integer := 4;
    ADDR_WIDTH : integer := 32;
    DATA_WIDTH : integer := 64;
    DESC_WIDTH : integer := 128
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;

    -- AXI4-Lite slave (control/status)
    s_axi_awaddr  : in  std_logic_vector(31 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(31 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;

    -- Interrupt
    irq : out std_logic;

    -- AXI master (simplified top-level tie-through)
    m_axil_awid    : out std_logic_vector(3 downto 0);
    m_axil_awaddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    m_axil_awlen   : out std_logic_vector(7 downto 0);
    m_axil_awsize  : out std_logic_vector(2 downto 0);
    m_axil_awburst : out std_logic_vector(1 downto 0);
    m_axil_awvalid : out std_logic;
    m_axil_awready : in  std_logic;

    m_axil_wdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axil_wstrb   : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    m_axil_wlast   : out std_logic;
    m_axil_wvalid  : out std_logic;
    m_axil_wready  : in  std_logic;

    m_axil_bresp   : in  std_logic_vector(1 downto 0);
    m_axil_bvalid  : in  std_logic;
    m_axil_bready  : out std_logic;

    m_axil_arid    : out std_logic_vector(3 downto 0);
    m_axil_araddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    m_axil_arlen   : out std_logic_vector(7 downto 0);
    m_axil_arsize  : out std_logic_vector(2 downto 0);
    m_axil_arburst : out std_logic_vector(1 downto 0);
    m_axil_arvalid : out std_logic;
    m_axil_arready : in  std_logic;

    m_axil_rdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axil_rresp   : in  std_logic_vector(1 downto 0);
    m_axil_rlast   : in  std_logic;
    m_axil_rvalid  : in  std_logic;
    m_axil_rready  : out std_logic
  );
end entity;

architecture rtl of dma_top is

  -- per-channel control/status signals
  type addr_array_t is array (natural range <>) of std_logic_vector(ADDR_WIDTH-1 downto 0);
  type status_array_t is array (natural range <>) of std_logic_vector(31 downto 0);

  signal reg_start_ch   : std_logic_vector(NUM_CH-1 downto 0);
  signal reg_reset_ch   : std_logic_vector(NUM_CH-1 downto 0);
  signal reg_desc_base  : addr_array_t(0 to NUM_CH-1);
  signal reg_status     : status_array_t(0 to NUM_CH-1);

  -- channel -> arbiter signals
  signal ch_req        : std_logic_vector(NUM_CH-1 downto 0);
  signal ch_grant      : std_logic_vector(NUM_CH-1 downto 0);
  signal ch_done       : std_logic_vector(NUM_CH-1 downto 0);
  signal ch_error      : std_logic_vector(NUM_CH-1 downto 0);
  signal ch_wlast      : std_logic_vector(NUM_CH-1 downto 0);

  -- flattened vectors for arbiter
  signal ch_type_flat  : std_logic_vector(2*NUM_CH-1 downto 0);
  signal ch_addr_flat  : std_logic_vector(NUM_CH*ADDR_WIDTH-1 downto 0);
  signal ch_blen_flat  : std_logic_vector(NUM_CH*16-1 downto 0);
  signal ch_wdata_flat : std_logic_vector(NUM_CH*DATA_WIDTH-1 downto 0);

  -- irq source
  signal irq_src       : std_logic_vector(NUM_CH-1 downto 0);

begin

  -- Instantiate per-channel dma_channel units
  gen_ch : for i in 0 to NUM_CH-1 generate
    -- slice helpers
    function slice_addr(vec : std_logic_vector) return std_logic_vector is
      variable tmp : std_logic_vector(ADDR_WIDTH-1 downto 0);
    begin
      tmp := vec((i+1)*ADDR_WIDTH-1 downto i*ADDR_WIDTH);
      return tmp;
    end function;

    u_dma_channel : entity work.dma_channel
      generic map (
        ADDR_WIDTH => ADDR_WIDTH,
        DATA_WIDTH => DATA_WIDTH,
        DESC_WIDTH => DESC_WIDTH
      )
      port map (
        clk       => clk,
        rst_n     => rst_n,
        start     => reg_start_ch(i),
        desc_base => reg_desc_base(i),
        reset_ch  => reg_reset_ch(i),
        req       => ch_req(i),
        type      => ch_type_flat((i*2)+1 downto (i*2)),
        addr      => ch_addr_flat((i*ADDR_WIDTH)+ADDR_WIDTH-1 downto i*ADDR_WIDTH),
        burst_len => ch_blen_flat((i*16)+15 downto i*16),
        wdata     => ch_wdata_flat((i*DATA_WIDTH)+DATA_WIDTH-1 downto i*DATA_WIDTH),
        wlast     => ch_wlast(i),
        grant     => ch_grant(i),
        done      => ch_done(i),
        error     => ch_error(i),
        status_out=> reg_status(i),
        irq_out   => irq_src(i)
      );
  end generate;

  -- Arbiter
  u_arbiter: entity work.arbiter
    generic map (
      NUM_CH => NUM_CH,
      ADDR_WIDTH => ADDR_WIDTH,
      DATA_WIDTH => DATA_WIDTH
    )
    port map (
      clk => clk,
      rst_n => rst_n,
      ch_req => ch_req,
      ch_type_flat => ch_type_flat,
      ch_addr_flat => ch_addr_flat,
      ch_burst_len_flat => ch_blen_flat,
      ch_wdata_flat => ch_wdata_flat,
      ch_wlast_flat => ch_wlast,
      ch_grant => ch_grant,
      ch_done => ch_done,
      ch_error => ch_error,
      m_axil_awid => m_axil_awid,
      m_axil_awaddr => m_axil_awaddr,
      m_axil_awlen => m_axil_awlen,
      m_axil_awsize => m_axil_awsize,
      m_axil_awburst => m_axil_awburst,
      m_axil_awvalid => m_axil_awvalid,
      m_axil_awready => m_axil_awready,
      m_axil_wdata => m_axil_wdata,
      m_axil_wstrb => m_axil_wstrb,
      m_axil_wlast => m_axil_wlast,
      m_axil_wvalid => m_axil_wvalid,
      m_axil_wready => m_axil_wready,
      m_axil_bresp => m_axil_bresp,
      m_axil_bvalid => m_axil_bvalid,
      m_axil_bready => m_axil_bready,
      m_axil_arid => m_axil_arid,
      m_axil_araddr => m_axil_araddr,
      m_axil_arlen => m_axil_arlen,
      m_axil_arsize => m_axil_arsize,
      m_axil_arburst => m_axil_arburst,
      m_axil_arvalid => m_axil_arvalid,
      m_axil_arready => m_axil_arready,
      m_axil_rdata => m_axil_rdata,
      m_axil_rresp => m_axil_rresp,
      m_axil_rlast => m_axil_rlast,
      m_axil_rvalid => m_axil_rvalid,
      m_axil_rready => m_axil_rready
    );

  -- Register interface
  u_reg_if: entity work.dma_reg_if
    generic map (
      NUM_CH => NUM_CH,
      ADDR_WIDTH => ADDR_WIDTH
    )
    port map (
      clk => clk,
      rst_n => rst_n,
      s_axi_awaddr => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata => s_axi_wdata,
      s_axi_wstrb => s_axi_wstrb,
      s_axi_wvalid => s_axi_wvalid,
      s_axi_wready => s_axi_wready,
      s_axi_bresp => s_axi_bresp,
      s_axi_bvalid => s_axi_bvalid,
      s_axi_bready => s_axi_bready,
      s_axi_araddr => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata => s_axi_rdata,
      s_axi_rresp => s_axi_rresp,
      s_axi_rvalid => s_axi_rvalid,
      s_axi_rready => s_axi_rready,
      ch_start => reg_start_ch,
      ch_desc_base => reg_desc_base,
      ch_reset => reg_reset_ch,
      ch_status => reg_status,
      irq_src => irq_src
    );

  -- interrupt controller
  u_irq: entity work.interrupt_ctrl
    generic map ( NUM_CH => NUM_CH )
    port map (
      clk => clk,
      rst_n => rst_n,
      irq_in => irq_src,
      irq_out => irq
    );

end architecture;
