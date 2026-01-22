library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity HC_SR04 is
   port (
	clk         : in  std_logic;
	echo_IN     : in  std_logic;
	trigger_OUT 	:	out std_logic;
	SEG 				:	out	std_logic_vector(6 downto 0);
	DIG_OUT 			:	out	std_logic_vector(3 downto 0);
	dp					:	out	std_logic
   );
end entity HC_SR04;

architecture comp of HC_SR04 is

	signal medida			:	std_logic_vector(13 downto 0);
	signal reset			:	std_logic;

	component MS_HCSR04
	port(
	 clk         : in  std_logic;
	 echo_IN     : in  std_logic;
	 trigger_OUT : out std_logic;
	 distancia   : out std_logic_vector(13 downto 0)
	);
	end component;
	for all : MS_HCSR04 use entity work.MS_HCSR04(comp);

	
	component SEG7
	port(
		clk 				:	in std_logic;
		rst 				:	in std_logic;
		data				:	in	std_logic_vector(13 downto 0);
		SEG 				:	out	std_logic_vector(6 downto 0);
		DIG_OUT 			:	out	std_logic_vector(3 downto 0);
		dp					:	out	std_logic
	 );
	end component;
	for all : SEG7 use entity work.SEG7(comp);

begin

  myMS_HCSR04 : MS_HCSR04
    port map(
      clk     => clk,
      echo_IN   => echo_IN,
      trigger_OUT  => trigger_OUT,
      distancia    => medida
    );
	 
  mySEG7 : SEG7
    port map(
      clk		=> clk,
		rst		=>	reset,
      data		=> medida,
      SEG		=> SEG,
      DIG_OUT	=> DIG_OUT,
		dp			=>	dp
    );

end architecture;
