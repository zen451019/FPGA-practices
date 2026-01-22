library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MS_HCSR04 is
  port(
    clk         : in  std_logic;
    echo_IN     : in  std_logic;
    trigger_OUT : out std_logic;
    distancia   : out std_logic_vector(13 downto 0)
  );
end entity;

architecture comp of MS_HCSR04 is

  --------------------------------------------------------------------
  -- Tipos y señales internas
  --------------------------------------------------------------------
  type state_type is (IDLE, TRIGG, WAIT_ECHO_HIGH, MEASURE_ECHO, DONE);
  signal estado_actual, estado_siguiente : state_type;

  signal contador     : unsigned(21 downto 0) := (others => '0');
  signal n_ciclox     : std_logic_vector(21 downto 0);
  signal medida       : std_logic_vector(13 downto 0);

  -- Señales del módulo TRIG
  signal Trig_done    : std_logic := '0';
  signal Trig_Trig    : std_logic := '0'; 
  signal Trig_RST     : std_logic := '0';

  -- Señales del módulo ECHO
  signal Echo_done    : std_logic := '0';
  signal Echo_reg     : std_logic_vector(21 downto 0) := (others => '0'); 
  signal Echo_RST     : std_logic := '0';

  --------------------------------------------------------------------
  -- Componentes
  --------------------------------------------------------------------
  component Trig
    port(
      clk    : in  std_logic;
      reset  : in  std_logic;
      triger : in  std_logic;	
      done   : out std_logic;
      q      : out std_logic
    );
  end component;
  for all : Trig use entity work.Trig(comp);  

  component Echo
    port(
      clk      : in  std_logic;
      reset    : in  std_logic;
      ECH      : in  std_logic;
      n_ciclos : out std_logic_vector(21 downto 0);
      done     : out std_logic
    );
  end component;
  for all : Echo use entity work.Echo(rtl);  

  component Distance
    port(
      n_ciclos : in  std_logic_vector(21 downto 0);
      salida_d : out std_logic_vector(13 downto 0)
    );
  end component;
  for all : Distance use entity work.Distance(comp); 

begin

  --------------------------------------------------------------------
  -- Instanciación de módulos
  --------------------------------------------------------------------
  myTrig : Trig
    port map(
      clk     => clk,
      reset   => Trig_RST,
      triger  => Trig_Trig,
      done    => Trig_done,
      q       => trigger_OUT
    );
	
  myEcho : Echo
    port map(
      clk      => clk,
      reset    => Echo_RST,
      ECH      => echo_IN,
      n_ciclos => Echo_reg,
      done     => Echo_done
    );
	
  myDistance : Distance
    port map(
      n_ciclos => n_ciclox,
      salida_d => medida
    );

  --------------------------------------------------------------------
  -- Registro de estado
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      estado_actual <= estado_siguiente;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Máquina de estados principal
  --------------------------------------------------------------------
  process(estado_actual)
  begin
    if rising_edge(clk) then


      case estado_actual is

        ----------------------------------------------------------------
        -- IDLE: Espera un tiempo (~60ms) antes de iniciar un nuevo TRIG
        ----------------------------------------------------------------
        when IDLE =>
          contador <= contador + 1;

          if contador = 3_000_000 then   -- ~60 ms a 50 MHz
            contador <= (others => '0');
            estado_siguiente <= TRIGG;
          else
            estado_siguiente <= IDLE;
          end if;

        ----------------------------------------------------------------
        -- TRIGG: Activa el módulo TRIG para generar el pulso de disparo
        ----------------------------------------------------------------
        when TRIGG =>
          Trig_Trig <= '1';  -- genera el pulso
          
          if Trig_done = '1' then
            -- Espera un ciclo más antes de resetear TRIG
            estado_siguiente <= WAIT_ECHO_HIGH;
          else
            estado_siguiente <= TRIGG;
          end if;

        ----------------------------------------------------------------
        -- WAIT_ECHO_HIGH: Espera a que el pin ECHO suba (inicio del eco)
        ----------------------------------------------------------------
        when WAIT_ECHO_HIGH =>
          if echo_IN = '1' then
            estado_siguiente <= MEASURE_ECHO;
          else
            estado_siguiente <= WAIT_ECHO_HIGH;
          end if;

        ----------------------------------------------------------------
        -- MEASURE_ECHO: Espera a que el módulo ECHO termine su conteo
        ----------------------------------------------------------------
        when MEASURE_ECHO =>
          if Echo_done = '0' then
            estado_siguiente <= MEASURE_ECHO;
          else
            n_ciclox <= Echo_reg;   -- guarda el valor antes del reset
            Echo_RST <= '1';        -- reinicia módulo Echo
            estado_siguiente <= DONE;
          end if;

        ----------------------------------------------------------------
        -- DONE: Convierte a distancia, resetea y vuelve al IDLE
        ----------------------------------------------------------------
        when DONE =>
          distancia <= medida;  -- salida final
          Trig_RST  <= '1';     -- reinicia TRIG
          Echo_RST  <= '0';     -- ya quedó listo para próxima medición
          estado_siguiente <= IDLE;

      end case;

    end if;
  end process;

end architecture;
