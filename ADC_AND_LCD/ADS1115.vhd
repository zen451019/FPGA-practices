LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY ADS1115 IS
    PORT (
        -- System
        CLK         : IN STD_LOGIC;
        RESET       : IN STD_LOGIC;
        
        -- Configuration
        CONFIG_EN   : IN STD_LOGIC;                      -- Enable para cargar configuración
        CHANNEL     : IN STD_LOGIC_VECTOR(2 DOWNTO 0);  -- Canal (000-011: single, 100-111: diff)
        PGA         : IN STD_LOGIC_VECTOR(2 DOWNTO 0);  -- Ganancia: 000=±6.144V, 001=±4.096V, 010=±2.048V, etc.
        DATA_RATE   : IN STD_LOGIC_VECTOR(2 DOWNTO 0);  -- 000=8SPS, 001=16SPS, ... 111=860SPS
        CONTINUOUS  : IN STD_LOGIC;                      -- '0'=Single-shot, '1'=Continuous
        
        -- Control
        START_CONV  : IN STD_LOGIC;                      -- Inicia conversión
        
        -- Status & Data
        CONV_READY  : OUT STD_LOGIC;
        DATA_OUT    : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        BUSY        : OUT STD_LOGIC;
        
        -- I2C
        SDA         : INOUT STD_LOGIC;
        SCL         : INOUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF ADS1115 IS 
    TYPE MACHINE IS (IDLE, CONFIGURE, WAIT_CONVERSION, READ_DATA, WAIT_I2C_BUSY, WAIT_I2C_DONE);
    SIGNAL STATE : MACHINE := IDLE;
    SIGNAL STATE_AFTER_WAIT : MACHINE := IDLE;

    COMPONENT I2C
        GENERIC (
            CLK_FREQ_HZ : INTEGER := 50000000;
            I2C_FREQ_HZ : INTEGER := 100000
        );
        PORT (
            CLK : IN STD_LOGIC;
            RESET : IN STD_LOGIC;
            EN : IN STD_LOGIC;
            ADDR : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
            RW : IN STD_LOGIC;
            DATA_WR : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            BUSY : OUT STD_LOGIC;
            DATA_RD : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            ACK_ERR : BUFFER STD_LOGIC;
            SDA : INOUT STD_LOGIC;
            SCL : INOUT STD_LOGIC
        );
    END COMPONENT;

    FUNCTION BUILD_CONFIG_REG (
        CHANNEL : STD_LOGIC_VECTOR(2 DOWNTO 0);
        PGA : STD_LOGIC_VECTOR(2 DOWNTO 0);
        DATA_RATE : STD_LOGIC_VECTOR(2 DOWNTO 0);
        CONTINUOUS : STD_LOGIC
    ) RETURN STD_LOGIC_VECTOR IS
        VARIABLE CONFIG : STD_LOGIC_VECTOR(15 DOWNTO 0);
    BEGIN
        IF CONTINUOUS = '0' THEN
            CONFIG(15) := '1'; -- Start single conversion
        ELSE   
            CONFIG(15) := '0'; -- Continuous mode
        END IF;
        
        CONFIG(14 DOWNTO 12) := CHANNEL; -- MUX
        CONFIG(11 DOWNTO 9) := PGA;       -- PGA
        CONFIG(8) := NOT CONTINUOUS;      -- Mode (1=single-shot, 0=continuous)
        CONFIG(7 DOWNTO 5) := DATA_RATE;  -- Data rate
        CONFIG(4 DOWNTO 0) := "00011"; -- Comparator disabled
        RETURN CONFIG;
    END FUNCTION;

    SIGNAL MAX_WAIT : INTEGER;

FUNCTION CALC_MAX_WAIT (DATA_RATE : STD_LOGIC_VECTOR(2 DOWNTO 0)) RETURN INTEGER IS
BEGIN
    CASE DATA_RATE IS
        -- Valores calculados: (1/SPS) * 1.2 * 50,000,000
        WHEN "000" => RETURN 7500000; -- 8SPS   (teórico 125ms -> espera 150ms)
        WHEN "001" => RETURN 3750000; -- 16SPS  (teórico 62.5ms -> espera 75ms)
        WHEN "010" => RETURN 1875000; -- 32SPS  (teórico 31.2ms -> espera 37.5ms)
        WHEN "011" => RETURN 937500;  -- 64SPS  (teórico 15.6ms -> espera 18.7ms)
        WHEN "100" => RETURN 468750;  -- 128SPS (teórico 7.8ms -> espera 9.3ms)
        WHEN "101" => RETURN 240000;  -- 250SPS (teórico 4ms -> espera 4.8ms)
        WHEN "110" => RETURN 126315;  -- 475SPS (teórico 2.1ms -> espera 2.5ms)
        WHEN OTHERS => RETURN 69767;  -- 860SPS (teórico 1.16ms -> espera 1.4ms)
    END CASE;
END FUNCTION;

    SIGNAL EN : STD_LOGIC;
    CONSTANT I2C_ADDRESS : STD_LOGIC_VECTOR(6 DOWNTO 0) := "1001000"; -- Dirección I2C del ADS1115
    SIGNAL RW : STD_LOGIC;
    SIGNAL DATA_WR : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL BUSY_I2C : STD_LOGIC;
    SIGNAL DATA_RD : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL ACK_ERR : STD_LOGIC;


    CONSTANT ADS1115_POINTER_CONVERSION : STD_LOGIC_VECTOR(7 DOWNTO 0) := "00000000";
    CONSTANT ADS1115_POINTER_CONFIG     : STD_LOGIC_VECTOR(7 DOWNTO 0) := "00000001";
    SIGNAL CONFIG_REG : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL CONFIGURED : STD_LOGIC := '0'; -- Indica si ya se configuró en modo continuo
    SIGNAL BYTE_COUNT : INTEGER RANGE 0 TO 2 := 0;
    SIGNAL WAIT_COUNT : INTEGER := 0;
    

BEGIN

    -- Nuevo: BUSY de salida
    BUSY <= '1' WHEN STATE /= IDLE ELSE '0';

    U_I2C : I2C
    PORT MAP (
        CLK => CLK,
        RESET => RESET,
        EN => EN,
        ADDR => I2C_ADDRESS,
        RW => RW,
        DATA_WR => DATA_WR,
        BUSY => BUSY_I2C,
        DATA_RD => DATA_RD,
        ACK_ERR => ACK_ERR,
        SDA => SDA,
        SCL => SCL
    );

    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            CONV_READY <= '0';
            DATA_OUT <= (OTHERS => '0');
            EN <= '0';
            RW <= '0';
            DATA_WR <= (OTHERS => '0');
            CONFIGURED <= '0';
            BYTE_COUNT <= 0;
            WAIT_COUNT <= 0;
            MAX_WAIT <= 0; -- Nuevo: init seguro
        ELSIF rising_edge(CLK) THEN
            CASE STATE IS
                WHEN IDLE =>
                    CONV_READY <= '0';
                    EN <= '0';
                    IF START_CONV = '1' AND BUSY_I2C = '0' THEN
                        -- Asegurar configuración y tiempo siempre
                        CONFIG_REG <= BUILD_CONFIG_REG(CHANNEL, PGA, DATA_RATE, CONTINUOUS);
                        MAX_WAIT   <= CALC_MAX_WAIT(DATA_RATE);

                        IF CONFIG_EN = '1' THEN
                            CONFIGURED <= '0'; -- Forzar reconfiguración
                            STATE <= CONFIGURE;
                        ELSIF CONTINUOUS = '1' AND CONFIGURED = '1' THEN
                            STATE <= WAIT_CONVERSION; -- ya configurado
                        ELSE
                            STATE <= CONFIGURE; -- single-shot o primera vez continuo
                        END IF;
                    END IF;

                WHEN CONFIGURE =>
                    EN <= '1';
                    RW <= '0'; -- Write
                    
                    CASE BYTE_COUNT IS
                        WHEN 0 => DATA_WR <= ADS1115_POINTER_CONFIG; -- 0x01
                        WHEN 1 => DATA_WR <= CONFIG_REG(15 DOWNTO 8); -- MSB
                        WHEN 2 => DATA_WR <= CONFIG_REG(7 DOWNTO 0);  -- LSB
                        WHEN OTHERS => NULL;
                    END CASE;
                    
                    STATE <= WAIT_I2C_BUSY;
                    STATE_AFTER_WAIT <= CONFIGURE;
                
                WHEN WAIT_I2C_BUSY =>
                    IF BUSY_I2C = '1' THEN
                        STATE <= WAIT_I2C_DONE;
                    END IF;

                WHEN WAIT_I2C_DONE =>
                    IF BUSY_I2C = '0' THEN
                        EN <= '0'; -- Disable I2C
                        IF STATE_AFTER_WAIT = CONFIGURE THEN
                            IF BYTE_COUNT = 2 THEN
                                BYTE_COUNT <= 0;
                                CONFIGURED <= '1';
                                WAIT_COUNT <= 0;
                                STATE <= WAIT_CONVERSION;
                            ELSE
                                BYTE_COUNT <= BYTE_COUNT + 1;
                                STATE <= CONFIGURE;
                            END IF;
                        ELSIF STATE_AFTER_WAIT = READ_DATA THEN
                            IF BYTE_COUNT = 2 THEN
                                BYTE_COUNT <= 0;
                                CONV_READY <= '1';
                                STATE <= IDLE;
                            ELSE
                                BYTE_COUNT <= BYTE_COUNT + 1;
                                STATE <= READ_DATA;
                            END IF;
                        END IF;
                    END IF;

                WHEN WAIT_CONVERSION =>
                    IF WAIT_COUNT < MAX_WAIT THEN
                        WAIT_COUNT <= WAIT_COUNT + 1;
                    ELSE
                        WAIT_COUNT <= 0;
                        BYTE_COUNT <= 0;
                        STATE <= READ_DATA;
                    END IF;
                
                WHEN READ_DATA =>
                    EN <= '1';
                    
                    CASE BYTE_COUNT IS
                        WHEN 0 => 
                            RW <= '0'; -- Write
                            DATA_WR <= ADS1115_POINTER_CONVERSION; -- 0x00
                        WHEN 1 => 
                            RW <= '1'; -- Read
                            DATA_OUT(15 DOWNTO 8) <= DATA_RD; -- MSB
                        WHEN 2 => 
                            RW <= '1'; -- Read
                            DATA_OUT(7 DOWNTO 0) <= DATA_RD; -- LSB
                        WHEN OTHERS => NULL;
                    END CASE;
                    
                    STATE <= WAIT_I2C_BUSY;
                    STATE_AFTER_WAIT <= READ_DATA;
            END CASE;
        END IF;
    END PROCESS;
   END ARCHITECTURE;