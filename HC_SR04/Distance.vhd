library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Distance is
    port(
        n_ciclos : in std_logic_vector(21 downto 0);
        salida_d : out std_logic_vector(13 downto 0)
    );
end entity;

architecture comp of Distance is
    constant M : unsigned(9 downto 0) := to_unsigned(899, 10);
    signal ciclos : unsigned(21 downto 0);
    signal temp : unsigned(30 downto 0);
    signal distancia : unsigned(13 downto 0);
begin
    -- Extiende n_ciclos a 31 bits
    ciclos <= unsigned(n_ciclos);
    temp <= resize(ciclos * M, 31);
    distancia <= resize(temp srl 18, 14);

	salida_d <= std_logic_vector(distancia);
end architecture;