#!/usr/bin/env python3
"""Correct the linux/sparc64 stat ABI in a vendored golang.org/x/sys/unix.

Upstream declares Stat_t with a layout the kernel never writes, and points
Stat/Lstat/Fstat at the legacy newstat calls, which fill a different struct
again. Reading Ino, Nlink or Size therefore returns garbage - which is why
runc rejects /proc with "incorrect procfs root inode number".

This is deliberately a targeted edit rather than a whole-file replacement,
because vendored copies span many x/sys versions and a version-pinned file
silently fails to apply to all the others. Idempotent: safe to run repeatedly.

Usage: fix-xsys-stat.py <path to vendor/golang.org/x/sys/unix>
"""
import re
import sys

STAT_T = """type Stat_t struct {
\tDev     uint64
\tIno     uint64
\tNlink   uint64
\tMode    uint32
\tUid     uint32
\tGid     uint32
\t_       int32
\tRdev    uint64
\tSize    int64
\tBlksize int64
\tBlocks  int64
\tAtim    Timespec
\tMtim    Timespec
\tCtim    Timespec
\t_       [3]int64
}"""

FLOCK_T = """type Flock_t struct {
\tType   int16
\tWhence int16
\t_      [4]byte
\tStart  int64
\tLen    int64
\tPid    int32
\t_      [4]byte
}"""

# the legacy newstat calls fill a 104-byte struct stat; the 64 family fills
# the 144-byte struct stat64 that Stat_t now describes
SYSCALL_SWAPS = [
    ("SYS_FSTAT,", "SYS_FSTAT64,"),
    ("SYS_LSTAT,", "SYS_LSTAT64,"),
    ("SYS_STAT,", "SYS_STAT64,"),
]


def replace_struct(src, name, replacement):
    pat = re.compile(r"^type %s struct \{.*?^\}" % re.escape(name), re.M | re.S)
    if replacement in src:
        return src, False
    new, n = pat.subn(lambda _: replacement, src, count=1)
    return new, n > 0


def main(d):
    changed = []

    p = "%s/ztypes_linux_sparc64.go" % d
    try:
        s = open(p).read()
    except FileNotFoundError:
        print("no ztypes_linux_sparc64.go in %s; nothing to do" % d)
        return 0
    orig = s
    for name, repl in (("Stat_t", STAT_T), ("Flock_t", FLOCK_T)):
        s, did = replace_struct(s, name, repl)
        if did:
            changed.append(name)
    if s != orig:
        open(p, "w").write(s)

    p = "%s/zsyscall_linux_sparc64.go" % d
    try:
        s = open(p).read()
        orig = s
        for old, new in SYSCALL_SWAPS:
            if old in s:
                s = s.replace(old, new)
                changed.append(old.rstrip(",") + "->" + new.rstrip(","))
        if s != orig:
            open(p, "w").write(s)
    except FileNotFoundError:
        pass

    # keep the //sys directives consistent, so a regeneration reproduces this
    p = "%s/syscall_linux_sparc64.go" % d
    try:
        s = open(p).read()
        orig = s
        for fn, num in (("Fstat", "SYS_FSTAT64"), ("Lstat", "SYS_LSTAT64"),
                        ("Stat", "SYS_STAT64")):
            pat = re.compile(r"^(//sys\t%s\((?:[^)]*)\) \(err error\))$" % fn, re.M)
            s = pat.sub(lambda m: m.group(1) + " = " + num, s)
        if s != orig:
            open(p, "w").write(s)
            changed.append("//sys directives")
    except FileNotFoundError:
        pass

    if changed:
        print("sparc64 stat ABI corrected in %s: %s" % (d, ", ".join(changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
