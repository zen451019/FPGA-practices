LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY LCD_TEST IS
    PORT (
        CLK : IN STD_LOGIC;
        RST : IN STD_LOGIC;
        LCD_RS : OUT STD_LOGIC;
        LCD_EN : OUT STD_LOGIC;
        LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE COMP OF LCD_TEST IS

    -- Declaración del componente LCD_DISPLAY
    COMPONENT LCD_DISPLAY
        GENERIC (
            LCD_CHARS : POSITIVE := 16
        );
        PORT (
            CLK : IN STD_LOGIC;
            RST : IN STD_LOGIC;
            STRING_LINE_1 : IN STRING(1 TO LCD_CHARS);
            STRING_LINE_2 : IN STRING(1 TO LCD_CHARS);
            LCD_RS : OUT STD_LOGIC;
            LCD_EN : OUT STD_LOGIC;
            LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)

        );
    END COMPONENT;

    -- Señales para los contadores numéricos
    SIGNAL COUNT_UP   : INTEGER RANGE 0 TO 9999 := 0;
    SIGNAL COUNT_DOWN : INTEGER RANGE 0 TO 9999 := 9999;
    
    -- Divisor de frecuencia interno para controlar la velocidad (sin añadir otro reloj externo)
    -- Si tu reloj es de 50MHz, 5,000,000 ciclos = 0.1 segundos (bastante rápido)
    -- Puedes aumentar este número para hacerlo más lento.
    SIGNAL TICK_COUNTER : INTEGER RANGE 0 TO 5000000 := 0; 

    -- Definición de los strings (se actualizarán dinámicamente)
    SIGNAL S_LINE_1 : STRING(1 TO 16) := "UP:   0000      ";
    SIGNAL S_LINE_2 : STRING(1 TO 16) := "DOWN: 9999      ";

    -- Función auxiliar para convertir entero a string de 4 dígitos
    FUNCTION INT_TO_STR4(val : INTEGER) RETURN STRING IS
        VARIABLE temp_str : STRING(1 TO 4);
        VARIABLE temp_val : INTEGER;
    BEGIN
        temp_val := val;
        -- Miles
        temp_str(1) := CHARACTER'VAL(48 + (temp_val / 1000));
        temp_val := temp_val MOD 1000;
        -- Centenas
        temp_str(2) := CHARACTER'VAL(48 + (temp_val / 100));
        temp_val := temp_val MOD 100;
        -- Decenas
        temp_str(3) := CHARACTER'VAL(48 + (temp_val / 10));
        temp_val := temp_val MOD 10;
        -- Unidades
        temp_str(4) := CHARACTER'VAL(48 + temp_val);
        RETURN temp_str;
    END FUNCTION;

BEGIN

    -- Proceso principal: Controla la velocidad y actualiza los contadores
    PROCESS(CLK, RST)
    BEGIN
        IF RST = '1' THEN
            TICK_COUNTER <= 0;
            COUNT_UP <= 0;
            COUNT_DOWN <= 9999;
        ELSIF RISING_EDGE(CLK) THEN
            -- Lógica de división de tiempo
            IF TICK_COUNTER = 5000000 THEN -- Ajusta este valor para cambiar la velocidad
                TICK_COUNTER <= 0;
                
                -- Actualizar Contador Ascendente
                IF COUNT_UP = 9999 THEN
                    COUNT_UP <= 0;
                ELSE
                    COUNT_UP <= COUNT_UP + 1;
                END IF;

                -- Actualizar Contador Descendente
                IF COUNT_DOWN = 0 THEN
                    COUNT_DOWN <= 9999;
                ELSE
                    COUNT_DOWN <= COUNT_DOWN - 1;
                END IF;
            ELSE
                TICK_COUNTER <= TICK_COUNTER + 1;
            END IF;
        END IF;
    END PROCESS;

    -- Asignación concurrente: Convierte los números a texto y los pone en las señales del LCD
    S_LINE_1 <= "UP:   " & INT_TO_STR4(COUNT_UP) & "      ";
    S_LINE_2 <= "DOWN: " & INT_TO_STR4(COUNT_DOWN) & "      ";

    -- Instancia del controlador LCD
    U_LCD : LCD_DISPLAY
    GENERIC MAP(
        LCD_CHARS => 16
    )
    PORT MAP(
        CLK           => CLK,
        RST           => RST,
        STRING_LINE_1 => S_LINE_1,
        STRING_LINE_2 => S_LINE_2,
        LCD_RS        => LCD_RS,
        LCD_EN        => LCD_EN,
        LCD_DATA      => LCD_DATA
    );

END ARCHITECTURE;