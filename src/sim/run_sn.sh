#!/bin/bash
# The SN76489 module in the model (sim/tests/sn_test.asm in the Classic ROM window, ~5 s):
# expect "sn changes L" and "R" in the thousands (a tone left, noise right).
set -e
cd "$(dirname "$0")/.."
sim/tests/build.sh
sim/run_machine.sh --profile 1 --rom 0x104000:sim/build/tests/sn_test.bin --ms 20
