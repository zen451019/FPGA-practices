LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY I2C IS
    GENERIC (
        CLK_FREQ_HZ : INTEGER := 50000000;
        I2C_FREQ_HZ : INTEGER := 100000
    );
    PORT (
        CLK : IN STD_LOGIC; -- System clock input for timing synchronization
        RESET : IN STD_LOGIC; -- Asynchronous reset signal (active LOW)
        EN : IN STD_LOGIC; -- Enable signal to initiate I2C transaction
        ADDR : IN STD_LOGIC_VECTOR(6 DOWNTO 0); -- 7-bit slave address for I2C communication
        RW : IN STD_LOGIC; -- Read/Write control (0=Write, 1=Read)
        DATA_WR : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- 8-bit data to write to slave device
        BUSY : OUT STD_LOGIC; -- Status output indicating I2C bus is busy
        DATA_RD : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- 8-bit data read from slave device
        ACK_ERR : BUFFER STD_LOGIC; -- Acknowledgment error flag (no ACK received from slave)
        SDA : INOUT STD_LOGIC; -- I2C Serial Data Line (open-drain, bidirectional)
        SCL : INOUT STD_LOGIC -- I2C Serial Clock Line (open-drain, bidirectional)
    );
END ENTITY;

ARCHITECTURE COMP OF I2C IS
    CONSTANT CLK_DIV : INTEGER := CLK_FREQ_HZ / (I2C_FREQ_HZ * 4); -- Clock divider for I2C timing (T/4)

    --STATE MACHINE
    TYPE MACHINE IS (READY, START, COMMAND, SLV_ACK1, WR, SLV_ACK2, RD, MSTR_ACK, STOP);
    SIGNAL STATE : MACHINE := READY;

    --CLOCK GENERATION
    SIGNAL DATA_CLK : STD_LOGIC := '0';
    SIGNAL DATA_CLK_PREV : STD_LOGIC := '0';
    SIGNAL SCL_CLK : STD_LOGIC := '0';
    SIGNAL SCL_EN : STD_LOGIC := '0';
    SIGNAL SDA_INT : STD_LOGIC := '1';
    SIGNAL SDA_EN : STD_LOGIC := '0';
    SIGNAL ADDR_RW : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL DATA_TX : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL DATA_RX : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL BIT_CNT : INTEGER RANGE 0 TO 7 := 7;
    SIGNAL STRETCHED : STD_LOGIC := '0';

