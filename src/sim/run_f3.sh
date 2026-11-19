#!/bin/bash
# The cards of Ф3 in the model (sim/tests/f3_test.asm in the Classic ROM window, ~50 s):
# expect on SIO A "T5AA40JEEEEFDK551CF01CI0FB" (VRAM, YM2149, joysticks, 8242 self test, then the key a
# (make, break), 15 VDP interrupts) and "[B HELLO]" (SIO B echo of the USB serial port);
# the TMS picture "HELLO RC2014" in sim/build/tests/f3.ppm.
set -e
cd "$(dirname "$0")/.."
sim/tests/build.sh
sim/run_machine.sh --profile 1 --rom 0x104000:sim/build/tests/f3_test.bin --kbd 60:a --usb 330:hello \
	--joy1 17 --joy2 2 --ms 360 --ppm sim/build/tests/f3.ppm
