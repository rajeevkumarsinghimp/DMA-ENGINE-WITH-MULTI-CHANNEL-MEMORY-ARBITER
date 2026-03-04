-- arbiter.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arbiter is
  generic (
    NUM_CH     : integer := 4;
    ADDR_WIDTH : integer := 32;
    DATA_WIDTH : integer := 64
  );
  port (
    clk  : in std_logic;
    rst_n: in std_logic;

    ch_req           : in  std_logic_vector(NUM_CH-1 downto 0);
    ch_type_flat     : in  std_logic_vector(2*NUM_CH-1 downto 0);
    ch_addr_flat     : in  std_logic_vector(NUM_CH*ADDR_WIDTH-1 downto 0);
    ch_burst_len_flat: in  std_logic_vector(NUM_CH*16-1 downto 0);
    ch_wdata_flat    : in  std_logic_vector(NUM_CH*DATA_WIDTH-1 downto 0);
    ch_wlast_flat    : in  std_logic_vector(NUM_CH-1 downto 0);

    ch_grant         : out std_logic_vector(NUM_CH-1 downto 0);
    ch_done          : out std_logic_vector(NUM_CH-1 downto 0);
    ch_error         : out std_logic_vector(NUM_CH-1 downto 0);

    -- Simplified AXI master ties-through
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

architecture rtl of arbiter is
  type state_t is (S_IDLE, S_REQ, S_XFER, S_WAIT_RESP);
  signal state, next_state : state_t;

  signal ptr  : integer range 0 to NUM_CH-1 := 0;
  signal cur_ch : integer range 0 to NUM_CH-1 := 0;

  -- outputs default
begin

  process(clk, rst_n)
  begin
    if rst_n = '0' then
      state <= S_IDLE;
      ptr <= 0;
      ch_grant <= (others => '0');
      ch_done <= (others => '0');
      ch_error <= (others => '0');
      m_axil_awvalid <= '0';
      m_axil_wvalid <= '0';
      m_axil_arvalid <= '0';
      m_axil_rready <= '0';
      m_axil_bready <= '0';
    elsif rising_edge(clk) then
      state <= next_state;
      -- clear pulses
      ch_done <= (others => '0');
      ch_error <= (others => '0');
    end if;
  end process;

  -- combinational logic for arbitration (simplified)
  process(state, ch_req, m_axil_arready, m_axil_awready, m_axil_wready, m_axil_rvalid, m_axil_rlast, m_axil_bvalid)
    variable found : boolean;
    variable c     : integer;
  begin
    -- default outputs
    m_axil_awvalid <= '0';
    m_axil_wvalid  <= '0';
    m_axil_arvalid <= '0';
    m_axil_rready  <= '0';
    m_axil_bready  <= '0';
    ch_grant <= (others => '0');
    next_state <= state;

    case state is
      when S_IDLE =>
        found := false;
        for i in 0 to NUM_CH-1 loop
          c := (ptr + i) mod NUM_CH;
          if ch_req(c) = '1' then
            cur_ch <= c;
            found := true;
            exit;
          end if;
        end loop;
        if found then
          next_state <= S_REQ;
        end if;

      when S_REQ =>
        ch_grant(cur_ch) <= '1';
        -- extract type for cur_ch
        if ch_type_flat((cur_ch*2)+1 downto cur_ch*2) = "00" then
          -- read
          m_axil_araddr <= ch_addr_flat((cur_ch*ADDR_WIDTH)+ADDR_WIDTH-1 downto cur_ch*ADDR_WIDTH);
          m_axil_arlen  <= ch_burst_len_flat((cur_ch*16)+15 downto cur_ch*16) - x"0001";
          m_axil_arsize <= std_logic_vector(to_unsigned(integer(log2(real(DATA_WIDTH/8))), 3));
          m_axil_arburst <= "01";
          m_axil_arvalid <= '1';
          if m_axil_arready = '1' then
            m_axil_rready <= '1';
            next_state <= S_XFER;
          end if;
        else
          -- write
          m_axil_awaddr <= ch_addr_flat((cur_ch*ADDR_WIDTH)+ADDR_WIDTH-1 downto cur_ch*ADDR_WIDTH);
          m_axil_awlen  <= ch_burst_len_flat((cur_ch*16)+15 downto cur_ch*16) - x"0001";
          m_axil_awsize <= std_logic_vector(to_unsigned(integer(log2(real(DATA_WIDTH/8))), 3));
          m_axil_awburst <= "01";
          m_axil_awvalid <= '1';
          if m_axil_awready = '1' then
            m_axil_wdata <= ch_wdata_flat((cur_ch*DATA_WIDTH)+DATA_WIDTH-1 downto cur_ch*DATA_WIDTH);
            m_axil_wstrb <= (others => '1');
            m_axil_wlast <= ch_wlast_flat(cur_ch);
            m_axil_wvalid <= '1';
            if m_axil_wready = '1' then
              m_axil_bready <= '1';
              next_state <= S_WAIT_RESP;
            end if;
          end if;
        end if;

      when S_XFER =>
        m_axil_rready <= '1';
        if m_axil_rvalid = '1' and m_axil_rlast = '1' then
          ch_done(cur_ch) <= '1';
          ptr <= (cur_ch + 1) mod NUM_CH;
          next_state <= S_IDLE;
        end if;

      when S_WAIT_RESP =>
        m_axil_bready <= '1';
        if m_axil_bvalid = '1' then
          if m_axil_bresp = "00" then
            ch_done(cur_ch) <= '1';
          else
            ch_error(cur_ch) <= '1';
          end if;
          ptr <= (cur_ch + 1) mod NUM_CH;
          next_state <= S_IDLE;
        end if;
    end case;
  end process;

end architecture;
