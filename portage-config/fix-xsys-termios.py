#!/usr/bin/env python3
"""Correct the sparc64 termios control-character indices in vendored x/sys.

zerrors_linux_sparc64.go carries the generic Linux values for VMIN, VEOL and
VEOL2. SPARC numbers them differently, because its NCCS is small enough that
the canonical and non-canonical slots overlap:

    VMIN  = 4   (shares the slot with VEOF)   x/sys said 6
    VEOL  = 5   (shares the slot with VTIME)  x/sys said 11
    VEOL2 = 6                                 x/sys said 16

VMIN is the damaging one. moby/term and containerd/console put a terminal in
raw mode with `termios.Cc[unix.VMIN] = 1`, so with the wrong index the real
VMIN keeps its default of 4 and every read on the terminal blocks until four
bytes arrive. Interactive `docker run -it` then delivers stdin in 4-byte
groups: type four characters before anything appears.

Idempotent. Usage: fix-xsys-termios.py <WORKDIR>
"""
import os
import re
import sys

WANT = {"VMIN": "0x4", "VEOL": "0x5", "VEOL2": "0x6"}


def fix(path):
    s = open(path).read()
    orig = s
    for name, val in WANT.items():
        s = re.sub(r"^(\t%s\s+)= 0x[0-9a-fA-F]+$" % name,
                   lambda m: m.group(1) + "= " + val, s, flags=re.M)
    if s == orig:
        return False
    open(path, "w").write(s)
    return True


def main(workdir):
    n = 0
    for root, _, files in os.walk(workdir):
        if not root.endswith(os.path.join("golang.org", "x", "sys", "unix")):
            continue
        p = os.path.join(root, "zerrors_linux_sparc64.go")
        if os.path.exists(p) and fix(p):
            print("sparc64 termios VMIN/VEOL/VEOL2 corrected in %s" % root)
            n += 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
