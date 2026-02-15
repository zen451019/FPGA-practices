LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ADXL345 IS
    GENERIC (
        SLAVE : INTEGER := 1;
        SLAVE_DATA_BITS : INTEGER := 8
    );
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        MOSI : OUT STD_LOGIC;
        MISO : IN STD_LOGIC;
        CS : BUFFER STD_LOGIC_VECTOR(SLAVE - 1 DOWNTO 0);
        SCLK : BUFFER STD_LOGIC;

        CPOL : IN STD_LOGIC;
        CPHA : IN STD_LOGIC;
        CLK_DIVI : IN INTEGER;
        CS_SELECT : IN INTEGER;

        R_W : IN STD_LOGIC;
        REG_ADDR : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        N : IN INTEGER;
        DATA : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        START_S : IN STD_LOGIC;

        RX_DATA : OUT STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0);
        RX_VALID : OUT STD_LOGIC := '0';
        BUSY : OUT STD_LOGIC;
        DONE : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF ADXL345 IS

    TYPE MACHINE IS (IDLE, START, WAIT_SPI_RISE, WAIT_SPI_LOW);
    SIGNAL STATE : MACHINE := IDLE;

    COMPONENT SPI
        GENERIC (
            SLAVE : INTEGER := SLAVE;
            SLAVE_DATA_BITS : INTEGER := SLAVE_DATA_BITS
        );
        PORT (
            CLK : IN STD_LOGIC;
            RESET : IN STD_LOGIC;
            MOSI : OUT STD_LOGIC;
            MISO : IN STD_LOGIC;
            CS : BUFFER STD_LOGIC_VECTOR(SLAVE - 1 DOWNTO 0);
            SCLK : BUFFER STD_LOGIC;

            BUSY : OUT STD_LOGIC;
            CLK_DIVI : IN INTEGER;
            CS_SELECT : IN INTEGER;

            EN : IN STD_LOGIC;

            CPOL : IN STD_LOGIC;
            CPHA : IN STD_LOGIC;

            DATA_WR : IN STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0);
            DATA_RD : OUT STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0);

            A_CON : IN STD_LOGIC
        );
    END COMPONENT;

    SIGNAL SPI_BUSY : STD_LOGIC;
    SIGNAL SPI_EN : STD_LOGIC := '0';
    SIGNAL SPI_FIRE : STD_LOGIC := '0';

    CONSTANT DUMMY_BYTE : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '1');
    SIGNAL SPI_DATA_WR : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL SPI_DATA_RD : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL SPI_A_CON : STD_LOGIC := '0';

    SIGNAL BYTE_COUNT : INTEGER := 0;

    SIGNAL R_W_REG : STD_LOGIC;
    SIGNAL REG_ADDR_REG : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL DATA_REG : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL N_REG : INTEGER;

    SIGNAL START_SYNC_0 : STD_LOGIC := '0';
    SIGNAL START_SYNC_1 : STD_LOGIC := '0';
    SIGNAL START_PREV   : STD_LOGIC := '0';
    SIGNAL START_PULSE  : STD_LOGIC := '0';

BEGIN

    SPI_EN <= SPI_FIRE;

    SPI_INST : SPI
    PORT MAP(
        CLK => CLK,
        RESET => RESET,
        MOSI => MOSI,
        MISO => MISO,
        CS => CS,
        SCLK => SCLK,
        BUSY => SPI_BUSY,
        CLK_DIVI => CLK_DIVI,
        CS_SELECT => CS_SELECT,
        EN => SPI_EN,
        CPOL => CPOL,
        CPHA => CPHA,
        DATA_WR => SPI_DATA_WR,
        DATA_RD => SPI_DATA_RD,
        A_CON => SPI_A_CON
    );

    PROCESS(CLK, RESET)
    BEGIN
        IF RESET = '1' THEN

            STATE <= IDLE;
            SPI_FIRE <= '0';
            RX_DATA <= (OTHERS => '0');
            RX_VALID <= '0';
            BUSY <= '0';
            DONE <= '0';
            BYTE_COUNT <= 0;

        ELSIF RISING_EDGE(CLK) THEN

            -- Pulso de un solo ciclo SIEMPRE
            SPI_FIRE <= '0';
            RX_VALID <= '0';

            -- Sincronizador de START
            START_SYNC_0 <= START_S;
            START_SYNC_1 <= START_SYNC_0;
            START_PREV   <= START_SYNC_1;
            START_PULSE  <= START_SYNC_1 AND NOT START_PREV;

            CASE STATE IS

                WHEN IDLE =>
                    BUSY <= '0';
                    DONE <= '0';
                    BYTE_COUNT <= 0;

                    IF START_PULSE = '1' THEN
                        R_W_REG <= R_W;
                        REG_ADDR_REG <= REG_ADDR;
                        DATA_REG <= DATA;
                        N_REG <= N;
                        BUSY <= '1';
                        STATE <= START;
                    END IF;

                WHEN START =>
                    IF SPI_BUSY = '0' THEN

                        IF BYTE_COUNT < (N_REG + 1) THEN

                            IF BYTE_COUNT < N_REG THEN
                                SPI_A_CON <= '1';
                            ELSE
                                SPI_A_CON <= '0';
                            END IF;

                            IF BYTE_COUNT = 0 THEN
                                SPI_DATA_WR <= REG_ADDR_REG;
                            ELSE
                                IF R_W_REG = '1' THEN
                                    SPI_DATA_WR <= DUMMY_BYTE;
                                ELSE
                                    SPI_DATA_WR <= DATA_REG;
                                END IF;
                            END IF;

                            SPI_FIRE <= '1';  -- PULSO EXACTO DE 1 CICLO
                            STATE <= WAIT_SPI_RISE;

                        ELSE
                            DONE <= '1';
                            STATE <= IDLE;
                        END IF;

                    END IF;

                WHEN WAIT_SPI_RISE =>
                    IF SPI_BUSY = '1' THEN
                        STATE <= WAIT_SPI_LOW;
                    END IF;

                WHEN WAIT_SPI_LOW =>
                    IF SPI_BUSY = '0' THEN

                        IF R_W_REG = '1' AND BYTE_COUNT > 0 THEN
                            RX_DATA <= SPI_DATA_RD;
                            RX_VALID <= '1';
                        END IF;

                        BYTE_COUNT <= BYTE_COUNT + 1;
                        STATE <= START;

                    END IF;

            END CASE;

        END IF;
    END PROCESS;

END ARCHITECTURE;
