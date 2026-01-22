library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Trig is
	port(
		clk		:		in		std_logic;
		reset 	:		in		std_logic;
		triger 	: 		in  	std_logic;	
		done   	:		out 	std_logic;
		q			:		out	std_logic

	);
end entity;

architecture comp of Trig is
	signal count			:	unsigned(8 downto 0);
	signal system_active	: 	std_logic := '0';
begin
	process(clk,reset)
	begin
		if reset = '1' then
			count 			<= to_unsigned(0, 9);
			system_active 	<= '0';
			q					<=	'0';
			done				<=	'0';
			
		elsif rising_edge(clk) then
			if triger = '1' and system_active = '0' then
				count 			<= to_unsigned(0, 9);
				system_active 	<= '1';
				q					<=	'1';
				done				<=	'0';
			
			elsif system_active = '1' then		
				if count < 500 then
					count 			<= count + 1;
					q					<=	'1';
					
				else
					system_active 	<= '0';
					q					<=	'0';
					done				<=	'1';
					
				end if;			
			else
				done				<=	'0';
						
			end if;
		end if;	
	end process;
end architecture;