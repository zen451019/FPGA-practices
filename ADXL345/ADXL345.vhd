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

        R_W : IN STD_LOGIC; -- Read/Write control signal
        REG_ADDR : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- Register address
        N : IN INTEGER; -- Number of bytes to read/write
        DATA : IN STD_LOGIC_VECTOR(7 DOWNTO 0); -- Data to write (for write operations)
        START_S : IN STD_LOGIC; -- Signal to start the operation

        RX_DATA : OUT STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0);
        RX_VALID : OUT STD_LOGIC := '0';
        BUSY : OUT STD_LOGIC;
        DONE : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF ADXL345 IS

    TYPE MACHINE IS (IDLE, START, SEND_CMD, WAIT_SPI);
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

    CONSTANT DUMMY_BYTE : STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0) := (OTHERS => '1');

    SIGNAL SPI_DATA_WR : STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SPI_DATA_RD : STD_LOGIC_VECTOR(SLAVE_DATA_BITS - 1 DOWNTO 0);

    SIGNAL SPI_A_CON : STD_LOGIC := '0';

    SIGNAL BYTE_COUNT : INTEGER := 0;

    SIGNAL PREV_START_S : STD_LOGIC := '0';
    
BEGIN

    SPI_INST : SPI
    GENERIC MAP(
        SLAVE => SLAVE,
        SLAVE_DATA_BITS => SLAVE_DATA_BITS
    )
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

    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '1' THEN
            STATE <= IDLE;
            SPI_EN <= '0';
            RX_DATA <= (OTHERS => '0');
            RX_VALID <= '0';
            BUSY <= '0';
            DONE <= '0';
            BYTE_COUNT <= 0;

        ELSIF RISING_EDGE(CLK) THEN
        PREV_START_S <= START_S; -- Capturar el valor anterior de START_S
            CASE STATE IS
                WHEN IDLE =>
                    DONE <= '0';
                    BUSY <= '0';
                    BYTE_COUNT <= 0;
                    RX_VALID <= '0';
                    IF START_S = '1' AND PREV_START_S = '0' THEN
                        STATE <= START;
                        BUSY <= '1';
                    END IF;

                WHEN START =>
                    BUSY <= '1';
                    IF SPI_BUSY = '0' THEN
                        IF BYTE_COUNT < (N + 1) THEN
                            -- Configurar A_CON
                            IF BYTE_COUNT < N THEN
                                SPI_A_CON <= '1';
                            ELSE 
                                SPI_A_CON <= '0';
                            END IF;
                            
                            IF BYTE_COUNT = 0 THEN
                                SPI_DATA_WR <= REG_ADDR;
                                SPI_EN <= '1';
                                STATE <= SEND_CMD;
                            ELSE
                                IF R_W = '1' THEN
                                    SPI_DATA_WR <= DUMMY_BYTE;
                                    SPI_EN <= '1';
                                    STATE <= SEND_CMD;
                                ELSE
                                    SPI_DATA_WR <= DATA;
                                    SPI_EN <= '1';
                                    STATE <= SEND_CMD;
                                END IF;
                            END IF;
                        ELSE
                            STATE <= IDLE;
                            DONE <= '1';
                        END IF;
                    END IF;
                
                    WHEN SEND_CMD =>
                        SPI_EN <= '0';
                        IF SPI_BUSY = '1' THEN
                            STATE <= WAIT_SPI;
                        END IF;

                    WHEN WAIT_SPI =>
                        RX_VALID <= '0';
                        IF SPI_BUSY = '0' THEN
                            IF R_W = '1' AND BYTE_COUNT > 0 THEN
                                RX_DATA <= SPI_DATA_RD;
                                RX_VALID <= '1';
                            END IF;
                            BYTE_COUNT <= BYTE_COUNT + 1;
                            STATE <= START;
                        END IF;

                    WHEN OTHERS =>
                        STATE <= IDLE;
                END CASE;
            END IF;
        END PROCESS;

END ARCHITECTURE;

-- ========================================
-- IMPORTANTE: Restricciones de uso
-- ========================================
-- • LECTURA (R_W='1'): N puede ser cualquier valor (1, 2, 6, etc.)
-- • ESCRITURA (R_W='0'): N DEBE ser siempre 1
-- • No se soportan escrituras múltiples por diseño
-- ========================================