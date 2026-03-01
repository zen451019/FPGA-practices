LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY SINGLE_SHOT IS
    PORT (
        CLK : IN STD_LOGIC;
        RESET : IN STD_LOGIC;
        DATA_VALID : OUT STD_LOGIC;
        DATA_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        SDA : INOUT STD_LOGIC;
        SCL : INOUT STD_LOGIC
    );
END ENTITY;

ARCHITECTURE COMP OF SINGLE_SHOT IS
    TYPE MACHINE IS (IDLE, SEND_COMMAND, WAIT_PIN);
    SIGNAL STATE : MACHINE := IDLE;

    COMPONENT ADS1115
        PORT (
            -- System
            CLK : IN STD_LOGIC;
            RESET : IN STD_LOGIC;

            -- Configuration
            CONFIG_EN : IN STD_LOGIC; -- Enable para cargar configuración
            CHANNEL : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- Canal (000-011: single, 100-111: diff)
            PGA : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- Ganancia: 000=±6.144V, 001=±4.096V, 010=±2.048V, etc.
            DATA_RATE : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- 000=8SPS, 001=16SPS, ... 111=860SPS
            CONTINUOUS : IN STD_LOGIC; -- '0'=Single-shot, '1'=Continuous

            -- Control
            START_CONV : IN STD_LOGIC; -- Inicia conversión

            -- Status & Data
            CONV_READY : OUT STD_LOGIC;
            DATA_OUT : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
            BUSY : OUT STD_LOGIC;

            -- I2C
            SDA : INOUT STD_LOGIC;
            SCL : INOUT STD_LOGIC
        );
    END COMPONENT;

    SIGNAL CONFIG_EN : STD_LOGIC := '0';
    SIGNAL CHANNEL : STD_LOGIC_VECTOR(2 DOWNTO 0) := "100"; -- AIN0 vs GND
    SIGNAL PGA : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000"; -- ±6.144V (ganancia 2/3, ideal para 3.3V)
    SIGNAL DATA_RATE : STD_LOGIC_VECTOR(2 DOWNTO 0) := "100"; -- 16 SPS
    SIGNAL CONTINUOUS : STD_LOGIC := '0';
    SIGNAL START_CONV : STD_LOGIC := '0';
    SIGNAL CONV_READY : STD_LOGIC;
    SIGNAL BUSY : STD_LOGIC;

    SIGNAL CONFIGURED : STD_LOGIC := '0';

BEGIN
    U_ADS1115 : ADS1115
    PORT MAP(
        CLK => CLK,
        RESET => RESET,
        CONFIG_EN => CONFIG_EN, -- Cargar configuración al inicio
        CHANNEL => CHANNEL, -- Canal AIN0
        PGA => PGA, -- Ganancia ±2.048V
        DATA_RATE => DATA_RATE, -- 128SPS
        CONTINUOUS => CONTINUOUS, -- Modo single-shot
        START_CONV => START_CONV,

        CONV_READY => CONV_READY,
        DATA_OUT => DATA_OUT,
        BUSY => BUSY,

        SDA => SDA, -- Conexión I2C
        SCL => SCL -- Conexión I2C
    );
    PROCESS (CLK, RESET)
    BEGIN
        IF RESET = '0' THEN
            STATE <= IDLE;
            CONFIG_EN <= '0';
            START_CONV <= '0';
            CONFIGURED <= '0';
            DATA_VALID <= '0';  -- Inicializar
        ELSIF RISING_EDGE(CLK) THEN
            DATA_VALID <= '0';  -- Por defecto en bajo
            
            CASE STATE IS
                WHEN IDLE =>
                    STATE <= SEND_COMMAND;

                WHEN SEND_COMMAND =>
                    IF CONFIGURED = '0' THEN
                        CONFIG_EN <= '1'; -- Cargar configuración
                        CONFIGURED <= '1';
                    ELSE
                        CONFIG_EN <= '0';
                    END IF;
                    START_CONV <= '1'; -- Iniciar conversión
                    STATE <= WAIT_PIN;

                WHEN WAIT_PIN =>
                    START_CONV <= '0';  -- Desactivar después de 1 ciclo
                    IF CONV_READY = '1' THEN
                        DATA_VALID <= '1';  -- Pulso de dato válido
                        STATE <= IDLE;
                    END IF;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE;