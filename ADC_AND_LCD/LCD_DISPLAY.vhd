LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.LCD_CONTROL.ALL;

ENTITY LCD_DISPLAY IS
    GENERIC (
        LCD_CHARS : POSITIVE := 16
    );
    PORT (
        CLK : IN STD_LOGIC;
        RST : IN STD_LOGIC;
        LINE1_VEC : IN STD_LOGIC_VECTOR(8*LCD_CHARS-1 DOWNTO 0);
        LINE2_VEC : IN STD_LOGIC_VECTOR(8*LCD_CHARS-1 DOWNTO 0);
        LCD_RS : OUT STD_LOGIC;
        LCD_EN : OUT STD_LOGIC;
        LCD_DATA : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE COMP OF LCD_DISPLAY IS

    TYPE MACHINE IS (INIT, CURSOR_1, CURSOR_2, WRITE_1, WRITE_2);
    SIGNAL STATE : MACHINE := INIT;

    COMPONENT TIMER
        PORT (
            CLK : IN STD_LOGIC;
            RST : IN STD_LOGIC;
            FAST_MODE : IN STD_LOGIC;
            ENABLE : OUT STD_LOGIC
        );
    END COMPONENT;

    SIGNAL ENABLE_TICK : STD_LOGIC;
    SIGNAL TIMER_FAST : STD_LOGIC;
    SIGNAL COUNT_1 : NATURAL RANGE 0 TO 14 := 0;
    SIGNAL COUNT_2 : NATURAL RANGE 1 TO LCD_CHARS := 1;
    SIGNAL FLAG : STD_LOGIC := '0';
    SIGNAL LINE1 : STD_LOGIC_VECTOR(8*LCD_CHARS-1 DOWNTO 0);
    SIGNAL LINE2 : STD_LOGIC_VECTOR(8*LCD_CHARS-1 DOWNTO 0);

    FUNCTION SLV_TO_CHAR(B : STD_LOGIC_VECTOR(7 DOWNTO 0)) RETURN CHARACTER IS
    BEGIN
        RETURN CHARACTER'VAL(TO_INTEGER(UNSIGNED(B)));
    END FUNCTION;

    FUNCTION GET_CHAR(LINE : STD_LOGIC_VECTOR; IDX : NATURAL; CHARS : NATURAL) RETURN CHARACTER IS
        VARIABLE BASE : NATURAL;
        VARIABLE BYTE : STD_LOGIC_VECTOR(7 DOWNTO 0);
    BEGIN
        -- IDX: 1..CHARS (1 ES EL PRIMER CARACTER)
        BASE := (CHARS - IDX) * 8;
        BYTE := LINE(BASE+7 DOWNTO BASE);
        RETURN SLV_TO_CHAR(BYTE);
    END FUNCTION;

BEGIN

    -- Lógica de control de velocidad:
    -- '0' (Lento) durante la inicialización para respetar los tiempos del datasheet.
    -- '1' (Rápido) para el resto de operaciones (escritura es mucho más rápida).
    TIMER_FAST <= '0' WHEN STATE = INIT ELSE
        '1';

    U_TIMER : TIMER
    PORT MAP(
        CLK => CLK,
        RST => RST,
        FAST_MODE => TIMER_FAST,
        ENABLE => ENABLE_TICK -- Recibe pulsos
    );

    PROCESS (CLK, RST) -- goblal clock
    BEGIN
        IF RST = '1' THEN
            COUNT_1 <= 0;
            FLAG <= '0';
            STATE <= INIT;
            LCD_EN <= '0';
            LCD_RS <= '0';
            LCD_DATA <= (OTHERS => '0');

        ELSIF RISING_EDGE(CLK) THEN
            IF ENABLE_TICK = '1' THEN -- ? Solo ejecuta cuando hay pulso
                CASE STATE IS
                    WHEN INIT =>
                        IF COUNT_1 < 14 THEN
                            IF FLAG = '0' THEN
                                LCD_EN <= '1';
                                FLAG <= '1';
                                LCD_INIT(COUNT_1, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            ELSE
                                LCD_EN <= '0';
                                FLAG <= '0';
                                COUNT_1 <= COUNT_1 + 1;
                                LCD_INIT(COUNT_1, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            END IF;
                        ELSE
                            COUNT_1 <= 0;
                            STATE <= CURSOR_1;
                            LCD_EN <= '0';
                        END IF;

                    WHEN CURSOR_1 =>
                        IF COUNT_1 < 2 THEN
                            IF FLAG = '0' THEN
                                LCD_EN <= '1';
                                FLAG <= '1';
                                LCD_CURSOR(COUNT_1, 0, 0, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            ELSE
                                LCD_EN <= '0';
                                FLAG <= '0';
                                COUNT_1 <= COUNT_1 + 1;
                                -- Mantener datos estables
                                LCD_CURSOR(COUNT_1, 0, 0, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            END IF;
                        ELSE
                            COUNT_1 <= 0;
                            STATE <= WRITE_1;
                            LCD_EN <= '0';
                        END IF;

                    WHEN CURSOR_2 =>
                        IF COUNT_1 < 2 THEN
                            IF FLAG = '0' THEN
                                LCD_EN <= '1';
                                FLAG <= '1';
                                LCD_CURSOR(COUNT_1, 0, 1, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            ELSE
                                LCD_EN <= '0';
                                FLAG <= '0';
                                COUNT_1 <= COUNT_1 + 1;
                                -- Mantener datos estables
                                LCD_CURSOR(COUNT_1, 0, 1, LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                            END IF;
                        ELSE
                            COUNT_1 <= 0;
                            STATE <= WRITE_2;
                            LCD_EN <= '0';
                        END IF;

                    WHEN WRITE_1 =>
                        IF COUNT_2 <= LCD_CHARS THEN
                            IF COUNT_1 < 2 THEN
                                IF FLAG = '0' THEN
                                    LCD_EN <= '1';
                                    FLAG <= '1';
                                    LCD_WRITE_CHAR(COUNT_1, GET_CHAR(LINE1_VEC, COUNT_2, LCD_CHARS), LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                                ELSE
                                    LCD_EN <= '0';
                                    FLAG <= '0';
                                    COUNT_1 <= COUNT_1 + 1;
                                    LCD_WRITE_CHAR(COUNT_1, GET_CHAR(LINE1_VEC, COUNT_2, LCD_CHARS), LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                                END IF;
                            ELSE
                                COUNT_1 <= 0;
                                COUNT_2 <= COUNT_2 + 1;
                            END IF;
                        ELSE
                            COUNT_2 <= 1;
                            STATE <= CURSOR_2;
                            LCD_EN <= '0';
                        END IF;

                    WHEN WRITE_2 =>
                        IF COUNT_2 <= LCD_CHARS THEN
                            IF COUNT_1 < 2 THEN
                                IF FLAG = '0' THEN
                                    LCD_EN <= '1';
                                    FLAG <= '1';
                                    LCD_WRITE_CHAR(COUNT_1, GET_CHAR(LINE2_VEC, COUNT_2, LCD_CHARS), LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                                ELSE
                                    LCD_EN <= '0';
                                    FLAG <= '0';
                                    COUNT_1 <= COUNT_1 + 1;
                                    LCD_WRITE_CHAR(COUNT_1, GET_CHAR(LINE2_VEC, COUNT_2, LCD_CHARS), LCD_RS => LCD_RS, LCD_DATA => LCD_DATA);
                                END IF;
                            ELSE
                                COUNT_1 <= 0;
                                COUNT_2 <= COUNT_2 + 1;
                            END IF;
                        ELSE
                            COUNT_2 <= 1;
                            STATE <= CURSOR_1;
                            LCD_EN <= '0';
                        END IF;

                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;