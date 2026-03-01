LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART IS
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        DATA : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        DATA_READY : IN STD_LOGIC;
        TX : OUT STD_LOGIC;
        UART_BUSY : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF UART IS
    CONSTANT BAUD_STEP : UNSIGNED(31 DOWNTO 0) := TO_UNSIGNED(158330000, 32);
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

    TYPE STATE_TYPE IS (IDLE, CAPTURE, WAIT_TX_ACCEPT, WAIT_TX_DONE);
    SIGNAL STATE : STATE_TYPE := IDLE;

    SIGNAL DATA_IN : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL TX_START : STD_LOGIC;
    SIGNAL TX_READY : STD_LOGIC;

    SIGNAL DATA_READY_PREV : STD_LOGIC := '0';
    SIGNAL DATA_READY_EDGE : STD_LOGIC := '0'; -- combinatorial

BEGIN
    -- Combinatorial edge detect: avoids 1-cycle delay of registered approach
    DATA_READY_EDGE <= DATA_READY AND NOT DATA_READY_PREV;

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

    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            DATA_IN <= (OTHERS => '0');
            TX_START <= '0';
            UART_BUSY <= '0';
            DATA_READY_PREV <= '0';
        ELSIF RISING_EDGE(CLK) THEN
            DATA_READY_PREV <= DATA_READY; -- only this is registered now
            TX_START <= '0';

            CASE STATE IS
                WHEN IDLE =>
                    -- DATA_READY_EDGE is combinatorial: valid this same cycle
                    IF DATA_READY_EDGE = '1' THEN
                        UART_BUSY <= '1';
                        DATA_IN <= DATA;        -- Captura DATA inmediatamente
                        STATE <= CAPTURE;
                    END IF;

                WHEN CAPTURE =>
                    -- Esperar a que UART_TX esté listo para aceptar
                    IF TX_READY = '1' THEN
                        TX_START <= '1';        -- Pulso de inicio
                        STATE <= WAIT_TX_ACCEPT;
                    END IF;

                WHEN WAIT_TX_ACCEPT =>
                    -- Esperar a que UART_TX tome el byte (TX_READY baja)
                    TX_START <= '0';
                    IF TX_READY = '0' THEN
                        STATE <= WAIT_TX_DONE;
                    END IF;

                WHEN WAIT_TX_DONE =>
                    -- Esperar a que UART_TX termine completamente (TX_READY sube)
                    IF TX_READY = '1' THEN
                        UART_BUSY <= '0';       -- Ahora sí el byte se envió completo
                        STATE <= IDLE;
                    END IF;

                WHEN OTHERS =>
                    STATE <= IDLE;

            END CASE;

        END IF;
    END PROCESS;

END ARCHITECTURE;