BEGIN
    PROCESS (CLK, RESET)
        VARIABLE COUNT : INTEGER RANGE 0 TO CLK_DIV * 4 := 0;
    BEGIN
        IF RESET = '0' THEN
            STRETCHED <= '0';
            COUNT := 0;

        ELSIF RISING_EDGE(CLK) THEN
            DATA_CLK_PREV <= DATA_CLK;
            IF COUNT = CLK_DIV * 4 - 1 THEN
                COUNT := 0;

            ELSIF STRETCHED = '0' THEN
                COUNT := COUNT + 1;
            END IF;

            CASE COUNT IS
                WHEN 0 TO CLK_DIV - 1 =>
                    SCL_CLK <= '0';
                    DATA_CLK <= '0';
                WHEN CLK_DIV TO CLK_DIV * 2 - 1 =>
                    SCL_CLK <= '0';
                    DATA_CLK <= '1';
                WHEN CLK_DIV * 2 TO CLK_DIV * 3 - 1 =>
                    SCL_CLK <= '1';
                    IF SCL = '0' THEN
                        STRETCHED <= '1';
                    ELSE
                        STRETCHED <= '0';
                    END IF;
                    DATA_CLK <= '1';
                WHEN CLK_DIV * 3 TO CLK_DIV * 4 - 1 =>
                    SCL_CLK <= '1';
                    DATA_CLK <= '0';
                WHEN OTHERS =>
                    SCL_CLK <= '1';
                    DATA_CLK <= '0';

            END CASE;

        END IF;

    END PROCESS;

    --SECOND PROCESS FOR I2C LOGIC
    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE <= READY;
            BUSY <= '1';
            SCL_EN <= '0';
            SDA_INT <= '1';
            ACK_ERR <= '0';
            BIT_CNT <= 7;
            DATA_RD <= (OTHERS => '0');

        ELSIF RISING_EDGE(CLK) THEN
            IF DATA_CLK = '1' AND DATA_CLK_PREV = '0' THEN
                CASE STATE IS
                    WHEN READY =>
                        IF EN = '1' THEN
                            BUSY <= '1';
                            ADDR_RW <= ADDR & RW;
                            DATA_TX <= DATA_WR;
                            STATE <= START;
                        ELSE
                            BUSY <= '0';
                            STATE <= READY;
                        END IF;
                    WHEN START =>
                        BUSY <= '1';
                        SDA_INT <= ADDR_RW(BIT_CNT);
                        STATE <= COMMAND;
                    WHEN COMMAND =>
                        IF BIT_CNT = 0 THEN
                            BIT_CNT <= 7;
                            SDA_INT <= '1'; -- Release SDA for ACK bit
                            STATE <= SLV_ACK1;
                        ELSE
                            BIT_CNT <= BIT_CNT - 1;
                            SDA_INT <= ADDR_RW(BIT_CNT - 1);
                            STATE <= COMMAND;
                        END IF;
                    WHEN SLV_ACK1 =>
                        IF ADDR_RW(0) = '0' THEN -- Write operation
                            SDA_INT <= DATA_TX(BIT_CNT);
                            STATE <= WR;
                        ELSE
                            SDA_INT <= '1';
                            STATE <= RD;
                        END IF;
                    WHEN WR =>
                        BUSY <= '1';
                        IF BIT_CNT = 0 THEN
                            BIT_CNT <= 7;
                            SDA_INT <= '1'; -- Release SDA for ACK bit
                            STATE <= SLV_ACK2;
                        ELSE
                            BIT_CNT <= BIT_CNT - 1;
                            SDA_INT <= DATA_TX(BIT_CNT - 1);
                            STATE <= WR;
                        END IF;
                    WHEN SLV_ACK2 =>
                        IF EN = '1' THEN
                            BUSY <= '0';
                            ADDR_RW <= ADDR & RW;
                            DATA_TX <= DATA_WR;
                            IF ADDR_RW = ADDR & RW THEN
                                SDA_INT <= DATA_WR(BIT_CNT);
                                STATE <= WR;
                            ELSE
                                STATE <= START;
                            END IF;
                        ELSE
                            STATE <= STOP;
                        END IF;
                    WHEN RD =>
                        BUSY <= '1';
                        IF BIT_CNT = 0 THEN
                            IF EN = '1' AND ADDR_RW = ADDR & RW THEN
                                SDA_INT <= '0';
                            ELSE
                                SDA_INT <= '1';
                            END IF;
                            BIT_CNT <= 7;
                            DATA_RD <= DATA_RX;
                            STATE <= MSTR_ACK;
                        ELSE
                            BIT_CNT <= BIT_CNT - 1;
                            STATE <= RD;
                        END IF;
                    WHEN MSTR_ACK =>
                        IF EN = '1' THEN
                            BUSY <= '0';
                            ADDR_RW <= ADDR & RW;
                            DATA_TX <= DATA_WR;
                            IF ADDR_RW = ADDR & RW THEN
                                SDA_INT <= '1';
                                STATE <= RD;
                            ELSE
                                STATE <= START;
                            END IF;
                        ELSE
                            STATE <= STOP;
                        END IF;
                    WHEN STOP =>
                        BUSY <= '0';
                        STATE <= READY;
                    WHEN OTHERS =>
                END CASE;

            ELSIF DATA_CLK = '0' AND DATA_CLK_PREV = '1' THEN
                CASE STATE IS
                    WHEN START =>
                        IF SCL_EN = '0' THEN
                            SCL_EN <= '1';
                            ACK_ERR <= '0';
                        END IF;
                    WHEN SLV_ACK1 =>
                        IF SDA /= '0' OR ACK_ERR = '1' THEN
                            ACK_ERR <= '1';
                        END IF;
                    WHEN RD =>
                        DATA_RX(BIT_CNT) <= SDA;
                    WHEN SLV_ACK2 =>
                        IF SDA /= '0' OR ACK_ERR = '1' THEN
                            ACK_ERR <= '1';
                        END IF;
                    WHEN STOP =>
                        SCL_EN <= '0';
                    WHEN OTHERS =>
                        NULL;
                END CASE;

            END IF;
        END IF;

    END PROCESS;

    WITH STATE SELECT
        SDA_EN <= DATA_CLK_PREV WHEN START,
        NOT DATA_CLK_PREV WHEN STOP,
        SDA_INT WHEN OTHERS;

    SCL <= '0' WHEN SCL_EN = '1' AND SCL_CLK = '0' ELSE
        'Z';
    SDA <= '0' WHEN SDA_EN = '0' ELSE
        'Z';

END ARCHITECTURE;