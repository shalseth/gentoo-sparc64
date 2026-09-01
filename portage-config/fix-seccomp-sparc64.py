#!/usr/bin/env python3
"""Teach vendored libseccomp-golang, and runc's seccomp code, about SPARC.

The C library has known SPARC since 2020 - /usr/include/seccomp.h defines
SCMP_ARCH_SPARC and SCMP_ARCH_SPARC64 - but the Go bindings never exposed
them, so ArchFromString("sparc64") returns ArchInvalid and every seccomp
profile carrying an architecture list fails to load. runc then refuses to
start the container rather than running it unconfined.

Four files, in two groups:

    vendor/github.com/seccomp/libseccomp-golang/
        seccomp.go            the public ScmpArch constants and their
                              string conversions
        seccomp_internal.go   the cgo bridge to SCMP_ARCH_*, plus archEnd,
                              which bounds every arch validity check

    libcontainer/seccomp/
        config.go             the SCMP_ARCH_* name the OCI profile uses
        patchbpf/enosys_linux.go
                              AUDIT_ARCH_* for the ENOSYS stub program

Written as a fixer rather than as whole-file replacements because runc,
containerd and docker each pin libseccomp-golang independently: one
version-pinned copy matches at most one of them, and the others would be
skipped with a warning and silently built without sparc64 seccomp. The
edits here are additive and anchored, so they apply to any version that
still has the SHEB and LOONGARCH64 entries they sit beside.

Idempotent. Usage: fix-seccomp-sparc64.py <WORKDIR>
"""
import os
import re
import sys


def _after(s, anchor, addition):
    """Insert addition immediately after anchor. Returns (text, changed)."""
    i = s.find(anchor)
    if i < 0:
        return s, False
    j = i + len(anchor)
    return s[:j] + addition + s[j:], True


def fix_seccomp_go(path):
    s = open(path).read()
    if "ArchSPARC64" in s:
        return False
    orig = s

    s, _ = _after(s, "\t// ArchSHEB represents Big-endian SuperH.\n\tArchSHEB\n",
                  "\t// ArchSPARC represents 32-bit SPARC.\n"
                  "\tArchSPARC\n"
                  "\t// ArchSPARC64 represents 64-bit SPARC.\n"
                  "\tArchSPARC64\n")
    s, _ = _after(s, '\tcase "sheb":\n\t\treturn ArchSHEB, nil\n',
                  '\tcase "sparc":\n\t\treturn ArchSPARC, nil\n'
                  '\tcase "sparc64":\n\t\treturn ArchSPARC64, nil\n')
    s, _ = _after(s, '\tcase ArchSHEB:\n\t\treturn "sheb"\n',
                  '\tcase ArchSPARC:\n\t\treturn "sparc"\n'
                  '\tcase ArchSPARC64:\n\t\treturn "sparc64"\n')

    if s == orig:
        return False
    open(path, "w").write(s)
    return True


