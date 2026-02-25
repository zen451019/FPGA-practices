# Clock constraint for 50 MHz oscillator on PIN 26
create_clock -name CLK -period 20.000 [get_ports {CLK}]

# Input/output delays (relaxed for simple design)
set_input_delay -clock CLK 0 [get_ports {RESET}]
set_output_delay -clock CLK 0 [get_ports {TX}]
