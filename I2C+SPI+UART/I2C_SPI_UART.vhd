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

        --UART Interface
        UART_BUSY : IN STD_LOGIC;
        UART_TX : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        UART_READY : OUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF I2C_SPI_UART IS

    TYPE PACKET_BUILDER IS (IDLE, HEADER, DATA_LENGTH, PAYLOAD, CHECKSUM, DONE, WRITE_FIFO);
    SIGNAL STATE : PACKET_BUILDER := IDLE;
    SIGNAL RETURN_STATE : PACKET_BUILDER := IDLE; -- state to return to after WRITE_FIFO

    TYPE UART_STATE_TYPE IS (
        U_IDLE,
        U_RDREQ,
        U_LATCH,
        U_SEND,
        U_WAIT_UART
    );
    SIGNAL UART_STATE : UART_STATE_TYPE := U_IDLE;

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
    SIGNAL SPI_BUFFER : STD_LOGIC_VECTOR(47 DOWNTO 0) := (OTHERS => '0');
    SIGNAL I2C_BUFFER : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- Active buffers (double-buffered to prevent mid-packet corruption)
    SIGNAL SPI_ACTIVE_BUFFER : STD_LOGIC_VECTOR(47 DOWNTO 0) := (OTHERS => '0');
    SIGNAL I2C_ACTIVE_BUFFER : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');

    -- Signal to track the current data source being processed
    SIGNAL PROCESSING_I2C : STD_LOGIC := '0'; -- '0' for SPI, '1' for I2C

    -- Contans for packet formatting
    CONSTANT SPI_HEADER : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"FE"; -- DIAGNOSTICO: unico, distinto de todo el payload
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
    SIGNAL SPI_READY_PREV : STD_LOGIC := '0';
    SIGNAL I2C_READY_PREV : STD_LOGIC := '0';

    -- 10 ms SPI sample timer (50 MHz clock → 500 000 cycles)
    CONSTANT SPI_SAMPLE_CYCLES : INTEGER := 2_500_000;
    SIGNAL SPI_SAMPLE_TIMER : INTEGER RANGE 0 TO 2_500_000 := 0;
    SIGNAL SPI_SAMPLE_TICK : STD_LOGIC := '0';

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
    UART_TX_PROC : PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            UART_STATE <= U_IDLE;
            rdreq_sig <= '0';
            UART_READY <= '0';
            UART_TX <= (OTHERS => '0');
        ELSIF RISING_EDGE(CLK) THEN

            UART_READY <= '0';
            rdreq_sig <= '0';

            CASE UART_STATE IS

                WHEN U_IDLE =>
                    IF empty_sig = '0' AND UART_BUSY = '0' THEN
                        rdreq_sig <= '1';
                        UART_STATE <= U_RDREQ;
                    END IF;

                WHEN U_RDREQ =>
                    -- esperar 1 ciclo para que q sea válido
                    UART_STATE <= U_LATCH;

                WHEN U_LATCH =>
                    UART_TX <= q_sig; -- registrar dato estable
                    UART_STATE <= U_SEND;

                WHEN U_SEND =>
                    UART_READY <= '1'; -- pulso limpio
                    UART_STATE <= U_WAIT_UART;

                WHEN U_WAIT_UART =>
                    IF UART_BUSY = '1' THEN
                        UART_READY <= '0';
                    END IF;

                    IF UART_BUSY = '0' THEN
                        UART_STATE <= U_IDLE;
                    END IF;

            END CASE;
        END IF;
    END PROCESS UART_TX_PROC;

    PACKET_BUILDER_PROC : PROCESS (CLK, RESET)
    BEGIN

        IF RESET = '0' THEN
            STATE <= IDLE;
            RETURN_STATE <= IDLE;
            wrreq_sig <= '0';
            data_sig <= (OTHERS => '0');
            SPI_PEDING <= '0';
            I2C_PENDING <= '0';
            PAYLOAD_COUNTER <= 0;
            CHECKSUM_ACC <= (OTHERS => '0');
            PROCESSING_I2C <= '0';
            NEXT_PRIORITY <= '0';
            SPI_BUFFER <= (OTHERS => '0');
            I2C_BUFFER <= (OTHERS => '0');
            SPI_ACTIVE_BUFFER <= (OTHERS => '0');
            I2C_ACTIVE_BUFFER <= (OTHERS => '0');
            SPI_READY_PREV <= '0';
            I2C_READY_PREV <= '0';
            SPI_SAMPLE_TIMER <= 0;
            SPI_SAMPLE_TICK <= '0';

        ELSIF RISING_EDGE(CLK) THEN

            -- Store previous states of SPI_READY and I2C_READY
            SPI_READY_PREV <= SPI_READY;
            I2C_READY_PREV <= I2C_READY;

            -- 10 ms free-running timer
            SPI_SAMPLE_TICK <= '0';
            IF SPI_SAMPLE_TIMER = SPI_SAMPLE_CYCLES - 1 THEN
                SPI_SAMPLE_TIMER <= 0;
                SPI_SAMPLE_TICK <= '1';
            ELSE
                SPI_SAMPLE_TIMER <= SPI_SAMPLE_TIMER + 1;
            END IF;

            -- Default assignments to avoid latches
            wrreq_sig <= '0';

            CASE STATE IS
                WHEN IDLE =>
                    IF SPI_PEDING = '1' AND (NEXT_PRIORITY = '0' OR I2C_PENDING = '0') THEN
                        PROCESSING_I2C <= '0';
                        -- TEMPORAL: patron de prueba para diagnostico (todos los bytes son unicos)
                        -- Paquete esperado: FE 06 11 22 33 44 55 66 C3
                        -- FE=header  06=len  11 22 33 44 55 66=payload  C3=checksum(sum mod256)
                        SPI_ACTIVE_BUFFER <= SPI_BUFFER;
                        STATE <= HEADER;
                    ELSIF I2C_PENDING = '1' THEN
                        PROCESSING_I2C <= '1';
                        -- TEMPORAL: patron de prueba para diagnostico
                        I2C_ACTIVE_BUFFER <= I2C_BUFFER;
                        STATE <= HEADER;
                    END IF;

                WHEN HEADER =>
                    -- Latch data_sig this cycle; WRITE_FIFO will assert wrreq next cycle
                    IF full_sig = '0' THEN
                        IF PROCESSING_I2C = '0' THEN
                            data_sig <= SPI_HEADER;
                        ELSE
                            data_sig <= I2C_HEADER;
                        END IF;
                        RETURN_STATE <= DATA_LENGTH;
                        STATE <= WRITE_FIFO;
                    END IF;

                WHEN DATA_LENGTH =>
                    -- Latch data_sig this cycle; WRITE_FIFO will assert wrreq next cycle
                    IF full_sig = '0' THEN
                        IF PROCESSING_I2C = '0' THEN
                            data_sig <= STD_LOGIC_VECTOR(TO_UNSIGNED(SPI_BYTES_LENGTH, 8));
                        ELSE
                            data_sig <= STD_LOGIC_VECTOR(TO_UNSIGNED(I2C_BYTES_LENGTH, 8));
                        END IF;
                        CHECKSUM_ACC <= (OTHERS => '0');
                        RETURN_STATE <= PAYLOAD;
                        STATE <= WRITE_FIFO;
                    END IF;

                WHEN PAYLOAD =>
                    -- Latch the current byte this cycle; WRITE_FIFO will assert wrreq next cycle
                    -- After writing, WRITE_FIFO returns here (RETURN_STATE=PAYLOAD) to send the next byte
                    IF full_sig = '0' THEN
                        IF PROCESSING_I2C = '0' THEN
                            IF PAYLOAD_COUNTER < SPI_BYTES_LENGTH THEN
                                data_sig <= SPI_ACTIVE_BUFFER(SPI_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO SPI_MIN_BITES - (PAYLOAD_COUNTER * 8));
                                CHECKSUM_ACC <= CHECKSUM_ACC + UNSIGNED(SPI_ACTIVE_BUFFER(SPI_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO SPI_MIN_BITES - (PAYLOAD_COUNTER * 8)));
                                PAYLOAD_COUNTER <= PAYLOAD_COUNTER + 1;
                                RETURN_STATE <= PAYLOAD;
                                STATE <= WRITE_FIFO;
                            ELSE
                                PAYLOAD_COUNTER <= 0;
                                STATE <= CHECKSUM;
                            END IF;
                        ELSE
                            IF PAYLOAD_COUNTER < I2C_BYTES_LENGTH THEN
                                data_sig <= I2C_ACTIVE_BUFFER(I2C_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO I2C_MIN_BITES - (PAYLOAD_COUNTER * 8));
                                CHECKSUM_ACC <= CHECKSUM_ACC + UNSIGNED(I2C_ACTIVE_BUFFER(I2C_MAX_BITES - (PAYLOAD_COUNTER * 8) DOWNTO I2C_MIN_BITES - (PAYLOAD_COUNTER * 8)));
                                PAYLOAD_COUNTER <= PAYLOAD_COUNTER + 1;
                                RETURN_STATE <= PAYLOAD;
                                STATE <= WRITE_FIFO;
                            ELSE
                                PAYLOAD_COUNTER <= 0;
                                STATE <= CHECKSUM;
                            END IF;
                        END IF;
                    END IF;

                WHEN CHECKSUM =>
                    -- Latch checksum this cycle; WRITE_FIFO will assert wrreq next cycle
                    IF full_sig = '0' THEN
                        data_sig <= STD_LOGIC_VECTOR(CHECKSUM_ACC);
                        RETURN_STATE <= DONE;
                        STATE <= WRITE_FIFO;
                    END IF;

                WHEN WRITE_FIFO =>
                    -- data_sig is already stable from the previous cycle; assert wrreq now
                    IF full_sig = '0' THEN
                        wrreq_sig <= '1';
                        STATE <= RETURN_STATE;
                    END IF;

                WHEN DONE =>
                    -- Clear the pending flag for the source that was JUST processed
                    IF PROCESSING_I2C = '0' THEN
                        SPI_PEDING <= '0';
                        NEXT_PRIORITY <= '1'; -- Next time give I2C priority
                    ELSE
                        I2C_PENDING <= '0';
                        NEXT_PRIORITY <= '0'; -- Next time give SPI priority
                    END IF;
                    STATE <= IDLE; -- Transition back to IDLE after processing
                WHEN OTHERS =>
                    NULL; -- Placeholder for additional state handling logic

            END CASE;

            -- Always keep SPI_BUFFER fresh with the latest sensor reading
            IF SPI_READY = '1' AND SPI_READY_PREV = '0' THEN
                SPI_BUFFER <= FORMAT_SPI_DATA(SPI_X_OUT, SPI_Y_OUT, SPI_Z_OUT);
            END IF;

            -- Only trigger a SPI packet every 10 ms
            IF SPI_SAMPLE_TICK = '1' THEN
                SPI_PEDING <= '1';
            END IF;

            -- I2C is still event-driven (no rate limit)
            IF I2C_READY = '1' AND I2C_READY_PREV = '0' THEN
                I2C_BUFFER <= I2C_DATA_OUT;
                I2C_PENDING <= '1';
            END IF;

        END IF;
    END PROCESS PACKET_BUILDER_PROC;
END ARCHITECTURE;