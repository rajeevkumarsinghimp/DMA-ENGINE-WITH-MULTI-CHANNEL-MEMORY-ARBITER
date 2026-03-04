-- pulse_sync.vhd
library ieee;
use ieee.std_logic_1164.all;

entity pulse_sync is
  port (
    clk_dst : in  std_logic;
    rst_n   : in  std_logic;
    pulse_in: in  std_logic;
    pulse_out: out std_logic
  );
end entity;

architecture rtl of pulse_sync is
  signal sync1, sync2 : std_logic := '0';
  signal flag : std_logic := '0';
begin
  process(clk_dst, rst_n)
  begin
    if rst_n = '0' then
      sync1 <= '0';
      sync2 <= '0';
      flag <= '0';
      pulse_out <= '0';
    elsif rising_edge(clk_dst) then
      sync1 <= pulse_in;
      sync2 <= sync1;
      if sync2 = '1' and flag = '0' then
        pulse_out <= '1';
        flag <= '1';
      else
        pulse_out <= '0';
      end if;
      if sync2 = '0' then
        flag <= '0';
      end if;
    end if;
  end process;
end architecture;
