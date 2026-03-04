-- dma_channel.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dma_channel is
  generic (
    ADDR_WIDTH : integer := 32;
    DATA_WIDTH : integer := 64;
    DESC_WIDTH : integer := 128
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    -- control
    start     : in  std_logic;
    desc_base : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    reset_ch  : in  std_logic;
    -- arbiter request interface
    req       : out std_logic;
    type      : out std_logic_vector(1 downto 0);
    addr      : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    burst_len : out std_logic_vector(15 downto 0);
    wdata     : out std_logic_vector(DATA_WIDTH-1 downto 0);
    wlast     : out std_logic;
    grant     : in  std_logic;
    done      : in  std_logic;
    error     : in  std_logic;
    -- status
    status_out: out std_logic_vector(31 downto 0);
    -- irq
    irq_out   : out std_logic
  );
end entity;

architecture rtl of dma_channel is
  type state_t is (IDLE, FETCH_DESC, START_XFER, WAIT_DONE, COMPLETE, ERROR);
  signal state, next_state : state_t;

  signal cur_desc_addr : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal cur_desc      : std_logic_vector(DESC_WIDTH-1 downto 0);
  signal desc_valid    : std_logic;

  signal xfer_len      : unsigned(31 downto 0);
  signal xfer_addr     : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal next_desc     : std_logic_vector(ADDR_WIDTH-1 downto 0);

  signal bytes_remaining : unsigned(31 downto 0);
begin

  -- Sequential: state and outputs
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      state <= IDLE;
      req <= '0';
      type <= (others => '0');
      addr <= (others => '0');
      burst_len <= (others => '0');
      wdata <= (others => '0');
      wlast <= '0';
      status_out <= (others => '0');
      irq_out <= '0';
      cur_desc_addr <= (others => '0');
      cur_desc <= (others => '0');
      desc_valid <= '0';
      xfer_len <= (others => '0');
      xfer_addr <= (others => '0');
      next_desc <= (others => '0');
      bytes_remaining <= (others => '0');
    elsif rising_edge(clk) then
      state <= next_state;

      if grant = '1' then
        req <= '0';
      end if;

      if state = COMPLETE then
        status_out <= std_logic_vector(unsigned(status_out) + 1);
        irq_out <= '1';
      else
        irq_out <= '0';
      end if;

      if reset_ch = '1' then
        state <= IDLE;
        cur_desc_addr <= (others => '0');
        desc_valid <= '0';
        bytes_remaining <= (others => '0');
      end if;
    end if;
  end process;

  -- Combinational next-state
  process(state, start, grant, done, error, cur_desc)
  begin
    next_state <= state;
    case state is
      when IDLE =>
        if start = '1' then
          cur_desc_addr <= desc_base;
          next_state <= FETCH_DESC;
        end if;
      when FETCH_DESC =>
        req <= '1';
        type <= "00";
        addr <= cur_desc_addr;
        burst_len <= std_logic_vector(to_unsigned((DESC_WIDTH/8) / (DATA_WIDTH/8), 16));
        if grant = '1' and done = '1' then
          desc_valid <= '1';
          xfer_len <= unsigned(cur_desc(95 downto 64));
          xfer_addr <= cur_desc(63 downto 32);
          next_desc <= cur_desc(31 downto 0);
          bytes_remaining <= unsigned(cur_desc(95 downto 64));
          next_state <= START_XFER;
        end if;
      when START_XFER =>
        if xfer_len = 0 then
          if next_desc /= (others => '0') then
            cur_desc_addr <= next_desc;
            next_state <= FETCH_DESC;
          else
            next_state <= COMPLETE;
          end if;
        else
          type <= "00";
          addr <= xfer_addr;
          burst_len <= std_logic_vector(to_unsigned((to_integer(xfer_len) + (DATA_WIDTH/8 - 1)) / (DATA_WIDTH/8), 16));
          req <= '1';
          if grant = '1' then
            next_state <= WAIT_DONE;
          end if;
        end if;
      when WAIT_DONE =>
        if done = '1' then
          if next_desc /= (others => '0') then
            cur_desc_addr <= next_desc;
            next_state <= FETCH_DESC;
          else
            next_state <= COMPLETE;
          end if;
        elsif error = '1' then
          next_state <= ERROR;
        end if;
      when COMPLETE =>
        next_state <= IDLE;
      when ERROR =>
        next_state <= ERROR;
    end case;
  end process;

end architecture;
