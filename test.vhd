library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_dma_top is
end tb_dma_top;

architecture sim of tb_dma_top is

constant NUM_CH     : integer := 4;
constant ADDR_WIDTH : integer := 32;
constant DATA_WIDTH : integer := 64;

signal clk   : std_logic := '0';
signal rst_n : std_logic := '0';

-- AXI Lite signals
signal s_axi_awaddr  : std_logic_vector(31 downto 0);
signal s_axi_awvalid : std_logic;
signal s_axi_awready : std_logic;

signal s_axi_wdata   : std_logic_vector(31 downto 0);
signal s_axi_wstrb   : std_logic_vector(3 downto 0);
signal s_axi_wvalid  : std_logic;
signal s_axi_wready  : std_logic;

signal s_axi_bresp   : std_logic_vector(1 downto 0);
signal s_axi_bvalid  : std_logic;
signal s_axi_bready  : std_logic;

signal s_axi_araddr  : std_logic_vector(31 downto 0);
signal s_axi_arvalid : std_logic;
signal s_axi_arready : std_logic;

signal s_axi_rdata   : std_logic_vector(31 downto 0);
signal s_axi_rresp   : std_logic_vector(1 downto 0);
signal s_axi_rvalid  : std_logic;
signal s_axi_rready  : std_logic;

-- AXI MASTER (memory side)

signal m_axil_awaddr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal m_axil_awvalid : std_logic;
signal m_axil_awready : std_logic := '0';

signal m_axil_wdata   : std_logic_vector(DATA_WIDTH-1 downto 0);
signal m_axil_wvalid  : std_logic;
signal m_axil_wready  : std_logic := '0';
signal m_axil_wlast   : std_logic;

signal m_axil_bresp   : std_logic_vector(1 downto 0) := "00";
signal m_axil_bvalid  : std_logic := '0';
signal m_axil_bready  : std_logic;

signal m_axil_araddr  : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal m_axil_arvalid : std_logic;
signal m_axil_arready : std_logic := '0';

signal m_axil_rdata   : std_logic_vector(DATA_WIDTH-1 downto 0);
signal m_axil_rvalid  : std_logic := '0';
signal m_axil_rlast   : std_logic := '0';
signal m_axil_rready  : std_logic;

signal irq : std_logic;

begin

------------------------------------------------
-- CLOCK
------------------------------------------------

clk_process : process
begin
    clk <= '0';
    wait for 5 ns;
    clk <= '1';
    wait for 5 ns;
end process;


------------------------------------------------
-- RESET
------------------------------------------------

reset_process : process
begin
    rst_n <= '0';
    wait for 100 ns;
    rst_n <= '1';
    wait;
end process;


------------------------------------------------
-- DUT INSTANTIATION
------------------------------------------------

dut : entity work.dma_top
generic map(
    NUM_CH => NUM_CH,
    ADDR_WIDTH => ADDR_WIDTH,
    DATA_WIDTH => DATA_WIDTH
)
port map(

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

irq => irq,

m_axil_awaddr => m_axil_awaddr,
m_axil_awvalid => m_axil_awvalid,
m_axil_awready => m_axil_awready,

m_axil_wdata => m_axil_wdata,
m_axil_wvalid => m_axil_wvalid,
m_axil_wready => m_axil_wready,
m_axil_wlast => m_axil_wlast,

m_axil_bresp => m_axil_bresp,
m_axil_bvalid => m_axil_bvalid,
m_axil_bready => m_axil_bready,

m_axil_araddr => m_axil_araddr,
m_axil_arvalid => m_axil_arvalid,
m_axil_arready => m_axil_arready,

m_axil_rdata => m_axil_rdata,
m_axil_rvalid => m_axil_rvalid,
m_axil_rlast => m_axil_rlast,
m_axil_rready => m_axil_rready
);


------------------------------------------------
-- SIMPLE AXI MEMORY MODEL
------------------------------------------------

memory_model : process(clk)
begin

if rising_edge(clk) then

-- READ ADDRESS
if m_axil_arvalid = '1' then
    m_axil_arready <= '1';
else
    m_axil_arready <= '0';
end if;

-- READ DATA
if m_axil_arvalid = '1' then
    m_axil_rvalid <= '1';
    m_axil_rlast  <= '1';
    m_axil_rdata  <= x"DEADBEEFCAFEBABE";
else
    m_axil_rvalid <= '0';
    m_axil_rlast  <= '0';
end if;

-- WRITE ADDRESS
if m_axil_awvalid = '1' then
    m_axil_awready <= '1';
else
    m_axil_awready <= '0';
end if;

-- WRITE DATA
if m_axil_wvalid = '1' then
    m_axil_wready <= '1';
else
    m_axil_wready <= '0';
end if;

-- WRITE RESPONSE
if m_axil_wvalid = '1' then
    m_axil_bvalid <= '1';
else
    m_axil_bvalid <= '0';
end if;

end if;

end process;


------------------------------------------------
-- AXI-LITE WRITE PROCEDURE
------------------------------------------------

procedure axi_write(
    signal clk       : in std_logic;
    signal awaddr    : out std_logic_vector(31 downto 0);
    signal awvalid   : out std_logic;
    signal wdata     : out std_logic_vector(31 downto 0);
    signal wvalid    : out std_logic
) is
begin

wait until rising_edge(clk);

awaddr  <= x"00000100";
awvalid <= '1';
wdata   <= x"00000001";
wvalid  <= '1';

wait until rising_edge(clk);

awvalid <= '0';
wvalid  <= '0';

end procedure;


------------------------------------------------
-- TEST SEQUENCE
------------------------------------------------

stimulus : process
begin

wait until rst_n = '1';

wait for 50 ns;

-- Start Channel 0
s_axi_awaddr  <= x"00000100";
s_axi_awvalid <= '1';
s_axi_wdata   <= x"00000001";
s_axi_wvalid  <= '1';

wait for 20 ns;

s_axi_awvalid <= '0';
s_axi_wvalid  <= '0';

-- Start Channel 1
wait for 100 ns;

s_axi_awaddr  <= x"00000110";
s_axi_awvalid <= '1';
s_axi_wdata   <= x"00000001";
s_axi_wvalid  <= '1';

wait for 20 ns;

s_axi_awvalid <= '0';
s_axi_wvalid  <= '0';

wait for 5000 ns;

report "DMA Simulation Completed";

wait;

end process;

end architecture;
