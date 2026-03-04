-- axi_master.vhd (skeleton placeholder)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_master is
  generic (
    ADDR_WIDTH : integer := 32;
    DATA_WIDTH : integer := 64
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    -- AW
    awaddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    awlen   : out std_logic_vector(7 downto 0);
    awsize  : out std_logic_vector(2 downto 0);
    awburst : out std_logic_vector(1 downto 0);
    awvalid : out std_logic;
    awready : in  std_logic;
    -- W
    wdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    wstrb   : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    wlast   : out std_logic;
    wvalid  : out std_logic;
    wready  : in  std_logic;
    -- B
    bresp   : in  std_logic_vector(1 downto 0);
    bvalid  : in  std_logic;
    bready  : out std_logic;
    -- AR
    araddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    arlen   : out std_logic_vector(7 downto 0);
    arsize  : out std_logic_vector(2 downto 0);
    arburst : out std_logic_vector(1 downto 0);
    arvalid : out std_logic;
    arready : in  std_logic;
    -- R
    rdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    rresp   : in  std_logic_vector(1 downto 0);
    rlast   : in  std_logic;
    rvalid  : in  std_logic;
    rready  : out std_logic
  );
end entity;

architecture rtl of axi_master is
begin
  -- Minimal placeholder FSM — integrate with arbiter if you want a standalone master.
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      awvalid <= '0';
      wvalid  <= '0';
      arvalid <= '0';
      rready  <= '0';
      bready  <= '0';
    elsif rising_edge(clk) then
      -- left as exercise to drive AXI transactions
    end if;
  end process;
end architecture;
