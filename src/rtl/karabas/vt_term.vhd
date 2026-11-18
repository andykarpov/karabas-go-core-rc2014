-- vt_term.vhd: the pdp2011 vt10x terminal with std_logic ports only (Verilog tops cannot
-- drive its integer ports): VT100, 115200 bps, no RTS / CTS, underline blinking cursor,
-- no auto screen off.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity vt_term is
	port(
		cpuclk : in std_logic;     -- the PDP-11 of the terminal, about 10 MHz
		clk50mhz : in std_logic;   -- the video timing
		reset : in std_logic;
		rx : in std_logic;
		tx : out std_logic;
		ps2k_c : in std_logic;
		ps2k_d : in std_logic;
		vga_hsync : out std_logic;
		vga_vsync : out std_logic;
		vga_fb : out std_logic;
		vga_ht : out std_logic;
		vga_blank : out std_logic;
		vtbell : out std_logic
	);
end vt_term;

architecture rtl of vt_term is
	component vt10x is
		port(
			vga_hsync : out std_logic;
			vga_vsync : out std_logic;
			vga_fb : out std_logic;
			vga_ht : out std_logic;
			vgaclk : out std_logic;
			vga_blank : out std_logic;
			tx : out std_logic;
			rx : in std_logic;
			rts : out std_logic;
			cts : in std_logic := '0';
			bps : in integer range 1200 to 230400 := 9600;
			force7bit : in integer range 0 to 1 := 0;
			rtscts : in integer range 0 to 1 := 0;
			ps2k_c : in std_logic;
			ps2k_d : in std_logic;
			ifetch : out std_logic;
			iwait : out std_logic;
			teste : in std_logic := '0';
			testf : in std_logic := '0';
			vtbell : out std_logic;
			vga_bl : out std_logic_vector(9 downto 0);
			vttype : in integer range 100 to 105 := 100;
			vga_cursor_block : in std_logic := '1';
			vga_cursor_blink : in std_logic := '0';
			have_act_seconds : in integer range 0 to 7200 := 900;
			have_act : in integer range 1 to 2 := 2;
			cpuclk : in std_logic;
			clk50mhz : in std_logic;
			reset : in std_logic
		);
	end component;
begin
	vt0: vt10x port map(
		vga_hsync => vga_hsync, vga_vsync => vga_vsync, vga_fb => vga_fb, vga_ht => vga_ht,
		vgaclk => open, vga_blank => vga_blank,
		tx => tx, rx => rx, rts => open, cts => '0', bps => 115200, force7bit => 0, rtscts => 0,
		ps2k_c => ps2k_c, ps2k_d => ps2k_d, ifetch => open, iwait => open, teste => '0', testf => '0',
		vtbell => vtbell, vga_bl => open, vttype => 100, vga_cursor_block => '0', vga_cursor_blink => '1',
		have_act_seconds => 0, have_act => 2,
		cpuclk => cpuclk, clk50mhz => clk50mhz, reset => reset
	);
end rtl;
