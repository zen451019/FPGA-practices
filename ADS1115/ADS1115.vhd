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
    TYPE MACHINE IS (IDLE, CONFIGURE, START_CONVERSION, WAIT_CONVERSION, READ_DATA, WAIT_I2C_BUSY, WAIT_I2C_DONE);
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
    SIGNAL COUNT : INTEGER RANGE 0 TO 2 := 0;
    

BEGIN

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
        ELSIF rising_edge(CLK) THEN
            CASE STATE IS
                WHEN IDLE =>
                IF START_CONV = '1' AND BUSY_I2C = '0' THEN
                    IF CONFIG_EN = '1' THEN
                        CONFIG_REG <= BUILD_CONFIG_REG(CHANNEL, PGA, DATA_RATE, CONTINUOUS);
                    END IF;
                    STATE <= CONFIGURE;
                END IF;

                WHEN CONFIGURE =>
                    EN <= '1';
                    RW <= '0'; -- Write
                    
                    CASE COUNT IS
                        WHEN 0 => DATA_WR <= ADS1115_POINTER_CONFIG; -- 0x01 = Pointer to Config Register
                        WHEN 1 => DATA_WR <= CONFIG_REG(15 DOWNTO 8); -- MSB
                        WHEN 2 => DATA_WR <= CONFIG_REG(7 DOWNTO 0);  -- LSB
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
                        IF COUNT = 2 THEN
                            COUNT <= 0;
                            STATE <= START_CONVERSION;
                        ELSE
                            COUNT <= COUNT + 1;
                            STATE <= STATE_AFTER_WAIT; 
                        END IF;
                    END IF;

                WHEN WAIT_CONVERSION =>
                    -- Esperar a que la conversión esté lista
                    -- (Implementación de espera aquí)
                    CONV_READY <= '1';
                    STATE <= READ_DATA;
                
                WHEN START_CONVERSION =>
                    -- Iniciar conversión (Implementación I2C aquí)
                    STATE <= WAIT_CONVERSION;

                WHEN READ_DATA =>
                    -- Leer los datos convertidos (Implementación I2C aquí)
                    DATA_OUT <= DATA_RD & DATA_RD; -- Suponiendo lectura de 16 bits en dos partes
                    CONV_READY <= '0';
                    STATE <= IDLE;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;