library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DISP is
port(
  segmentos 	:	out	std_logic_vector(6 downto 0);
  dp				:	out	std_logic;
  digito_saida :	out std_logic_vector(3 downto 0);
  data			:	in	std_logic_vector(15 downto 0);
  digito 		:	in std_logic_vector(1 downto 0)
  
);
end entity;

architecture comp of DISP is
  signal selec		:	std_logic_vector(3 downto 0);
 
begin
  with digito select
		selec	 <= 	data(3 downto 0) 		when "00",
					   data(7 downto 4) 		when "01",
						data(11 downto 8) 	when "10",
						data(15 downto 12) 	when "11",
						"0000"			  		when others;	

	with digito select
		digito_saida	<= 	"1110" when "00",
									"1101" when "01",
									"1011" when "10",
									"0111" when "11",
									"1111"		when others;		
	
	with selec select
		 segmentos <= "1000000" when "0000",  -- 0
						  "1111001" when "0001",  -- 1
						  "0100100" when "0010",  -- 2
						  "0110000" when "0011",  -- 3
						  "0011001" when "0100",  -- 4
						  "0010010" when "0101",  -- 5
						  "0000010" when "0110",  -- 6
						  "1111000" when "0111",  -- 7
						  "0000000" when "1000",  -- 8
						  "0010000" when "1001",  -- 9
						  "1111111" when others;  -- Apagado
	dp <= '1';			
end architecture;