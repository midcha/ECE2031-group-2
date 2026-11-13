library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity periodic_oscillating_timer is
    port (
        clk            : in  std_logic;
        reset          : in  std_logic;
        tick_en        : in  std_logic;  -- One clk-wide pulse per timer step
        load_config    : in  std_logic;  -- Latch settings and restart
        interval_in    : in  std_logic_vector(15 downto 0);
        start_up       : in  std_logic;  -- '1' starts at 0, '0' at interval
        paused         : in  std_logic;
        clear_pending  : in  std_logic;
        irq_enable     : in  std_logic;

        timer_value    : out std_logic_vector(15 downto 0);
        interval_count : out std_logic_vector(15 downto 0);
        event_pending  : out std_logic;
        irq            : out std_logic
    );
end entity;

architecture rtl of periodic_oscillating_timer is
    signal interval_limit : unsigned(15 downto 0);
    signal position       : unsigned(15 downto 0);
    signal completed      : unsigned(15 downto 0);
    signal counting_up    : std_logic;
    signal pending        : std_logic;
begin
    timer_value    <= std_logic_vector(position);
    interval_count <= std_logic_vector(completed);
    event_pending  <= pending;
    irq            <= pending and irq_enable;

    process (clk)
        variable next_position : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                interval_limit <= (others => '0');
                position       <= (others => '0');
                completed      <= (others => '0');
                counting_up    <= '1';
                pending        <= '0';

            elsif load_config = '1' then
                interval_limit <= unsigned(interval_in);
                completed      <= (others => '0');
                counting_up    <= start_up;
                pending        <= '0';

                if start_up = '1' then
                    position <= (others => '0');
                else
                    position <= unsigned(interval_in);
                end if;

            else
                if clear_pending = '1' then
                    pending <= '0';
                end if;

                if tick_en = '1' and paused = '0' and interval_limit /= 0 then
                    if counting_up = '1' then
                        next_position := position + 1;
                    else
                        next_position := position - 1;
                    end if;

                    position <= next_position;

                    if next_position = 0 or next_position = interval_limit then
                        counting_up <= not counting_up;
                        completed   <= completed + 1;
                        pending     <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;