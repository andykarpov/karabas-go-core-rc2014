#!/usr/bin/env python3
"""VHDL ports are case-insensitive, Verilog (verilator) ones are not: the upstream Verilog connects
the VHDL entities with any case (.reset_n to RESET_n, .dout to DOUT). For the simulation only:
lower-case the ports of the given modules in the ghdl netlist, and the port names of their
instances in copies of the Verilog files. XST binds them as they are.
  fixcase.py <ghdl netlist> <out dir> <verilog files...>
"""
import os
import re
import sys

net, out, vfiles = sys.argv[1], sys.argv[2], sys.argv[3:]
src = open(net).read()
# ghdl writes VHDL names that are Verilog keywords as escaped identifiers (\reg ), also glued
# into other names (u0_\reg ): make them plain
src = re.sub(r'\\(\w+) ', r'\1_esc', src)

KW = {'reg', 'wire', 'do', 'input', 'output', 'inout', 'integer', 'time', 'event', 'begin', 'end',
      'module', 'assign', 'always', 'initial', 'case', 'if', 'else', 'for', 'while', 'repeat', 'function', 'task'}


def low(n):
    n = n.lower()
    return n + '_' if n in KW else n


ports = {}
parts = re.split(r'(?=^module )', src, flags=re.M)
fixed = []
for p in parts:
    m = re.match(r'module (\w+)\s*\((.*?)\);', p, re.S)
    if m:
        names = re.findall(r'(?:input|output|inout)\s+(?:\[[^\]]*\]\s*)?(\w+)', m.group(2))
        ports[m.group(1)] = set(names)
        for n in names:
            if n != low(n):
                p = re.sub(r'\b%s\b' % re.escape(n), low(n), p)
    fixed.append(p)
netlist = ''.join(fixed)

PAR = r'#\s*\((?:[^()]|\([^()]*\))*\)'
inst_re = re.compile(r'^(\s*)(\w+)\s+(?:' + PAR + r'\s*)?\w+\s*\(([^;]*?)\);', re.M | re.S)
def fix_instances(s):
    return inst_re.sub(lower_ports, s)


def lower_ports(m):
    if m.group(2) not in ports:
        return m.group(0)
    # the generics are fixed in the ghdl netlist: drop the parameter list
    t = re.sub(PAR, '', m.group(0), count=1)
    return re.sub(r'\.(\w+)\s*\(', lambda k: '.' + low(k.group(1)) + '(', t)


# the instances inside the netlist too (T80pa -> t80: .do)
open(os.path.join(out, os.path.basename(net)), 'w').write(fix_instances(netlist))

for f in vfiles:
    s = open(f).read()
    s = fix_instances(s)
    open(os.path.join(out, os.path.basename(f)), 'w').write(s)
