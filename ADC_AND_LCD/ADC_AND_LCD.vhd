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


    SIGNAL BCD_RESULT : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SHIFT_REG : STD_LOGIC_VECTOR(28 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SHIFT_COUNT : INTEGER RANGE 0 TO 13 := 0;

    -- Funci�n Double Dabble
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
        VARIABLE TEMP_S : INTEGER;
        VARIABLE TEMP_BIN : STD_LOGIC_VECTOR(12 DOWNTO 0);
        VARIABLE TEMP_SHIFT : STD_LOGIC_VECTOR(28 DOWNTO 0); -- ? Variable temporal
        VARIABLE TEMP_MULT : unsigned(16 downto 0);
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            SHIFT_COUNT <= 0;  -- ? AGREGADO
            DATA_OUT <=  X"20202020202020202020202020202020";
            BCD_RESULT <= (OTHERS => '0');
            SHIFT_REG <= (OTHERS => '0');
        
            
        ELSIF RISING_EDGE(CLK) THEN
            CASE STATE IS
                WHEN IDLE =>
                    IF DATA_VALID = '1' THEN
                        STATE <= CONVERT;
                    END IF;

                WHEN CONVERT =>
                    -- ? Todo en 1 ciclo usando variables
                    TEMP_S := to_integer(signed(DATA_IN));
                    IF TEMP_S < 0 THEN
                        TEMP_S := 0;
                    END IF;
                    
                    -- Inicializar BCD
                    TEMP_MULT := to_unsigned(TEMP_S * 3, TEMP_MULT'length);
                    TEMP_BIN := STD_LOGIC_VECTOR(TEMP_MULT(16 downto 4));
                    SHIFT_REG <= (OTHERS => '0');
                    SHIFT_REG(12 DOWNTO 0) <= TEMP_BIN;
                    SHIFT_COUNT <= 0;
                    STATE <= BCD_CONV;

                WHEN BCD_CONV =>
                    IF SHIFT_COUNT < 13 THEN
                        -- ? Usar variable temporal para evitar conflictos
                        TEMP_SHIFT := SHIFT_REG;
                        
                        -- Aplicar ADD3 a cada d�gito
                        TEMP_SHIFT(28 DOWNTO 25) := ADD3_IF_GE5(TEMP_SHIFT(28 DOWNTO 25));
                        TEMP_SHIFT(24 DOWNTO 21) := ADD3_IF_GE5(TEMP_SHIFT(24 DOWNTO 21));
                        TEMP_SHIFT(20 DOWNTO 17) := ADD3_IF_GE5(TEMP_SHIFT(20 DOWNTO 17));
                        TEMP_SHIFT(16 DOWNTO 13) := ADD3_IF_GE5(TEMP_SHIFT(16 DOWNTO 13));
                        
                        -- Ahora s� hacer shift
                        SHIFT_REG <= TEMP_SHIFT(27 DOWNTO 0) & '0';
                        SHIFT_COUNT <= SHIFT_COUNT + 1;
                    ELSE
                        BCD_RESULT <= SHIFT_REG(28 DOWNTO 13);
                        STATE <= FORMAT;
                    END IF;

                WHEN FORMAT =>
                    -- Formatear "Volt: XXXX mV  "
                    DATA_OUT(127 DOWNTO 120) <= X"56"; -- 'V'
                    DATA_OUT(119 DOWNTO 112) <= X"6F"; -- 'o'
                    DATA_OUT(111 DOWNTO 104) <= X"6C"; -- 'l'
                    DATA_OUT(103 DOWNTO 96)  <= X"74"; -- 't'
                    DATA_OUT(95 DOWNTO 88)   <= X"3A"; -- ':'
                    DATA_OUT(87 DOWNTO 80)   <= X"20"; -- ' '
                    DATA_OUT(79 DOWNTO 72)   <= X"3" & BCD_RESULT(15 DOWNTO 12);
                    DATA_OUT(71 DOWNTO 64)   <= X"3" & BCD_RESULT(11 DOWNTO 8);
                    DATA_OUT(63 DOWNTO 56)   <= X"3" & BCD_RESULT(7 DOWNTO 4);
                    DATA_OUT(55 DOWNTO 48)   <= X"3" & BCD_RESULT(3 DOWNTO 0);
                    DATA_OUT(47 DOWNTO 40)   <= X"20"; -- ' '
                    DATA_OUT(39 DOWNTO 32)   <= X"6D"; -- 'm'
                    DATA_OUT(31 DOWNTO 24)   <= X"56"; -- 'V'
                    DATA_OUT(23 DOWNTO 0)    <= X"202020"; -- 3 espacios
                    
                    STATE <= DONE;

                WHEN DONE =>
                    STATE <= IDLE;

                WHEN OTHERS =>
                    STATE <= IDLE;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;