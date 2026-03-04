-- interrupt_ctrl.vhd
library ieee;
use ieee.std_logic_1164.all;

entity interrupt_ctrl is
  generic ( NUM_CH : integer := 4 );
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;
    irq_in : in  std_logic_vector(NUM_CH-1 downto 0);
    irq_out: out std_logic
  );
end entity;

architecture rtl of interrupt_ctrl is
  signal irq_sync1, irq_sync2 : std_logic_vector(NUM_CH-1 downto 0);
begin
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      irq_sync1 <= (others => '0');
      irq_sync2 <= (others => '0');
      irq_out <= '0';
    elsif rising_edge(clk) then
      irq_sync1 <= irq_in;
      irq_sync2 <= irq_sync1;
      if irq_sync2 /= (others => '0') then
        irq_out <= '1';
      else
        irq_out <= '0';
      end if;
    end if;
  end process;
end architecture;
