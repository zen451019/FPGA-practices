LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE LCD_CONTROL IS
    PROCEDURE LCD_INIT(
        N : NATURAL RANGE 0 TO 15;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );

    PROCEDURE LCD_CURSOR(
        N : NATURAL RANGE 0 TO 1;
        X : NATURAL RANGE 0 TO 19;
        Y : NATURAL RANGE 0 TO 3;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );

    FUNCTION CHAR_TO_STD (
        N : NATURAL RANGE 0 TO 1;
        INPUT_CHAR : CHARACTER
    ) RETURN STD_LOGIC_VECTOR;

    PROCEDURE LCD_WRITE_CHAR(
        N : NATURAL RANGE 0 TO 1;
        INPUT_CHAR : CHARACTER;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );

    PROCEDURE LCD_WRITE_STRING(
        N : NATURAL RANGE 0 TO 1;
        N2 : NATURAL RANGE 0 TO 19;
        STR : IN STRING;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );

END PACKAGE;
PACKAGE BODY LCD_CONTROL IS
    PROCEDURE LCD_INIT(
        N : NATURAL RANGE 0 TO 15;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    ) IS
    BEGIN
        -- Todas las instrucciones de inicialización son comandos (RS='0')
        LCD_RS <= '0';

        CASE N IS
                --------------------------------------------------------
                -- SECUENCIA DE RESET (Datasheet Fig 24)
                --------------------------------------------------------
            WHEN 0 | 1 | 2 =>
                LCD_DATA <= "0011"; -- Enviar 0x3 tres veces (Reset 8-bit)

                --------------------------------------------------------
                -- PASO A MODO 4 BITS
                --------------------------------------------------------
            WHEN 3 =>
                LCD_DATA <= "0010"; -- 0x2: Set interface to 4-bit

                --------------------------------------------------------
                -- FUNCTION SET: 0x28 (4-bit, 2 lines, 5x8 font)
                --------------------------------------------------------
            WHEN 4 => LCD_DATA <= "0010"; -- High Nibble (0x2)
            WHEN 5 => LCD_DATA <= "1000"; -- Low Nibble  (0x8)

                --------------------------------------------------------
                -- DISPLAY OFF: 0x08 (Apagar antes de configurar)
                -- Recomendado por Hitachi antes de limpiar
                --------------------------------------------------------
            WHEN 6 => LCD_DATA <= "0000"; -- High Nibble (0x0)
            WHEN 7 => LCD_DATA <= "1000"; -- Low Nibble  (0x8)

                --------------------------------------------------------
                -- DISPLAY CLEAR: 0x01
                -- Importante: Requiere > 1.52ms de espera después
                --------------------------------------------------------
            WHEN 8 => LCD_DATA <= "0000"; -- High Nibble (0x0)
            WHEN 9 => LCD_DATA <= "0001"; -- Low Nibble  (0x1)

                --------------------------------------------------------
                -- ENTRY MODE SET: 0x06 (Inc addr, No shift)
                -- ESTE FALTABA EN TU CODIGO ORIGINAL
                --------------------------------------------------------
            WHEN 10 => LCD_DATA <= "0000"; -- High Nibble (0x0)
            WHEN 11 => LCD_DATA <= "0110"; -- Low Nibble  (0x6)

                --------------------------------------------------------
                -- DISPLAY ON: 0x0C (On, No Cursor, No Blink)
                -- O usa 0x0F si quieres cursor parpadeando
                --------------------------------------------------------
            WHEN 12 => LCD_DATA <= "0000"; -- High Nibble (0x0)
            WHEN 13 => LCD_DATA <= "1110"; -- Low Nibble  (0xE) -> On, Cursor, No Blink

            WHEN OTHERS =>
                LCD_DATA <= "0000"; -- Idle
        END CASE;
    END PROCEDURE;

    PROCEDURE LCD_CURSOR(
        N : NATURAL RANGE 0 TO 1;
        X : NATURAL RANGE 0 TO 19;
        Y : NATURAL RANGE 0 TO 3;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    ) IS
        VARIABLE DDRAM_ADDR : UNSIGNED(7 DOWNTO 0);
    BEGIN
        -- LINEA 1 --
        IF Y = 0 THEN
            DDRAM_ADDR := TO_UNSIGNED(128 + X, 8);
            -- LINEA 2 --
        ELSIF Y = 1 THEN
            DDRAM_ADDR := TO_UNSIGNED(128 + 64 + X, 8);
            -- LINEA 3 --
        ELSIF Y = 2 THEN
            DDRAM_ADDR := TO_UNSIGNED(128 + 20 + X, 8);
            -- LINEA 4 --
        ELSIF Y = 3 THEN
            DDRAM_ADDR := TO_UNSIGNED(128 + 64 + 20 + X, 8);
        END IF;

        IF N = 0 THEN
            LCD_RS <= '0';
            LCD_DATA <= STD_LOGIC_VECTOR(DDRAM_ADDR(7 DOWNTO 4));
        ELSIF N = 1 THEN
            LCD_RS <= '0';
            LCD_DATA <= STD_LOGIC_VECTOR(DDRAM_ADDR(3 DOWNTO 0));
        END IF;
    END PROCEDURE;

    FUNCTION CHAR_TO_STD (
        N : NATURAL RANGE 0 TO 1;
        INPUT_CHAR : CHARACTER
    )
        RETURN STD_LOGIC_VECTOR IS
        VARIABLE ASCCII_CODE : NATURAL;
        VARIABLE RESULT : STD_LOGIC_VECTOR(7 DOWNTO 0);
    BEGIN
        ASCCII_CODE := CHARACTER'POS(INPUT_CHAR);
        RESULT := STD_LOGIC_VECTOR(TO_UNSIGNED(ASCCII_CODE, 8));

        IF N = 0 THEN
            RETURN RESULT(7 DOWNTO 4);
        ELSE
            RETURN RESULT(3 DOWNTO 0);
        END IF;
    END FUNCTION;

    PROCEDURE LCD_WRITE_CHAR(
        N : NATURAL RANGE 0 TO 1;
        INPUT_CHAR : CHARACTER;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    ) IS
    BEGIN
        LCD_RS <= '1'; -- Modo dato
        LCD_DATA <= CHAR_TO_STD(N, INPUT_CHAR);
    END PROCEDURE;

    PROCEDURE LCD_WRITE_STRING(
        N : NATURAL RANGE 0 TO 1;
        N2 : NATURAL RANGE 0 TO 19;
        STR : IN STRING;
        SIGNAL LCD_RS : OUT STD_LOGIC;
        SIGNAL LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    ) IS
    BEGIN
        LCD_WRITE_CHAR(N, STR(N2), LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
    END PROCEDURE;

END PACKAGE BODY;