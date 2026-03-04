-- perf_counters.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity perf_counters is
  generic ( NUM_CH : integer := 4 );
  port (
    clk   : in std_logic;
    rst_n : in std_logic;
    ch_done : in std_logic_vector(NUM_CH-1 downto 0);
    ch_err  : in std_logic_vector(NUM_CH-1 downto 0);
    perf_done_out : out std_logic_vector(32*NUM_CH-1 downto 0);
    perf_err_out  : out std_logic_vector(32*NUM_CH-1 downto 0)
  );
end entity;

architecture rtl of perf_counters is
  type cnt_array_t is array (0 to NUM_CH-1) of unsigned(31 downto 0);
  signal perf_done : cnt_array_t := (others => (others => '0'));
  signal perf_err  : cnt_array_t := (others => (others => '0'));
begin
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      for i in 0 to NUM_CH-1 loop
        perf_done(i) <= (others => '0');
        perf_err(i) <= (others => '0');
      end loop;
    elsif rising_edge(clk) then
      for i in 0 to NUM_CH-1 loop
        if ch_done(i) = '1' then
          perf_done(i) <= perf_done(i) + 1;
        end if;
        if ch_err(i) = '1' then
          perf_err(i) <= perf_err(i) + 1;
        end if;
      end loop;
    end if;
  end process;

  -- pack outputs
  gen_pack: for i in 0 to NUM_CH-1 generate
    perf_done_out((i+1)*32-1 downto i*32) <= std_logic_vector(perf_done(i));
    perf_err_out((i+1)*32-1 downto i*32) <= std_logic_vector(perf_err(i));
  end generate;
end architecture;
