#!/bin/bash
# The cards of Ф3 in the model (sim/tests/f3_test.asm in the Classic ROM window, ~50 s):
# expect on SIO A "T5AA40JEEEEFDK1CF01C55I0FB" (VRAM, YM2149, joysticks, 8242 with the key a
# typed before the self test, 15 VDP interrupts) and "[B HELLO]" (SIO B echo of the USB serial port);
# the TMS picture "HELLO RC2014" in sim/build/tests/f3.ppm.
set -e
cd "$(dirname "$0")/.."
sim/tests/build.sh
sim/run_machine.sh --profile 1 --rom 0x104000:sim/build/tests/f3_test.bin --kbd 5:a --usb 330:hello \
	--joy1 17 --joy2 2 --ms 360 --ppm sim/build/tests/f3.ppm
