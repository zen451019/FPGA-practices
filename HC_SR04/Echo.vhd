library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Echo is
    port(
        clk       : in  std_logic;
        reset     : in  std_logic;
        ECH       : in  std_logic;
        n_ciclos  : out std_logic_vector(21 downto 0);      -- duración del pulso en ciclos
        done      : out std_logic     -- indica que la medición terminó
    );
end entity;

architecture rtl of Echo is
    signal count         : unsigned(21 downto 0);
    signal ECH_prev      : std_logic := '0';
    signal n_ciclos_reg  : unsigned(21 downto 0);
    signal done_reg      : std_logic := '0';
    signal counting      : std_logic := '0';
begin
    process(clk, reset)
    begin
        if reset = '1' then
            count <= to_unsigned(0, 22);
            ECH_prev <= '0';
            n_ciclos_reg <= to_unsigned(0, 22);
            done_reg <= '0';
            counting <= '0';

        elsif rising_edge(clk) then
            ECH_prev <= ECH;
            done_reg <= '0';  -- se pone en '1' solo un ciclo al final

            -- Detecta flanco de subida: inicio de conteo
            if (ECH = '1' and ECH_prev = '0') then
                counting <= '1';
                count <= to_unsigned(0, 22);

            -- Mientras ECHO esté en alto, cuenta
            elsif counting = '1' and ECH = '1' then
                count <= count + 1;

            -- Detecta flanco de bajada: fin de conteo
            elsif (ECH = '0' and ECH_prev = '1') then
                counting <= '0';
                n_ciclos_reg <= count;
                done_reg <= '1';
            end if;
        end if;
    end process;

    n_ciclos <= std_logic_vector(n_ciclos_reg);
    done <= done_reg;

end architecture;
