-------------------------------------------------------------------------------
--! @file lcd_hd44780.vhd
--! @brief HD44780 LCD decoder peripheral for RISC-V MAX10 softcore
--! @author Rodrigo da Costa
--! @date 21/08/2021
-------------------------------------------------------------------------------

--! Use standard library
library ieee;
--! Use standard logic elements 
use ieee.std_logic_1164.all;
--! Use conversion functions
use ieee.numeric_std.all;

entity lcd_hd44780 is
	generic(
		display_width   : integer := 16;
		display_heigth  : integer := 2;
		-- Countings
		t0_startup_time : integer := 10; --! 40ms in datasheet but using 100ms   -- test in 10us
		t1_short_wait   : integer := 10; --! 100us but using 200us            -- test in 10us
		t2_long_wait    : integer := 10; --! 4.1ms but using 5ms            -- test in 10 us
		t3_enable_pulse : integer := 2  --! 0,450us but using 10us           -- test in 1us
	);
	port(
		--! Internal signals (RISC-V Datapath)
		clk            : in  std_logic;
		rst            : in  std_logic;
		-- TODO: 16x2 8-bit RAM peripheral memory shared with RISC-V

		--! LCD peripheral 32-bit register ("LCDREG0")
		lcd_character  : in  std_logic_vector(7 downto 0); --! Bits 0 to 7 = CHARX
		lcd_init       : in  std_logic; --! Bit 8 - Rising edge will start display initialization FSM
		lcd_write_char : in  std_logic; --! Bit 9 - '1' will write char in bits 0-7
		lcd_clear      : in  std_logic; --! Bit 10 - '1' will return cursor to home (Line1-0) and clear display
		lcd_goto_l1    : in  std_logic; --! Bit 11 - '1' will put cursor in first position of line 1
		lcd_goto_l2    : in  std_logic; --! Bit 12 - '1' will put cursor in first position of line 2

		lcd_is_busy    : out std_logic; --! Bit 13 - Status flag, during command send will be 1, else 0

		--! External signals (IOs to interface with LCD)
		-- IO
		lcd_data       : out std_logic_vector(7 downto 0);
		lcd_rs         : out std_logic; --! Controls if command or char data
		lcd_e          : out std_logic  --! Pulse in every command/data
	);
end lcd_hd44780;

architecture controller of lcd_hd44780 is
	type fsm_state is (
		LCD_OFF, LCD_STARTUP, LCD_ON
	);
	type lcd_commands is (
		LCD_CMD_IDLE, LCD_CMD_INITIALIZE, LCD_CMD_WRITE_CHAR, LCD_CMD_CLEAR_RETURN_HOME, LCD_CMD_GOTO_LINE_1, LCD_CMD_GOTO_LINE_2
	);
	type lcd_initialize is (
		LCD_INIT_0, LCD_INIT_1, LCD_INIT_2, LCD_INIT_3, LCD_INIT_4, LCD_INIT_5, LCD_INIT_6
	);

	signal state                 : fsm_state      := LCD_STARTUP;
	signal command               : lcd_commands   := LCD_CMD_IDLE;
	signal lcd_initialize_states : lcd_initialize := LCD_INIT_0;

begin
	lcd_control : process(clk, rst)
		variable startup_counter : integer range 0 to 1000000; --! 0 microseconds to 1s
		variable time_counter    : integer range 0 to 1000000; --! 0 microseconds to 1s
	begin
		if (rst = '1') then
			state           <= LCD_OFF;
			startup_counter := 0;

		elsif rising_edge(clk) then
			startup_counter := startup_counter + 1;
			time_counter    := time_counter + 1;

			case state is
				when LCD_OFF =>
					lcd_is_busy <= '0';
					if (lcd_init = '1') then
						state <= LCD_STARTUP;
					end if;
				when LCD_STARTUP =>
					lcd_is_busy <= '1';
					if (startup_counter >= t0_startup_time) then
						startup_counter := 0;
						state           <= LCD_ON;
					end if;

				when LCD_ON =>
					--! Busy flag control
					if (command = LCD_CMD_IDLE) then
						lcd_is_busy <= '0';
					else
						lcd_is_busy <= '1';
					end if;

					--! Fetch bit instructions to internal "command" signal
					if (lcd_init = '1') then
						command <= LCD_CMD_INITIALIZE;
					--lcd_init <= '0'; --! Bit cleared by hardware
					elsif (lcd_write_char = '1') then
						command <= LCD_CMD_WRITE_CHAR;
					--lcd_write_char <= '0'; --! Bit cleared by hardware
					elsif (lcd_clear = '1') then
						command <= LCD_CMD_CLEAR_RETURN_HOME;
					--lcd_clear <= '0'; --! Bit cleared by hardware
					elsif (lcd_goto_l1 = '1') then
						command <= LCD_CMD_GOTO_LINE_1;
					--lcd_goto_l1 <= '0'; --! Bit cleared by hardware
					elsif (lcd_goto_l2 = '1') then
						command <= LCD_CMD_GOTO_LINE_2;
					--lcd_goto_l2 <= '0'; --! Bit cleared by hardware
					else
						command <= LCD_CMD_IDLE;
					end if;

					case command is
						when LCD_CMD_IDLE =>
						when LCD_CMD_INITIALIZE =>
							lcd_rs <= '0';
							case lcd_initialize_states is
								when LCD_INIT_0 =>
									lcd_data <= "00110000";
									lcd_e    <= '0';
									if (time_counter >= t2_long_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_1;
										time_counter          := 0;
									end if;
								when LCD_INIT_1 =>
									lcd_data <= "00110000";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_2;
										time_counter          := 0;
									end if;
								when LCD_INIT_2 =>
									lcd_data <= "00110000";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_3;
										time_counter          := 0;
									end if;
								when LCD_INIT_3 =>
									lcd_data <= "00001000";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_4;
										time_counter          := 0;
									end if;
								when LCD_INIT_4 =>
									lcd_data <= "00000001";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_5;
										time_counter          := 0;
									end if;
								when LCD_INIT_5 =>
									lcd_data <= "00000101";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_6;
										time_counter          := 0;
									end if;
								when LCD_INIT_6 =>
									lcd_data <= "00001101";
									lcd_e    <= '0';
									if (time_counter >= t1_short_wait) then
										lcd_e                 <= '1';
										lcd_initialize_states <= LCD_INIT_0;
										time_counter          := 0;
										command               <= LCD_CMD_IDLE;
									end if;
							end case;
						when LCD_CMD_WRITE_CHAR =>
							lcd_rs   <= '1';
							lcd_data <= "01000001";
							lcd_e    <= '1';
							if (time_counter >= t3_enable_pulse) then
								lcd_e        <= '0';
								time_counter := 0;
							end if;

						when LCD_CMD_CLEAR_RETURN_HOME =>
							lcd_rs   <= '1';
							lcd_data <= "00000001";
							lcd_e    <= '1';
							if (time_counter >= t3_enable_pulse) then
								lcd_e        <= '0';
								time_counter := 0;
							end if;

						when LCD_CMD_GOTO_LINE_1 =>

						when LCD_CMD_GOTO_LINE_2 =>
					end case;
			end case;
		end if;
	end process;

end controller;
