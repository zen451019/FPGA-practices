library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DIG_SEL is
    port(
        clk : in std_logic;
        rst : in std_logic;
        q   : out std_logic_vector(1 downto 0)
    );
end entity;

architecture comp of DIG_SEL is
    signal count : unsigned(1 downto 0);
begin
    process(clk, rst)
    begin
        if rst = '1' then
            count <= (others => '0');
        elsif rising_edge(clk) then
            count <= count + 1;
        end if;
    end process;

    q <= std_logic_vector(count);
end architecture;