library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FREQ_DIV is
    port(
        clk : in std_logic;
        rst : in std_logic;
        q   : out std_logic
    );
end entity;

architecture comp of FREQ_DIV is
    signal count : unsigned(16 downto 0);
    constant MAX_COUNT : unsigned(16 downto 0) := to_unsigned(100_000, 17); -- 2 ms
begin
    process(clk, rst)
    begin
        if rst = '1' then
            count <= (others => '0');
            q <= '0';
        elsif rising_edge(clk) then
            if count = MAX_COUNT then
                count <= (others => '0');
                q <= '1';         -- pulso alto un clock
            else
                count <= count + 1;
                q <= '0';         -- bajo el resto del tiempo
            end if;
        end if;
    end process;
end architecture;