# RC2014 core for Karabas Go / Mini / Mini G

An [RC2014](https://rc2014.co.uk/) modular Z80 computer for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25): the Z80 with the usual RC2014 cards and a built-in VT100 terminal on HDMI. Runs RomWBW (CP/M 2.2, CP/M 3, ZSDOS, BASIC, Forth, games), Fuzix, SCM and NASCOM BASIC.

Status: built for Karabas Go, Mini and Mini G (`src/rc2014.kg`, one file for all three); checked on Mini G, Go and Mini have not run on a board yet. The plan and the history are in `docs/PLAN.md` (Russian), a Russian README is `README.ru.md`.

## The machine

| Card | Ports |
|---|---|
| Z80 at 7.3728 MHz (OSD *CPU*: 14.7456 MHz) | |
| 512K ROM + 512K RAM (RomWBW), Pageable ROM + 64K RAM (Classic), 8K ROM + 32K RAM (Mini) | 78-7C / 38 |
| SIO/2 (or ACIA, OSD *Serial*) | 80-83 |
| Compact Flash (8-bit IDE): an image on the SD card or the CF card of the board | 10-17 |
| DS1302 real time clock (the clock of the board) | C0 |
| TMS9918A video (16K VRAM) | 98-99 |
| YM2149 sound (Ed Brindley module, 1.79 MHz) | D8 / D0 |
| SN76489 sound module (two chips: left, right; 3.58 MHz) | FF / FB |
| 8242 PS/2 keyboard controller (the keyboard of the TMS console) | 60 / 64 |
| Joystick module (two USB / Sega pads) | 01 / 02 |
| Front panel switches | 00 |

The ROMs are inside `rc2014.kg`: RomWBW 3.6 (our build `RCZ80_kg`: RCZ80_std with the TMS9918, keyboard, YM2149 and SN76489 drivers), the RC2014 factory ROMs with SCM (Classic) and BASIC (Mini).

## Using the core

- **Profile** (OSD): *RomWBW 512K*, *Classic* (SCM, BASIC, CP/M from CF), *Mini* (BASIC 32K on the ACIA). A change resets the machine.
- **Console** (OSD, Menu+C): *Terminal* = the built-in VT100 on the serial line (SIO/2 A or ACIA), the USB keyboard goes to the terminal; *TMS9918* = the picture of the TMS9918 and the keyboard on the 8242: RomWBW then starts its console there (the front panel reads SW_CRT). *Colour* sets the colour of the terminal: amber, green or white.
- **Second serial port**: SIO/2 channel B is the second USB serial port of the board ("Karabas core serial", `/dev/serial/by-id/usb-Karabas_Go_*-if02` on Linux; firmware with two CDC ports). In RomWBW it is SIO1: `I 1` at the boot loader moves the console there, `XM` transfers files.
- **CF card** (Menu+F1): a disk image (`.img`, `.hdf`) in `/rc2014` on the SD card, for example the RomWBW `hd1k` images (`hd1k_prefix.dat` + slices). *CF source* = *Card* uses the CF card in the slot of the board instead (be careful: the core writes to it like the machine does).
- **Fuzix**: unpack `src/roms/fuzix/rc2014_fuzix.img.xz` (a 40 MB CF image, Fuzix 0.5 built by `src/tools/rc2014_fuzix.sh`) into `/rc2014`, choose it as *CF card*, type `2` at the RomWBW boot loader, then `hda1` at `bootdev:` and log in as `root`. Its timer is the TMS9918 frame interrupt. With *Console* = *TMS9918* Fuzix runs on the TMS screen with the keyboard (tty1-4), with *Terminal* on the terminal (tty1); tty2 / tty6 is the second USB serial port. Leave it with `shutdown` (or answer the questions of `fsck` at the next boot).
- **Time**: the DS1302 reads and sets the clock of the board (RomWBW `RTC`, `TIME` in ZSDOS).
- **Reset**: Menu+F12.

## Building

ISE 14.7: `cd src; make minig` (or `go`, `mini`). The RomWBW ROM: `src/tools/rc2014_romwbw.sh <work dir>` (needs gcc, srecord, libncurses-dev), then rebuild the `.kg` (`python3 make_core.py core.json rc2014.kg`). Simulation of the machine: `src/sim/run_machine.sh` (Verilator + GHDL), the cards of the TMS / YM2149 / 8242: `src/sim/run_f3.sh`.

## Licence

The files written for this core are GPL-3.0 (see [LICENSE](LICENSE)). Imported files keep the licence in their headers:

- T80 (Daniel Wallner, MiSTer fixes): BSD-style;
- vdp18 (Arnim Läuger): GPL-2.0;
- JT49, JT89 (Jose Tejada): GPL-3.0;
- the VT100 terminal pdp2011 / vt10x (Sytse van Slooten), in the version of [tsybulin/karabas-go-core-pdp2026](https://github.com/tsybulin/karabas-go-core-pdp2026): **non-commercial use only**;
- afifo (Dan Gisselquist): GPL-3.0;
- RomWBW (Wayne Warthen and contributors): AGPL-3.0, a separate program in the `.kg`;
- Fuzix (Alan Cox and contributors): GPL-2.0, the disk image in `src/roms/fuzix` (sources: the commits in `rc2014_fuzix.txt`);
- SCM (Steve Cousins), NASCOM BASIC (Microsoft, Grant Searle): as distributed by RC2014.

RC2014 is a trademark of Spencer Owen. This project is not affiliated with RC2014.
