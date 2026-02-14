LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
ENTITY ADXL345 IS
    GENERIC (
        CLK_FREQ : INTEGER := 50000000;
        SLAVE : INTEGER := 1;
        SLAVE_DATA_BITS : INTEGER := 8
    );
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        MOSI : OUT STD_LOGIC;
        MISO : IN STD_LOGIC;
        CS : BUFFER STD_LOGIC_VECTOR(0 DOWNTO 0);
        SCLK : BUFFER STD_LOGIC;

        DATA_VALID : OUT STD_LOGIC := '0'
        --DATA_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE COMP OF ADXL345 IS

    TYPE MACHINE IS (IDLE, CONFIGURE, SEND_REG, READ_DATA, WAIT_STATE, WAIT_BUSY);
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

    SIGNAL SPI_CS_SELECT : INTEGER := 0;
    SIGNAL SPI_EN : STD_LOGIC := '0';

    CONSTANT SPI_CLK_DIVI : INTEGER := CLK_FREQ/10;
    CONSTANT CPOL : STD_LOGIC := '1';
    CONSTANT CPHA : STD_LOGIC := '1';
    CONSTANT DUMMY_BYTE : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"FF";

    SIGNAL SPI_DATA_WR : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SPI_DATA_RD : STD_LOGIC_VECTOR(7 DOWNTO 0);

    SIGNAL SPI_A_CON : STD_LOGIC := '0';

    SIGNAL CONFIG_COUNT : INTEGER := 0;
BEGIN

    SPI_INST : SPI
    GENERIC MAP(
        SLAVE => 1,
        SLAVE_DATA_BITS => 8
    )
    PORT MAP(
        CLK => CLK,
        RESET => RESET,
        MOSI => MOSI,
        MISO => MISO,
        CS => CS,
        SCLK => SCLK,

        BUSY => SPI_BUSY,
        CLK_DIVI => SPI_CLK_DIVI,
        CS_SELECT => SPI_CS_SELECT,

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
            DATA_VALID <= '0';
            --DATA_OUT <= (OTHERS => '0');
            SPI_EN <= '0';
        ELSIF RISING_EDGE(CLK) THEN
            CASE STATE IS
                WHEN IDLE =>
                    IF SPI_BUSY = '0' THEN
                        STATE <= CONFIGURE;
                    END IF;
                WHEN CONFIGURE =>
                    IF CONFIG_COUNT = 0 THEN
                        SPI_DATA_WR <= X"80";
                        SPI_EN <= '1';
                        STATE <= WAIT_BUSY;
                    ELSIF CONFIG_COUNT = 1 THEN
                        SPI_DATA_WR <= DUMMY_BYTE;
                        SPI_EN <= '1';
                        STATE <= WAIT_BUSY;
                    END IF;
                WHEN WAIT_BUSY =>
                    SPI_EN <= '0';
                    IF SPI_BUSY = '1' THEN
                        STATE <= WAIT_STATE;
                    END IF;
                WHEN WAIT_STATE =>
                    IF SPI_BUSY = '0' THEN
                        IF CONFIG_COUNT < 1 THEN
                            CONFIG_COUNT <= CONFIG_COUNT + 1;
                            STATE <= CONFIGURE;
                        ELSE
                            CONFIG_COUNT <= 0;
                            STATE <= READ_DATA;
                        END IF;
                    END IF;
                WHEN READ_DATA =>
                    IF SPI_DATA_RD = X"E5" THEN
                        DATA_VALID <= '1';
                    ELSE
                        DATA_VALID <= '0';
                    END IF;
                    STATE <= IDLE;

                WHEN OTHERS =>
            END CASE;
        END IF;
    END PROCESS;

END ARCHITECTURE;