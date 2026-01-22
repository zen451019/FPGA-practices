library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin2bcd is
    port (
        bin_in  : in  std_logic_vector(13 downto 0);
        bcd_out : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of bin2bcd is
begin
    process(bin_in)
        variable bcd      : unsigned(15 downto 0); -- 4 dígitos BCD
        variable bin_temp : unsigned(13 downto 0);
    begin
        -- Inicializar BCD en cero
        bcd := (others => '0');
        bin_temp := unsigned(bin_in);

        for i in 0 to 13 loop
            -- Sumar 3 si el dígito es >= 5
            if bcd(15 downto 12) >= 5 then
                bcd(15 downto 12) := bcd(15 downto 12) + 3;
            end if;
            if bcd(11 downto 8) >= 5 then
                bcd(11 downto 8) := bcd(11 downto 8) + 3;
            end if;
            if bcd(7 downto 4) >= 5 then
                bcd(7 downto 4) := bcd(7 downto 4) + 3;
            end if;
            if bcd(3 downto 0) >= 5 then
                bcd(3 downto 0) := bcd(3 downto 0) + 3;
            end if;

            -- Shift izquierda: añade MSB de bin_temp al LSB de bcd
            bcd := bcd(14 downto 0) & bin_temp(13);
            bin_temp := bin_temp(12 downto 0) & '0';
        end loop;

        bcd_out <= std_logic_vector(bcd);
    end process;
end architecture;