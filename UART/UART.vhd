LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART IS
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        TX : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF UART IS
    CONSTANT BAUD_STEP : UNSIGNED(31 DOWNTO 0) := TO_UNSIGNED(158330000, 32); -- 115200 baud @ 50MHz
    SIGNAL TICK16 : STD_LOGIC;
    SIGNAL TICK : STD_LOGIC;

    COMPONENT BAUD_GEN
        PORT (
            CLK : IN STD_LOGIC;
            RESET : IN STD_LOGIC;
            BAUD_STEP : IN UNSIGNED(31 DOWNTO 0);

            TICK16 : OUT STD_LOGIC;
            TICK : OUT STD_LOGIC
        );
    END COMPONENT;

    TYPE BYTE_ARRAY IS ARRAY (0 TO 3) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
    --CONSTANT HOLA : BYTE_ARRAY := (X"55", X"55", X"55", X"55"); -- 'U' patron alternante para debug
    CONSTANT HOLA : BYTE_ARRAY := (X"48", X"6F", X"6C", X"61"); -- 'H', 'o', 'l', 'a'
    SIGNAL BYTE_INDEX : INTEGER RANGE 0 TO 3 := 0;
    SIGNAL DATA_IN : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL TX_START : STD_LOGIC := '0';
    SIGNAL TX_READY : STD_LOGIC;

    COMPONENT UART_TX
        PORT (
            CLK : IN STD_LOGIC;
            TICK : IN STD_LOGIC;
            RESET : IN STD_LOGIC;

            DATA_IN : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            TX_START : IN STD_LOGIC;
            TX_READY : OUT STD_LOGIC;
            TX_OUT : OUT STD_LOGIC
        );
    END COMPONENT;

    TYPE STATE_TYPE IS (WAIT_READY, WAIT_ACCEPT);
    SIGNAL STATE : STATE_TYPE := WAIT_READY;

BEGIN

    BAUD_GEN_INST : BAUD_GEN
    PORT MAP(
        CLK => CLK,
        RESET => RESET,
        BAUD_STEP => BAUD_STEP,
        TICK16 => TICK16,
        TICK => TICK
    );

    UART_TX_INST : UART_TX
    PORT MAP(
        CLK => CLK,
        TICK => TICK,
        RESET => RESET,
        DATA_IN => DATA_IN,
        TX_START => TX_START,
        TX_READY => TX_READY,
        TX_OUT => TX
    );

    PROCESS(CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE      <= WAIT_READY;
            BYTE_INDEX <= 0;
            TX_START   <= '0';
            DATA_IN    <= (OTHERS => '0');
        ELSIF RISING_EDGE(CLK) THEN
            TX_START <= '0'; -- Default: pulso de 1 ciclo
            CASE STATE IS
                WHEN WAIT_READY =>
                    -- Esperar que UART_TX este listo, cargar dato y pulsar TX_START
                    IF TX_READY = '1' THEN
                        DATA_IN  <= HOLA(BYTE_INDEX);
                        TX_START <= '1';
                        STATE    <= WAIT_ACCEPT;
                    END IF;

                WHEN WAIT_ACCEPT =>
                    -- Esperar que UART_TX acepte (TX_READY baja)
                    IF TX_READY = '0' THEN
                        IF BYTE_INDEX = 3 THEN
                            BYTE_INDEX <= 0;
                        ELSE
                            BYTE_INDEX <= BYTE_INDEX + 1;
                        END IF;
                        STATE <= WAIT_READY;
                    END IF;

                WHEN OTHERS =>
                    STATE <= WAIT_READY;
            END CASE;
        END IF;
    END PROCESS;

END ARCHITECTURE;