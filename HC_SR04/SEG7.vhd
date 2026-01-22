library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SEG7 is
	 port(
		clk 				:	in std_logic;
		rst 				:	in std_logic;
		data				:	in	std_logic_vector(13 downto 0);
		SEG 				:	out	std_logic_vector(6 downto 0);
		DIG_OUT 			:	out	std_logic_vector(3 downto 0);
		dp					:	out	std_logic
	 );
end entity;

architecture comp of SEG7 is

component FREQ_DIV
    port(
        clk : in std_logic;
        rst : in std_logic;
        q   : out std_logic
    );
end component;
for all: FREQ_DIV
use entity work.FREQ_DIV(comp);

component DIG_SEL
    port(
        clk : in std_logic;
        rst : in std_logic;
        q   : out std_logic_vector(1 downto 0)
    );
end component;
for all: DIG_SEL
use entity work.DIG_SEL(comp);


component DISP
	port(
	  segmentos 	:	out	std_logic_vector(6 downto 0);
	  dp				:	out	std_logic;
	  digito_saida :	out	std_logic_vector(3 downto 0);
	  data			:	in	std_logic_vector(15 downto 0);
	  digito 		:	in	std_logic_vector(1 downto 0)
	  
	);
end component;
for all: DISP
use entity work.DISP(comp);

component bin2bcd
    port (
        bin_in  : in  std_logic_vector(13 downto 0);
        bcd_out : out std_logic_vector(15 downto 0)
    );
end component;
for all: bin2bcd
use entity work.bin2bcd(rtl);

signal freq_div_q 	: std_logic;
signal dig_sel_q  	: std_logic_vector(1 downto 0);
signal bin2bcd_out	: std_logic_vector(15 downto 0);

begin

	myFREQ_DIV	:	FREQ_DIV
	port map(
		clk => clk,
		rst => rst,
		q   => freq_div_q
	);

	 myDIG_SEL: DIG_SEL
	 port map(
		  clk => freq_div_q,
		  rst => rst,
		  q   => dig_sel_q
	 );
	 
	 mybin2bcd: bin2bcd
	 port map(
		  bin_in => data,
		  bcd_out   => bin2bcd_out
	 );	 
	 
	 myDISP: DISP
	 port map(
		  data => bin2bcd_out,
		  digito => dig_sel_q,
		  segmentos   => SEG,
		  dp => dp,
		  digito_saida   => DIG_OUT
	 );

end architecture;