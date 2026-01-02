LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY TIMER IS
    PORT (
        CLK : IN STD_LOGIC;
        RST : IN STD_LOGIC;
        FAST_MODE : IN STD_LOGIC; -- Nuevo puerto de control
        Q : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF TIMER IS

    SIGNAL COUNT : INTEGER RANGE 0 TO 100000 := 0;
    SIGNAL TRIGGER : STD_LOGIC := '0';

    -- Lento: 100,000 * 20ns = 2ms (Periodo completo 4ms, 250Hz) -> Para INIT
    CONSTANT MAX_SLOW : INTEGER := 100000;
    -- Rápido: 2,500 * 20ns = 50us (Periodo completo 100us, 10kHz) -> Para Escritura
    CONSTANT MAX_FAST : INTEGER := 2500;
    
    SIGNAL MAX_COUNT : INTEGER;

BEGIN
    
    MAX_COUNT <= MAX_FAST WHEN FAST_MODE = '1' ELSE MAX_SLOW;

    Q <= TRIGGER;

    PROCESS (CLK, RST)
    BEGIN
        IF RST = '1' THEN
            COUNT <= 0;
            TRIGGER <= '0';

        ELSIF RISING_EDGE(CLK) THEN
            -- Usamos >= para evitar errores al cambiar dinámicamente de límite alto a bajo
            IF COUNT >= MAX_COUNT THEN
                COUNT <= 0;
                TRIGGER <= NOT TRIGGER;
            ELSE
                COUNT <= COUNT + 1;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;