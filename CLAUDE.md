# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

An RC2014 (modular Z80 computer) core for the Karabas Go, Mini and Mini G boards (Xilinx Spartan-6 XC6SLX25, ISE 14.7, XST). Our own top on the RC2014 bus: T80, ROM / RAM banks in the board SRAM (Pageable ROM, 64K, 512K ROM + 512K RAM), ACIA / SIO/2, CF on an SD image (`hdf_ata.v` of modules), DS1302, CTC, TMS9918A (`vdp18` of core-msx), YM2149 (`jt49`), a built-in VT100 terminal (core-vt100). Docs, in Russian: `docs/PLAN.md` (decisions, blocks, phases). Follow the phases; record a changed decision in PLAN.md.

User decisions (2026-11-18): Z80 only (Z180 / eZ80 later); OSD profiles RomWBW 512K / Classic (SCM + BASIC) / Mini (BASIC 32K); default console = the built-in VT100 terminal on HDMI; ROMs built into the `.kg`; core id `rc2014`, public repo.

Reference emulator: Alan Cox EmulatorKit `rc2014` (etchedpixels/emulatorkit). Port map: from the RomWBW sources, never from memory.

## Rules of the core

The rules of the other karabas-go cores apply: standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, Mini / Mini G drive T3 (`FLASH_CS_N`) = 0, OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, FL slots 0..7 only, Verilog-2001 for XST (`sv2v` for SV), VHDL-93 for XST, imported code marked `karabas:`, builds through `src/Makefile`.

- Licences: our files GPL-3; the VT100 terminal (pdp2011) is non-commercial only (allowed by the user); keep every header as it is.
- **Ask the user before every check on the board** (and the HDMI capture). Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.
- Heavy builds: Mini G only while working on one feature, all boards for a release; map with cost table 2 first.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
