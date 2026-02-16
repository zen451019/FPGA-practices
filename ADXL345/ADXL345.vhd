LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ADXL345 IS
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        MOSI : OUT STD_LOGIC;
        MISO : IN STD_LOGIC;
        CS : BUFFER STD_LOGIC_VECTOR(0 DOWNTO 0);
        SCLK : BUFFER STD_LOGIC;

        X_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        Y_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        Z_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        READY : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF ADXL345 IS

    TYPE MACHINE IS (IDLE, POWER_UP_DELAY, INIT, WAIT_INIT_RISE, WAIT_INIT, START_READ, WAIT_READ, CAPTURE);
    SIGNAL STATE : MACHINE := IDLE;

    COMPONENT SPI_DRIVER
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
    END COMPONENT;

    CONSTANT CPOL : STD_LOGIC := '1';
    CONSTANT CPHA : STD_LOGIC := '1';
    CONSTANT CLK_DIVI : INTEGER := 5_000_000;
    CONSTANT CS_SELECT : INTEGER := 0;

    SIGNAL R_W : STD_LOGIC := '0';
    SIGNAL REG_ADDR : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL N : INTEGER := 1;
    SIGNAL DATA : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL START_S : STD_LOGIC := '0';

    SIGNAL RX_DATA : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL RX_VALID : STD_LOGIC := '0';
    SIGNAL RX_VALID_PREV : STD_LOGIC := '0';
    SIGNAL RX_VALID_PULSE : STD_LOGIC := '0';
    SIGNAL BUSY : STD_LOGIC;
    SIGNAL DONE : STD_LOGIC;
    SIGNAL DONE_PREV : STD_LOGIC := '0';
    SIGNAL DONE_PULSE : STD_LOGIC := '0';

    SIGNAL DELAY : INTEGER RANGE 0 TO 1000000 := 0;
    CONSTANT DELAY_5MS : INTEGER := 250_000; -- 5ms @ 50MHz

    SIGNAL INIT_CYCLES : INTEGER RANGE 0 TO 3 := 0;
    SIGNAL CAPUTURE_CYCLES : INTEGER RANGE 0 TO 6 := 0;

    CONSTANT DATA_FORMAT_H : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"31";
    CONSTANT DATA_FORMAT_L : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"0B";

    CONSTANT BW_RATE_H : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"2C";
    CONSTANT BW_RATE_L : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"0A";

    CONSTANT POWER_CTL_H : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"2D";
    CONSTANT POWER_CTL_L : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"08";

    SIGNAL START_SHOT : STD_LOGIC := '0';

    CONSTANT REG_ADDR_READ : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"F2";

BEGIN

    START_S <= START_SHOT;

    SPI_DRIVER_INST : SPI_DRIVER
    PORT MAP(
        CLK => CLK,
        RESET => RESET,
        MOSI => MOSI,
        MISO => MISO,
        CS => CS,
        SCLK => SCLK,

        CPOL => CPOL,
        CPHA => CPHA,
        CLK_DIVI => CLK_DIVI,
        CS_SELECT => CS_SELECT,

        R_W => R_W,
        REG_ADDR => REG_ADDR,
        N => N,
        DATA => DATA,
        START_S => START_S,

        RX_DATA => RX_DATA,
        RX_VALID => RX_VALID,
        BUSY => BUSY,
        DONE => DONE
    );

    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '1' THEN
            STATE <= IDLE;
            REG_ADDR <= (OTHERS => '0');
            DATA <= (OTHERS => '0');
            X_OUT <= (OTHERS => '0');
            Y_OUT <= (OTHERS => '0');
            Z_OUT <= (OTHERS => '0');
            READY <= '0';
        ELSIF RISING_EDGE(CLK) THEN

            START_SHOT <= '0';
            DONE_PREV <= DONE;
            DONE_PULSE <= DONE AND (NOT DONE_PREV);

            RX_VALID_PREV <= RX_VALID;
            RX_VALID_PULSE <= RX_VALID AND (NOT RX_VALID_PREV);

            READY <= '0';

            CASE STATE IS
                WHEN IDLE =>
                    IF BUSY = '0' THEN
                        STATE <= POWER_UP_DELAY;
                        DELAY <= 0;
                    END IF;
                WHEN POWER_UP_DELAY =>
                    IF DELAY < DELAY_5MS THEN
                        DELAY <= DELAY + 1;
                    ELSE
                        DELAY <= 0;
                        STATE <= INIT;
                    END IF;
                WHEN INIT =>
                    IF INIT_CYCLES < 3 THEN
                        INIT_CYCLES <= INIT_CYCLES + 1;
                        CASE INIT_CYCLES IS
                            WHEN 0 =>
                                REG_ADDR <= DATA_FORMAT_H; -- DATA_FORMAT register
                                DATA <= DATA_FORMAT_L;
                            WHEN 1 =>
                                REG_ADDR <= BW_RATE_H; -- BW_RATE
                                DATA <= BW_RATE_L;
                            WHEN 2 =>
                                REG_ADDR <= POWER_CTL_H; -- POWER_CTL
                                DATA <= POWER_CTL_L;
                            WHEN OTHERS =>
                        END CASE;
                        R_W <= '0'; -- Write
                        N <= 1;
                        START_SHOT <= '1';
                        STATE <= WAIT_INIT;
                    ELSE
                        INIT_CYCLES <= 0;
                        STATE <= START_READ;
                    END IF;
                WHEN WAIT_INIT =>
                    IF DONE_PULSE = '1' THEN
                        STATE <= INIT;
                    END IF;
                WHEN START_READ =>
                    IF BUSY = '0' THEN
                        REG_ADDR <= REG_ADDR_READ; -- DATAX0 register
                        R_W <= '1'; -- Read
                        N <= 6; -- Read 6 bytes (X0, X1, Y0, Y1, Z0, Z1)
                        START_SHOT <= '1';
                        STATE <= WAIT_READ;
                    END IF;
                WHEN WAIT_READ =>
                    IF RX_VALID_PULSE = '1' THEN
                        STATE <= CAPTURE;
                    END IF;
                WHEN CAPTURE =>
                    CASE CAPUTURE_CYCLES IS
                        WHEN 0 =>
                            X_OUT(7 DOWNTO 0) <= RX_DATA;
                        WHEN 1 =>
                            X_OUT(15 DOWNTO 8) <= RX_DATA;
                        WHEN 2 =>
                            Y_OUT(7 DOWNTO 0) <= RX_DATA;
                        WHEN 3 =>
                            Y_OUT(15 DOWNTO 8) <= RX_DATA;
                        WHEN 4 =>
                            Z_OUT(7 DOWNTO 0) <= RX_DATA;
                        WHEN 5 =>
                            Z_OUT(15 DOWNTO 8) <= RX_DATA;
                        WHEN OTHERS =>
                    END CASE;
                    IF CAPUTURE_CYCLES < 6 THEN
                        CAPUTURE_CYCLES <= CAPUTURE_CYCLES + 1;
                        STATE <= WAIT_READ;
                    ELSE
                        CAPUTURE_CYCLES <= 0;
                        READY <= '1';
                        STATE <= START_READ; -- Continuously read data
                    END IF;
                WHEN OTHERS =>
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;