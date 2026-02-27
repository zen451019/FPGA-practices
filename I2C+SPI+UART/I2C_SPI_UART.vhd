LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY I2C_SPI_UART IS
    GENERIC (
        SPI_BYTES_LENGTH : INTEGER := 6; -- 6 bytes for SPI data (X, Y, Z each 2 bytes)
        I2C_BYTES_LENGTH : INTEGER := 2 -- 2 bytes for I2C data
    );
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;

        -- SPI Interface       
        SPI_X_OUT : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        SPI_Y_OUT : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        SPI_Z_OUT : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        SPI_READY : IN STD_LOGIC;

        -- I2C Interface
        I2C_READY : IN STD_LOGIC;
        I2C_DATA_OUT : IN STD_LOGIC_VECTOR(15 DOWNTO 0);

        --UART Output
        UART_TX : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        UART_READY : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF I2C_SPI_UART IS

    TYPE PACKET_BUILDER IS (IDLE, HEADER, DATA_LENGTH, PAYLOAD, CHECKSUM, DONE);
    SIGNAL STATE : PACKET_BUILDER := IDLE;

    COMPONENT FIFO
        PORT (
            clock : IN STD_LOGIC;
            data : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            rdreq : IN STD_LOGIC;
            wrreq : IN STD_LOGIC;
            empty : OUT STD_LOGIC;
            full : OUT STD_LOGIC;
            q : OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
        );
    END COMPONENT;

    -- Signals for FIFO
    SIGNAL data_sig : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL rdreq_sig : STD_LOGIC := '0';
    SIGNAL wrreq_sig : STD_LOGIC := '0';
    SIGNAL empty_sig : STD_LOGIC;
    SIGNAL full_sig : STD_LOGIC;
    SIGNAL q_sig : STD_LOGIC_VECTOR(7 DOWNTO 0);

    -- peding signals for SPI and I2C data processing
    SIGNAL SPI_PEDING : STD_LOGIC := '0';
    SIGNAL I2C_PENDING : STD_LOGIC := '0';
    SIGNAL SPI_BUFFER : STD_LOGIC_VECTOR(47 DOWNTO 0);
    SIGNAL I2C_BUFFER : STD_LOGIC_VECTOR(15 DOWNTO 0);

    -- Signal to track the current data source being processed
    SIGNAL PROCESSING_I2C : STD_LOGIC := '0'; -- '0' for SPI, '1' for I2C

    -- Contans for packet formatting
    CONSTANT SPI_HEADER : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"65";
    CONSTANT I2C_HEADER : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"C8";

    -- SPI data formatting function
    FUNCTION FORMAT_SPI_DATA(x : STD_LOGIC_VECTOR(15 DOWNTO 0); y : STD_LOGIC_VECTOR(15 DOWNTO 0); z : STD_LOGIC_VECTOR(15 DOWNTO 0)) RETURN STD_LOGIC_VECTOR IS
        VARIABLE formatted : STD_LOGIC_VECTOR(47 DOWNTO 0);
    BEGIN
        formatted := x & y & z;
        RETURN formatted;
    END FUNCTION FORMAT_SPI_DATA;

    -- Flag to indiciate which data is the next to be processed
    SIGNAL NEXT_PRIORITY : STD_LOGIC := '0'; -- '0' for SPI, '1' for I2C

    --BITES length constants for packet formatting
    CONSTANT SPI_BIT_LENGTH : INTEGER := SPI_BYTES_LENGTH * 8; -- Total bits for SPI payload
    CONSTANT I2C_BIT_LENGTH : INTEGER := I2C_BYTES_LENGTH * 8; -- Total bits for I2C payload
    CONSTANT SPI_MAX_BITES : INTEGER := SPI_BIT_LENGTH - 1; -- Max index for SPI payload bits
    CONSTANT SPI_MIN_BITES : INTEGER := SPI_BIT_LENGTH - 8; -- Min index for the last byte of SPI payload
    CONSTANT I2C_MAX_BITES : INTEGER := I2C_BIT_LENGTH - 1; -- Max index for I2C payload bits
    CONSTANT I2C_MIN_BITES : INTEGER := I2C_BIT_LENGTH - 8; -- Min index for the last byte of I2C payload

    -- COUNTER for payload bytes
    SIGNAL PAYLOAD_COUNTER : INTEGER := 0;
    SIGNAL CHECKSUM_ACC : UNSIGNED(7 DOWNTO 0) := (OTHERS => '0');

    -- Signals to detect rising edges of SPI_READY and I2C_READY
    SIGNAL SPI_READY_PREV  : STD_LOGIC := '0';
    SIGNAL I2C_READY_PREV  : STD_LOGIC := '0';
    SIGNAL SPI_READY_PULSE : STD_LOGIC := '0';
    SIGNAL I2C_READY_PULSE : STD_LOGIC := '0';

