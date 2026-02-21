 LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY TIMER IS
    PORT (
        CLK : IN STD_LOGIC;
        RST : IN STD_LOGIC;
        FAST_MODE : IN STD_LOGIC;
        ENABLE : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF TIMER IS
    SIGNAL COUNT : INTEGER RANGE 0 TO 100000 := 0;
    SIGNAL PREV_FAST_MODE : STD_LOGIC := '0';

    CONSTANT MAX_SLOW : INTEGER := 100000; -- 2ms
    CONSTANT MAX_FAST : INTEGER := 2500; -- 50us
    SIGNAL MAX_COUNT : INTEGER := MAX_SLOW;
BEGIN

    PROCESS (CLK, RST)
    BEGIN
        IF RST = '0' THEN
            COUNT <= 0;
            ENABLE <= '0';
            MAX_COUNT <= MAX_SLOW;
            PREV_FAST_MODE <= '0';

        ELSIF RISING_EDGE(CLK) THEN
            ENABLE <= '0';
            IF FAST_MODE /= PREV_FAST_MODE THEN
                PREV_FAST_MODE <= FAST_MODE;
                COUNT <= 0;
                IF FAST_MODE = '1' THEN
                    MAX_COUNT <= MAX_FAST;
                ELSE
                    MAX_COUNT <= MAX_SLOW;
                END IF;
            ELSIF COUNT >= MAX_COUNT THEN
                COUNT <= 0;
                ENABLE <= '1';
            ELSE
                COUNT <= COUNT + 1;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;