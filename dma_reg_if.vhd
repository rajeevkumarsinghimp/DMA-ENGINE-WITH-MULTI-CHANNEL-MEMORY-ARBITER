-- dma_reg_if.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_reg_if is
  generic (
    NUM_CH     : integer := 4;
    ADDR_WIDTH : integer := 32
  );
  port (
    clk   : in std_logic;
    rst_n : in std_logic;

    -- AXI-lite slave minimal
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

    -- per-channel control/status
    ch_start     : out std_logic_vector(NUM_CH-1 downto 0);
    ch_desc_base : out std_logic_vector(NUM_CH*ADDR_WIDTH-1 downto 0);
    ch_reset     : out std_logic_vector(NUM_CH-1 downto 0);
    ch_status    : in  std_logic_vector(NUM_CH*32-1 downto 0);

    irq_src      : in  std_logic_vector(NUM_CH-1 downto 0)
  );
end entity;

architecture rtl of dma_reg_if is
  signal addr_reg : std_logic_vector(31 downto 0) := (others => '0');
begin

  -- Very small AXI-lite handling similar to the Verilog example.
  process(clk, rst_n)
    variable ch : integer;
    variable off: integer;
  begin
    if rst_n = '0' then
      s_axi_awready <= '0';
      s_axi_wready  <= '0';
      s_axi_bvalid  <= '0';
      s_axi_bresp   <= (others => '0');
      s_axi_arready <= '0';
      s_axi_rvalid  <= '0';
      s_axi_rdata   <= (others => '0');
      ch_start <= (others => '0');
      ch_desc_base <= (others => '0');
      ch_reset <= (others => '0');
    elsif rising_edge(clk) then
      -- write address handshake
      if s_axi_awvalid = '1' and s_axi_awready = '0' then
        s_axi_awready <= '1';
        addr_reg <= s_axi_awaddr;
      else
        s_axi_awready <= '0';
      end if;

      -- write data handshake
      if s_axi_wvalid = '1' and s_axi_wready = '0' then
        s_axi_wready <= '1';
      else
        s_axi_wready <= '0';
      end if;

      -- write completion
      if s_axi_awready = '1' and s_axi_awvalid = '1' and s_axi_wready = '1' and s_axi_wvalid = '1' then
        -- decode
        if unsigned(addr_reg) >= x"00000100" and unsigned(addr_reg) < x"00000100" + NUM_CH*16 then
          ch := to_integer(unsigned(addr_reg(7 downto 0))) / 16; -- simplified indexing
          off := to_integer(unsigned(addr_reg(3 downto 0)));
          if off = 0 then
            ch_start(ch) <= s_axi_wdata(0);
            ch_reset(ch) <= s_axi_wdata(1);
          elsif off = 4 then
            -- write desc base
            ch_desc_base((ch+1)*ADDR_WIDTH-1 downto ch*ADDR_WIDTH) <= s_axi_wdata;
          end if;
        end if;
        s_axi_bvalid <= '1';
        s_axi_bresp <= "00";
      elsif s_axi_bvalid = '1' and s_axi_bready = '1' then
        s_axi_bvalid <= '0';
      end if;

      -- read address handshake
      if s_axi_arvalid = '1' and s_axi_arready = '0' then
        s_axi_arready <= '1';
        addr_reg <= s_axi_araddr;
      else
        s_axi_arready <= '0';
      end if;

      if s_axi_arready = '1' and s_axi_arvalid = '1' then
        if unsigned(addr_reg) >= x"00000100" and unsigned(addr_reg) < x"00000100" + NUM_CH*16 then
          ch := to_integer(unsigned(addr_reg(7 downto 0))) / 16;
          off := to_integer(unsigned(addr_reg(3 downto 0)));
          if off = 0 then
            s_axi_rdata <= (30 => '0') & ch_reset(ch) & ch_start(ch); -- pack
          elsif off = 4 then
            s_axi_rdata <= ch_desc_base((ch+1)*ADDR_WIDTH-1 downto ch*ADDR_WIDTH);
          elsif off = 8 then
            s_axi_rdata <= ch_status((ch+1)*32-1 downto ch*32);
          else
            s_axi_rdata <= (others => '0');
          end if;
        elsif unsigned(addr_reg) = x"00000200" then
          s_axi_rdata <= (31-NUM_CH downto 0 => '0') & irq_src;
        else
          s_axi_rdata <= (others => '0');
        end if;
        s_axi_rvalid <= '1';
        s_axi_rresp <= "00";
      elsif s_axi_rvalid = '1' and s_axi_rready = '1' then
        s_axi_rvalid <= '0';
      end if;

    end if;
  end process;

end architecture;
