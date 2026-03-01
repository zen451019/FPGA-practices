LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY BAUD_GEN IS
    PORT (
        CLK       : IN  STD_LOGIC;
        RESET     : IN  STD_LOGIC;
        BAUD_STEP : IN  UNSIGNED(31 DOWNTO 0);

        TICK16    : OUT STD_LOGIC;
        TICK      : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE RTL OF BAUD_GEN IS

    SIGNAL ACC        : UNSIGNED(31 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SUM        : UNSIGNED(32 DOWNTO 0);

    SIGNAL DIV16_CNT  : UNSIGNED(3 DOWNTO 0) := (OTHERS => '0');

BEGIN

    -- SUMA CON CARRY (OVERFLOW REAL)
    SUM <= ('0' & ACC) + ('0' & BAUD_STEP);

    PROCESS(CLK)
    BEGIN
        IF RISING_EDGE(CLK) THEN

            IF RESET = '0' THEN
                ACC       <= (OTHERS => '0');
                DIV16_CNT <= (OTHERS => '0');
                TICK16    <= '0';
                TICK      <= '0';

            ELSE

                -- ACTUALIZAR ACUMULADOR
                ACC <= SUM(31 DOWNTO 0);

                -- OVERFLOW = CARRY OUT
                TICK16 <= SUM(32);

                -- DIVIDIR POR 16
                IF SUM(32) = '1' THEN
                    IF DIV16_CNT = 15 THEN
                        DIV16_CNT <= (OTHERS => '0');
                        TICK <= '1';
                    ELSE
                        DIV16_CNT <= DIV16_CNT + 1;
                        TICK <= '0';
                    END IF;
                ELSE
                    TICK <= '0';
                END IF;

            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;