def fix_seccomp_internal_go(path):
    s = open(path).read()
    if "C_ARCH_SPARC64" in s:
        return False
    orig = s

    s, _ = _after(s, "#define SCMP_ARCH_SHEB ARCH_BAD\n#endif\n",
                  "\n#ifndef SCMP_ARCH_SPARC\n"
                  "#define SCMP_ARCH_SPARC ARCH_BAD\n"
                  "#endif\n"
                  "\n#ifndef SCMP_ARCH_SPARC64\n"
                  "#define SCMP_ARCH_SPARC64 ARCH_BAD\n"
                  "#endif\n")

    # The C_ARCH_ block is column-aligned; match loosely, emit aligned.
    s = re.sub(r"^(const uint32_t C_ARCH_SHEB\s*= SCMP_ARCH_SHEB;)$",
               r"\1\n"
               "const uint32_t C_ARCH_SPARC        = SCMP_ARCH_SPARC;\n"
               "const uint32_t C_ARCH_SPARC64      = SCMP_ARCH_SPARC64;",
               s, count=1, flags=re.M)

    # archEnd bounds every arch validity check; leaving it at SHEB makes the
    # new constants parse and then fail validation.
    s = re.sub(r"^(\tarchEnd\s+ScmpArch = )ArchSHEB$", r"\1ArchSPARC64",
               s, count=1, flags=re.M)

    s, _ = _after(s, "\tcase C.C_ARCH_SHEB:\n\t\treturn ArchSHEB, nil\n",
                  "\tcase C.C_ARCH_SPARC:\n\t\treturn ArchSPARC, nil\n"
                  "\tcase C.C_ARCH_SPARC64:\n\t\treturn ArchSPARC64, nil\n")
    s, _ = _after(s, "\tcase ArchSHEB:\n\t\treturn C.C_ARCH_SHEB\n",
                  "\tcase ArchSPARC:\n\t\treturn C.C_ARCH_SPARC\n"
                  "\tcase ArchSPARC64:\n\t\treturn C.C_ARCH_SPARC64\n")

    if s == orig:
        return False
    open(path, "w").write(s)
    return True


def fix_config_go(path):
    s = open(path).read()
    if "SCMP_ARCH_SPARC64" in s:
        return False
    s, changed = _after(s, '\t"SCMP_ARCH_RISCV64":     "riscv64",\n',
                        '\t"SCMP_ARCH_SPARC":       "sparc",\n'
                        '\t"SCMP_ARCH_SPARC64":     "sparc64",\n')
    if not changed:
        return False
    open(path, "w").write(s)
    return True


def fix_enosys_go(path):
    s = open(path).read()
    if "C_AUDIT_ARCH_SPARC64" in s:
        return False
    orig = s

    # The nolint directive has to stay on the last line of the C block, or
    # the linter reads the added lines as an unterminated Go comment.
    s = re.sub(
        r"^const uint32_t C_AUDIT_ARCH_LOONGARCH64(\s*)= AUDIT_ARCH_LOONGARCH64;"
        r"(\s*//nolint:godot // C code, not Go comment\.)$",
        r"const uint32_t C_AUDIT_ARCH_LOONGARCH64\1= AUDIT_ARCH_LOONGARCH64;\n"
        r"const uint32_t C_AUDIT_ARCH_SPARC        = AUDIT_ARCH_SPARC;\n"
        r"const uint32_t C_AUDIT_ARCH_SPARC64      = AUDIT_ARCH_SPARC64;\2",
        s, count=1, flags=re.M)

    s, _ = _after(
        s,
        "\tcase libseccomp.ArchLOONGARCH64:\n"
        "\t\treturn linuxAuditArch(C.C_AUDIT_ARCH_LOONGARCH64), nil\n",
        "\tcase libseccomp.ArchSPARC:\n"
        "\t\treturn linuxAuditArch(C.C_AUDIT_ARCH_SPARC), nil\n"
        "\tcase libseccomp.ArchSPARC64:\n"
        "\t\treturn linuxAuditArch(C.C_AUDIT_ARCH_SPARC64), nil\n")

    if s == orig:
        return False
    open(path, "w").write(s)
    return True


TARGETS = [
    (os.path.join("seccomp", "libseccomp-golang"), "seccomp.go", fix_seccomp_go),
    (os.path.join("seccomp", "libseccomp-golang"), "seccomp_internal.go",
     fix_seccomp_internal_go),
    (os.path.join("libcontainer", "seccomp"), "config.go", fix_config_go),
    (os.path.join("libcontainer", "seccomp", "patchbpf"), "enosys_linux.go",
     fix_enosys_go),
]


def main(workdir):
    for root, _, _ in os.walk(workdir):
        for suffix, name, fixer in TARGETS:
            if not root.endswith(suffix):
                continue
            p = os.path.join(root, name)
            if not os.path.exists(p):
                continue
            try:
                if fixer(p):
                    print("sparc64 seccomp: patched %s"
                          % os.path.relpath(p, workdir))
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