BEGIN
    FIFO_inst : FIFO PORT MAP(
        clock => CLK,
        data => data_sig,
        rdreq => rdreq_sig,
        wrreq => wrreq_sig,
        empty => empty_sig,
        full => full_sig,
        q => q_sig
    );

    PROCESS (CLK, RESET)
    BEGIN

        IF RESET = '1' THEN
            STATE <= IDLE;
            rdreq_sig <= '0';
            SPI_PEDING <= '0';
            I2C_PENDING <= '0';
            PAYLOAD_COUNTER <= 0;

        ELSIF RISING_EDGE(CLK) THEN

            -- Store previous states of SPI_READY and I2C_READY
            SPI_READY_PREV <= SPI_READY;
            I2C_READY_PREV <= I2C_READY;

            -- Generate pulses on rising edge of SPI_READY and I2C_READY
            SPI_READY_PULSE <= SPI_READY AND NOT SPI_READY_PREV;
            I2C_READY_PULSE <= I2C_READY AND NOT I2C_READY_PREV;

            -- Capture data into buffers and set pending flags on rising edge of ready signals
            IF SPI_READY_PULSE = '1' THEN
                SPI_BUFFER <= FORMAT_SPI_DATA(SPI_X_OUT, SPI_Y_OUT, SPI_Z_OUT);
                SPI_PEDING <= '1';
            END IF;
            IF I2C_READY_PULSE = '1' THEN
                I2C_BUFFER <= I2C_DATA_OUT;
                I2C_PENDING <= '1';
            END IF;

            -- Default assignments to avoid latches
            wrreq_sig <= '0';

            CASE STATE IS
                WHEN IDLE =>
                    IF SPI_PEDING = '1' AND (NEXT_PRIORITY = '0' OR I2C_PENDING = '0') THEN
                        PROCESSING_I2C <= '0';
                        STATE <= HEADER;
                    ELSIF I2C_PENDING = '1' THEN
                        PROCESSING_I2C <= '1';
                        STATE <= HEADER;
                    END IF;

                WHEN HEADER =>
                    -- Write the selected header to the FIFO
                    IF full_sig = '0' THEN -- Check if FIFO is not full
                        IF PROCESSING_I2C = '0' THEN
                            data_sig <= SPI_HEADER;
                        ELSE
                            data_sig <= I2C_HEADER;
                        END IF;
                        wrreq_sig <= '1'; -- Write the header to FIFO
                        STATE <= DATA_LENGTH; -- Transition to DATA_LENGTH state
                    END IF;

                WHEN DATA_LENGTH =>
                    -- Write the data length to the FIFO
                    IF full_sig = '0' THEN -- Check if FIFO is not full
                        IF PROCESSING_I2C = '0' THEN
                            data_sig <= STD_LOGIC_VECTOR(TO_UNSIGNED(SPI_BYTES_LENGTH, 8));

                        ELSE
                            data_sig <= STD_LOGIC_VECTOR(TO_UNSIGNED(I2C_BYTES_LENGTH, 8));
                        END IF;
                        wrreq_sig <= '1'; -- Write the data length to FIFO
                        CHECKSUM_ACC <= (OTHERS => '0'); -- Reset checksum accumulator
                        STATE <= PAYLOAD; -- Transition to PAYLOAD state
                    END IF;

                WHEN PAYLOAD =>
                    -- Write the payload data to the FIFO
                    IF full_sig = '0' THEN -- Check if FIFO is not full
                        IF PROCESSING_I2C = '0' THEN
                            IF PAYLOAD_COUNTER < SPI_BYTES_LENGTH THEN
                                data_sig <= SPI_BUFFER(SPI_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO SPI_MIN_BITES - (PAYLOAD_COUNTER * 8));
                                wrreq_sig <= '1';
                                CHECKSUM_ACC <= CHECKSUM_ACC + UNSIGNED(SPI_BUFFER(SPI_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO SPI_MIN_BITES - (PAYLOAD_COUNTER * 8)));
                                PAYLOAD_COUNTER <= PAYLOAD_COUNTER + 1;
                            ELSE
                                PAYLOAD_COUNTER <= 0;
                                STATE <= CHECKSUM;
                            END IF;
                        ELSE
                            IF PAYLOAD_COUNTER < I2C_BYTES_LENGTH THEN
                                data_sig <= I2C_BUFFER(I2C_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO I2C_MIN_BITES - (PAYLOAD_COUNTER * 8));
                                wrreq_sig <= '1';
                                CHECKSUM_ACC <= CHECKSUM_ACC + UNSIGNED(I2C_BUFFER(I2C_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO I2C_MIN_BITES - (PAYLOAD_COUNTER * 8)));
                                PAYLOAD_COUNTER <= PAYLOAD_COUNTER + 1;
                            ELSE
                                PAYLOAD_COUNTER <= 0;
                                STATE <= CHECKSUM;
                            END IF;
                        END IF;
                    END IF;

                WHEN CHECKSUM =>
                    IF full_sig = '0' THEN -- Check if FIFO is not full
                        -- Write the calculated checksum to the FIFO
                        data_sig <= STD_LOGIC_VECTOR(CHECKSUM_ACC);
                        wrreq_sig <= '1';
                        STATE <= DONE;
                    END IF;

                WHEN DONE =>
                    IF NEXT_PRIORITY = '0' THEN
                        IF SPI_PEDING = '1' THEN
                            SPI_PEDING <= '0';
                            NEXT_PRIORITY <= '1';
                        ELSIF I2C_PENDING = '1' THEN
                            I2C_PENDING <= '0';
                            -- Priority remains with SPI
                        END IF;
                    ELSE -- NEXT_PRIORITY = '1'
                        IF I2C_PENDING = '1' THEN
                            I2C_PENDING <= '0';
                            NEXT_PRIORITY <= '0'; -- Give priority to SPI next
                        ELSIF SPI_PEDING = '1' THEN
                            SPI_PEDING <= '0';
                            -- Priority remains with I2C
                        END IF;
                    END IF;
                    STATE <= IDLE; -- Transition back to IDLE after processing
                WHEN OTHERS =>
                    NULL; -- Placeholder for additional state handling logic

            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;