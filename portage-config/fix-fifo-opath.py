#!/usr/bin/env python3
"""Stop containerd/fifo hardcoding a non-sparc64 O_PATH.

handle_linux.go carries its own copy of the constant:

    const O_PATH = 0o10000000        // 0x200000

That is correct on x86, arm and mips, but SPARC numbers its open flags
differently: O_PATH is 0x1000000 there and 0x200000 is O_NOATIME. So
getHandle opens the FIFO for reading rather than as a path reference, and
blocks until a writer appears - which is why "docker run" hangs forever
with the container stuck in Created.

Use syscall.O_PATH, which is right on every Linux architecture. Idempotent.

Usage: fix-fifo-opath.py <WORKDIR>
"""
import os
import re
import sys

# both spellings occur: 0o10000000 upstream today, 010000000 in older
# vendored copies. Either way it is 0x200000, the non-SPARC value.
HARDCODED = re.compile(r"^const O_PATH = (?:0o?10000000|0x200000)\s*$", re.M)


def fix(path):
    s = open(path).read()
    if "const O_PATH = syscall.O_PATH" in s:
        return False
    if not HARDCODED.search(s):
        return False
    s = HARDCODED.sub("const O_PATH = syscall.O_PATH", s)
    if not re.search(r'^\t"syscall"$', s, re.M):
        s = re.sub(r"^import \(\n", 'import (\n\t"syscall"\n', s, count=1, flags=re.M)
    open(path, "w").write(s)
    return True


def main(workdir):
    n = 0
    for root, _, files in os.walk(workdir):
        if not root.endswith(os.path.join("containerd", "fifo")):
            continue
        p = os.path.join(root, "handle_linux.go")
        if os.path.exists(p) and fix(p):
            print("containerd/fifo O_PATH corrected in %s" % root)
            n += 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
