-- desc_fetcher.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity desc_fetcher is
  generic (
    NUM_CHANNELS : integer := 4;
    ADDR_WIDTH   : integer := 32;
    DATA_WIDTH   : integer := 64;
    FIFO_DEPTH   : integer := 4  -- small FIFO depth
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;

    -- Requests from channels (one-hot)
    desc_req   : in  std_logic_vector(NUM_CHANNELS-1 downto 0);
    desc_ack   : out std_logic_vector(NUM_CHANNELS-1 downto 0);
    desc_addr  : in  std_logic_vector(NUM_CHANNELS*ADDR_WIDTH-1 downto 0);
    cur_desc   : out std_logic_vector(NUM_CHANNELS*128-1 downto 0); -- 128-bit per channel
    cur_valid  : out std_logic_vector(NUM_CHANNELS-1 downto 0);

    -- AXI read master connection (simple)
    m_axi_araddr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    m_axi_arlen   : out std_logic_vector(7 downto 0);
    m_axi_arsize  : out std_logic_vector(2 downto 0);
    m_axi_arburst : out std_logic_vector(1 downto 0);
    m_axi_arvalid : out std_logic;
    m_axi_arready : in  std_logic;
    m_axi_rdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axi_rvalid  : in  std_logic;
    m_axi_rlast   : in  std_logic;
    m_axi_rready  : out std_logic
  );
end entity;

architecture rtl of desc_fetcher is
  -- internal state
  type df_state_t is (DF_IDLE, DF_AR, DF_R);
  signal state, next_state : df_state_t;

  constant DESC_WORDS : integer := 128 / DATA_WIDTH;

  signal active_ch : integer range 0 to NUM_CHANNELS-1 := 0;
  signal beat_count : integer range 0 to DESC_WORDS := 0;

  -- simple single-entry buffers: for clarity we store descriptor into shared arrays
  signal cur_desc_int : std_logic_vector(NUM_CHANNELS*128-1 downto 0) := (others => '0');
  signal cur_valid_int: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others => '0');
  signal desc_ack_int : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others => '0');

begin

  -- outputs
  cur_desc  <= cur_desc_int;
  cur_valid <= cur_valid_int;
  desc_ack  <= desc_ack_int;

  -- FSM
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      state <= DF_IDLE;
      m_axi_arvalid <= '0';
      m_axi_rready <= '0';
      beat_count <= 0;
      cur_valid_int <= (others => '0');
      desc_ack_int <= (others => '0');
      m_axi_araddr <= (others => '0');
      m_axi_arlen <= std_logic_vector(to_unsigned(DESC_WORDS-1, 8));
      m_axi_arsize <= std_logic_vector(to_unsigned(integer(log2(real(DATA_WIDTH/8))), 3));
      m_axi_arburst <= "01";
    elsif rising_edge(clk) then
      state <= next_state;
      case state is
        when DF_IDLE =>
          cur_valid_int <= (others => '0');
          desc_ack_int <= (others => '0');
          if desc_req /= (others => '0') then
            -- pick lowest set bit (round-robin or priority can be added)
            for i in 0 to NUM_CHANNELS-1 loop
              if desc_req(i) = '1' then
                active_ch <= i;
                exit;
              end if;
            end loop;
            m_axi_araddr <= desc_addr((active_ch+1)*ADDR_WIDTH-1 downto active_ch*ADDR_WIDTH);
            m_axi_arvalid <= '1';
            m_axi_arlen <= std_logic_vector(to_unsigned(DESC_WORDS-1, 8));
            m_axi_arburst <= "01";
            m_axi_arsize <= std_logic_vector(to_unsigned(integer(log2(real(DATA_WIDTH/8))), 3));
            next_state <= DF_AR;
          else
            m_axi_arvalid <= '0';
            next_state <= DF_IDLE;
          end if;
        when DF_AR =>
          if m_axi_arready = '1' then
            m_axi_arvalid <= '0';
            m_axi_rready <= '1';
            beat_count <= 0;
            next_state <= DF_R;
          else
            next_state <= DF_AR;
          end if;
        when DF_R =>
          if m_axi_rvalid = '1' then
            -- append beat into descriptor buffer for active_ch
            -- compute index range to insert
            variable base_bit : integer := active_ch*128 + beat_count*DATA_WIDTH;
            cur_desc_int(base_bit + DATA_WIDTH -1 downto base_bit) <= m_axi_rdata;
            beat_count <= beat_count + 1;
            if m_axi_rlast = '1' or beat_count+1 = DESC_WORDS then
              -- descriptor complete
              cur_valid_int(active_ch) <= '1';
              desc_ack_int(active_ch) <= '1';
              m_axi_rready <= '0';
              next_state <= DF_IDLE;
            else
              next_state <= DF_R;
            end if;
          else
            next_state <= DF_R;
          end if;
      end case;
    end if;
  end process;

end architecture;
