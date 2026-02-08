LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ADC_AND_LCD IS
    GENERIC (
        LCD_CHARS : POSITIVE := 16
    );
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        DATA_VALID : IN STD_LOGIC;
        DATA_IN : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        DATA_OUT : OUT STD_LOGIC_VECTOR(8 * LCD_CHARS - 1 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE COMP OF ADC_AND_LCD IS
    TYPE MACHINE IS (IDLE, CONVERT, BCD_CONV, FORMAT, DONE);
    SIGNAL STATE : MACHINE := IDLE;

    SIGNAL VOLTAGE_RAW : NATURAL := 0;
    SIGNAL VOLTAGE_S : INTEGER := 0;
    SIGNAL STEP_CNT : NATURAL := 0;

    -- Señales para conversión BCD
    SIGNAL BCD_RESULT : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0'); -- 4 dígitos
    SIGNAL SHIFT_REG : STD_LOGIC_VECTOR(28 DOWNTO 0) := (OTHERS => '0'); -- 16 BCD + 13 binario
    SIGNAL SHIFT_COUNT : INTEGER RANGE 0 TO 13 := 0;

    -- Función para el algoritmo Double Dabble
    FUNCTION ADD3_IF_GE5(DIGIT : STD_LOGIC_VECTOR(3 DOWNTO 0))
        RETURN STD_LOGIC_VECTOR IS
    BEGIN
        IF unsigned(DIGIT) >= 5 THEN
            RETURN STD_LOGIC_VECTOR(unsigned(DIGIT) + 3);
        ELSE
            RETURN DIGIT;
        END IF;
    END FUNCTION;

BEGIN
    PROCESS (CLK, RESET)
        VARIABLE temp_bin : STD_LOGIC_VECTOR(12 DOWNTO 0); -- 13 bits para 0-6143
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            STEP_CNT <= 0;
            DATA_OUT <= (OTHERS => '0');
            BCD_RESULT <= (OTHERS => '0');
            SHIFT_REG <= (OTHERS => '0');
        ELSIF RISING_EDGE(CLK) THEN
            CASE STATE IS
                WHEN IDLE =>
                    IF DATA_VALID = '1' THEN
                        STEP_CNT <= 0;
                        STATE <= CONVERT;
                    END IF;

                WHEN CONVERT =>
                    CASE STEP_CNT IS
                        WHEN 0 =>
                            VOLTAGE_S <= to_integer(signed(DATA_IN));
                            IF to_integer(signed(DATA_IN)) < 0 THEN
                                VOLTAGE_S <= 0;
                            END IF;
                            STEP_CNT <= STEP_CNT + 1;

                        WHEN 1 =>
                            VOLTAGE_RAW <= (NATURAL(VOLTAGE_S) * 1875) / 10000;
                            STEP_CNT <= STEP_CNT + 1;

                        WHEN 2 =>
                            -- Inicializar conversión BCD (Double Dabble)
                            temp_bin := STD_LOGIC_VECTOR(to_unsigned(VOLTAGE_RAW, 13));
                            SHIFT_REG <= (OTHERS => '0');
                            SHIFT_REG(12 DOWNTO 0) <= temp_bin;
                            SHIFT_COUNT <= 0;
                            STATE <= BCD_CONV;
                            STEP_CNT <= 0;

                        WHEN OTHERS =>
                            STEP_CNT <= 0;
                            STATE <= IDLE;
                    END CASE;

                WHEN BCD_CONV =>
                    IF SHIFT_COUNT < 13 THEN

                        SHIFT_REG(28 DOWNTO 25) <= ADD3_IF_GE5(SHIFT_REG(28 DOWNTO 25)); -- MILES
                        SHIFT_REG(24 DOWNTO 21) <= ADD3_IF_GE5(SHIFT_REG(24 DOWNTO 21)); -- CENTENAS
                        SHIFT_REG(20 DOWNTO 17) <= ADD3_IF_GE5(SHIFT_REG(20 DOWNTO 17)); -- DECENAS
                        SHIFT_REG(16 DOWNTO 13) <= ADD3_IF_GE5(SHIFT_REG(16 DOWNTO 13)); -- UNIDADES

                        SHIFT_REG <= SHIFT_REG(27 DOWNTO 0) & '0'; -- Shift left
                        SHIFT_COUNT <= SHIFT_COUNT + 1;
                    ELSE
                        BCD_RESULT <= SHIFT_REG(28 DOWNTO 13); -- Resultado BCD
                        STATE <= FORMAT;
                    END IF;

                WHEN FORMAT =>
                    -- Aquí puedes formatear para el LCD
                    -- Por ejemplo: "Volt: XXXX mV  " (16 caracteres)
                    -- BCD_RESULT(15:12) = miles, (11:8) = centenas, (7:4) = decenas, (3:0) = unidades

                    -- Ejemplo simple: convertir BCD a ASCII y formatear
                    DATA_OUT(127 DOWNTO 120) <= X"56"; -- 'V'
                    DATA_OUT(119 DOWNTO 112) <= X"6F"; -- 'o'
                    DATA_OUT(111 DOWNTO 104) <= X"6C"; -- 'l'
                    DATA_OUT(103 DOWNTO 96) <= X"74"; -- 't'
                    DATA_OUT(95 DOWNTO 88) <= X"3A"; -- ':'
                    DATA_OUT(87 DOWNTO 80) <= X"20"; -- ' '

                    -- Convertir BCD a ASCII (sumar X"30")
                    DATA_OUT(79 DOWNTO 72) <= X"3" & BCD_RESULT(15 DOWNTO 12); -- Miles
                    DATA_OUT(71 DOWNTO 64) <= X"3" & BCD_RESULT(11 DOWNTO 8); -- Centenas
                    DATA_OUT(63 DOWNTO 56) <= X"3" & BCD_RESULT(7 DOWNTO 4); -- Decenas
                    DATA_OUT(55 DOWNTO 48) <= X"3" & BCD_RESULT(3 DOWNTO 0); -- Unidades

                    DATA_OUT(47 DOWNTO 40) <= X"20"; -- ' '
                    DATA_OUT(39 DOWNTO 32) <= X"6D"; -- 'm'
                    DATA_OUT(31 DOWNTO 24) <= X"56"; -- 'V'
                    DATA_OUT(23 DOWNTO 16) <= X"20"; -- ' '
                    DATA_OUT(15 DOWNTO 8) <= X"20"; -- ' '
                    DATA_OUT(7 DOWNTO 0) <= X"20"; -- ' '

                    STATE <= DONE;
                WHEN DONE =>
                    STATE <= IDLE;
                WHEN OTHERS =>
                    STATE <= IDLE;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;