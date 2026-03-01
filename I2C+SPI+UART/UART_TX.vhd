LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY UART_TX IS
    PORT (
        CLK : IN STD_LOGIC;
        TICK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;

        DATA_IN : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        TX_START : IN STD_LOGIC;
        TX_READY : OUT STD_LOGIC;
        TX_OUT : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF UART_TX IS
    TYPE MACHINE IS (IDLE, START, DATA, STOP);
    SIGNAL STATE : MACHINE := IDLE;
    SIGNAL BIT_INDEX : INTEGER RANGE 0 TO 7 := 0;
    SIGNAL SHIFT_REG : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL TX_REG : STD_LOGIC := '1'; -- Line idle is high
    SIGNAL TX_START_PREV : STD_LOGIC := '0';
    SIGNAL TX_START_EDGE : STD_LOGIC := '0';
BEGIN
    TX_READY <= '1' WHEN STATE = IDLE ELSE
        '0';
    TX_OUT <= TX_REG;
    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            BIT_INDEX <= 0;
            SHIFT_REG <= (OTHERS => '0');
            TX_REG <= '1'; -- Idle state
        ELSIF RISING_EDGE(CLK) THEN
            TX_START_PREV <= TX_START;
            TX_START_EDGE <= TX_START AND NOT TX_START_PREV; -- Detect rising edge

            IF STATE = IDLE THEN
                IF TX_START_EDGE = '1' THEN
                    SHIFT_REG <= DATA_IN;
                    STATE <= START;
                END IF;
            ELSIF TICK = '1' THEN
                CASE STATE IS

                    WHEN START =>
                        BIT_INDEX <= 0;
                        TX_REG <= '0'; -- Start bit
                        STATE <= DATA;

                    WHEN DATA =>
                        TX_REG <= SHIFT_REG(BIT_INDEX);
                        IF BIT_INDEX = 7 THEN
                            STATE <= STOP;
                        ELSE
                            BIT_INDEX <= BIT_INDEX + 1;
                        END IF;

                    WHEN STOP =>
                        TX_REG <= '1'; -- Stop bit
                        STATE <= IDLE;

                    WHEN OTHERS =>
                        STATE <= IDLE;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;