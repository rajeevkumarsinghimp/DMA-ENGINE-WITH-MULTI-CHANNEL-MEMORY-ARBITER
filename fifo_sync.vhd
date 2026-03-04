-- fifo_sync.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_sync is
  generic (
    WIDTH : integer := 32;
    DEPTH : integer := 16
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    din   : in  std_logic_vector(WIDTH-1 downto 0);
    wr_en : in  std_logic;
    rd_en : in  std_logic;
    dout  : out std_logic_vector(WIDTH-1 downto 0);
    full  : out std_logic;
    empty : out std_logic
  );
end entity;

architecture rtl of fifo_sync is
  type mem_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  signal wptr : unsigned(ceil_log2(DEPTH)-1 downto 0) := (others => '0');
  signal rptr : unsigned(ceil_log2(DEPTH)-1 downto 0) := (others => '0');
  signal count : unsigned(ceil_log2(DEPTH) downto 0) := (others => '0');

  -- helper function for ceil(log2)
  function ceil_log2(n : integer) return integer is
    variable i : integer := 0;
    variable v : integer := 1;
  begin
    while v < n loop
      v := v * 2;
      i := i + 1;
    end loop;
    return i;
  end function;

begin

  full  <= '1' when count = to_unsigned(DEPTH, count'length) else '0';
  empty <= '1' when count = 0 else '0';

  process(clk, rst_n)
  begin
    if rst_n = '0' then
      wptr <= (others => '0');
      rptr <= (others => '0');
      count <= (others => '0');
      dout <= (others => '0');
    elsif rising_edge(clk) then
      if wr_en = '1' and full = '0' then
        mem(to_integer(wptr)) <= din;
        wptr <= wptr + 1;
        count <= count + 1;
      end if;
      if rd_en = '1' and empty = '0' then
        dout <= mem(to_integer(rptr));
        rptr <= rptr + 1;
        count <= count - 1;
      end if;
    end if;
  end process;

end architecture;
