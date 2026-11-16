library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scomp_oscillating_timer is
    generic (
        BASE_ADDR    : natural range 0 to 2042 := 16#020#;
        CLOCK_HZ     : positive := 10000000;
        BASE_TICK_HZ : positive := 10
    );
    port (
        clk      : in    std_logic;
        resetn   : in    std_logic;
        io_addr  : in    std_logic_vector(10 downto 0);
        io_read  : in    std_logic;
        io_write : in    std_logic;
        io_data  : inout std_logic_vector(15 downto 0);
        irq      : out   std_logic
    );
end entity;

architecture rtl of scomp_oscillating_timer is
    subtype io_address is std_logic_vector(10 downto 0);
    constant ADDR_INTERVAL : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 0, 11));
    constant ADDR_SPEED    : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 1, 11));
    constant ADDR_MAX      : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 2, 11));
    constant ADDR_CONTROL  : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 3, 11));
    constant ADDR_TIMER    : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 4, 11));
    constant ADDR_COUNT    : io_address := std_logic_vector(to_unsigned(BASE_ADDR + 5, 11));

    constant CTRL_RESTART : natural := 0;
    constant CTRL_UP      : natural := 1;
    constant CTRL_PAUSE   : natural := 2;
    constant CTRL_IRQ     : natural := 3;
    constant CTRL_ACK     : natural := 4;
    constant CTRL_REVERSE : natural := 5;

    constant BASE_PERIOD : natural := CLOCK_HZ / BASE_TICK_HZ;
    signal phase         : natural range 0 to BASE_PERIOD - 1;
    signal speed         : unsigned(15 downto 0);
    signal speed_value   : natural range 0 to 65535;
    signal interval_cfg  : std_logic_vector(15 downto 0);
    signal max_cfg       : unsigned(15 downto 0);
    signal effective_max : unsigned(15 downto 0);
    signal pause_cfg     : std_logic;
    signal irq_enable    : std_logic;

    signal interval_limit : unsigned(15 downto 0);
    signal position       : unsigned(15 downto 0);
    signal completed      : unsigned(15 downto 0);
    signal counting_up    : std_logic;
    signal pending        : std_logic;

    signal write_seen     : std_logic;
    signal write_access   : std_logic;
    signal read_access    : std_logic;
    signal speed_write    : std_logic;
    signal control_write  : std_logic;
    signal restart        : std_logic;
    signal ack            : std_logic;
    signal reverse_dir    : std_logic;
    signal manual_pause   : std_logic;
    signal limit_reached  : std_logic;
    signal stalled        : std_logic;
    signal tick_en        : std_logic;
begin
    assert CLOCK_HZ mod BASE_TICK_HZ = 0 and BASE_PERIOD > 0
        report "CLOCK_HZ must be an integer multiple of BASE_TICK_HZ"
        severity failure;

    irq <= pending and irq_enable;

    write_access  <= '1' when resetn = '1' and io_write = '1' and io_read = '0'
                              and write_seen = '0' else '0';
    read_access   <= '1' when resetn = '1' and io_read = '1' and io_write = '0'
                    else '0';
    speed_write   <= '1' when write_access = '1' and io_addr = ADDR_SPEED else '0';
    control_write <= '1' when write_access = '1' and io_addr = ADDR_CONTROL else '0';

    -- All other peripherals share this bus; release it outside our reads.
    io_data <= std_logic_vector(position)
                   when read_access = '1' and io_addr = ADDR_TIMER else
               std_logic_vector(completed)
                   when read_access = '1' and io_addr = ADDR_COUNT else
               (others => 'Z');

    restart      <= io_data(CTRL_RESTART) when control_write = '1' else '0';
    ack          <= io_data(CTRL_ACK)     when control_write = '1' else '0';
    reverse_dir  <= io_data(CTRL_REVERSE) when control_write = '1' else '0';
    manual_pause <= io_data(CTRL_PAUSE)   when control_write = '1' else pause_cfg;

    effective_max <= unsigned(io_data) when write_access = '1' and io_addr = ADDR_MAX
                     else max_cfg;
    limit_reached <= '1' when resetn = '1' and effective_max /= 0
                              and completed >= effective_max else '0';
    stalled <= manual_pause or limit_reached;

    -- Accumulate SPEED each clock, emitting a step for each BASE_PERIOD.
    -- This yields BASE_TICK_HZ * SPEED on average, capped at one step per clock.
    speed_value <= to_integer(speed) when resetn = '1' else 0;
    tick_en <= '1' when resetn = '1' and stalled = '0' and speed_write = '0'
                        and restart = '0' and reverse_dir = '0'
                        and speed_value >= BASE_PERIOD - phase else '0';

    register_writes : process (clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                write_seen   <= '0';
                interval_cfg <= (others => '0');
                speed        <= to_unsigned(1, speed'length);
                max_cfg      <= (others => '0');
                pause_cfg    <= '0';
                irq_enable   <= '0';
            else
                -- A strobe held across several clocks still performs one OUT.
                write_seen <= io_write;
                if write_access = '1' then
                    if io_addr = ADDR_INTERVAL then
                        interval_cfg <= io_data;
                    elsif io_addr = ADDR_SPEED then
                        speed <= unsigned(io_data);
                    elsif io_addr = ADDR_MAX then
                        max_cfg <= unsigned(io_data);
                    elsif io_addr = ADDR_CONTROL then
                        pause_cfg  <= io_data(CTRL_PAUSE);
                        irq_enable <= io_data(CTRL_IRQ);
                    end if;
                end if;
            end if;
        end if;
    end process;

    step_rate : process (clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' or restart = '1' or speed_write = '1' then
                phase <= 0;
            elsif stalled = '0' and reverse_dir = '0' then
                if speed_value >= BASE_PERIOD then
                    phase <= 0;
                elsif tick_en = '1' then
                    phase <= speed_value - (BASE_PERIOD - phase);
                else
                    phase <= phase + speed_value;
                end if;
            end if;
        end if;
    end process;

    timer_counting : process (clk)
        variable next_position : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                interval_limit <= (others => '0');
                position       <= (others => '0');
                completed      <= (others => '0');
                counting_up    <= '1';
                pending        <= '0';

            elsif restart = '1' then
                interval_limit <= unsigned(interval_cfg);
                completed      <= (others => '0');
                counting_up    <= io_data(CTRL_UP);
                pending        <= '0';

                if io_data(CTRL_UP) = '1' then
                    position <= (others => '0');
                else
                    position <= unsigned(interval_cfg);
                end if;

            else
                if ack = '1' then
                    pending <= '0';
                end if;

                if reverse_dir = '1' then
                    -- At a boundary only the inward direction is valid.
                    if position /= 0 and position /= interval_limit then
                        counting_up <= not counting_up;
                    end if;
                elsif tick_en = '1' and interval_limit /= 0 then
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
