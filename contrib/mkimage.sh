#!/usr/bin/env bash
# Build a minimal native linux/sparc64 container image from a running Gentoo
# system: bash, the core utilities, and nothing else.
#
#   ./mkimage.sh                 # build and import as sparc64/gentoo-base:1
#   IMAGE=me/gentoo-sparc64:bash ./mkimage.sh
#
# Deliberately not a Dockerfile: `docker build` defaults to BuildKit, which
# wants to pull moby/buildkit, and no sparc64 image of it exists. `docker
# import` of a tarball needs no builder at all.
set -euo pipefail

IMAGE=${IMAGE:-sparc64/gentoo-base:1}
R=${R:-/tmp/gentoo-base}

# Bash provides echo/pwd/true/false as builtins, so `command -v` finds those
# rather than the files. Take everything from disk by path instead.
BINS="bash ls cat echo pwd mkdir rmdir rm cp mv ln chmod chown uname id env
      sleep true false printf sync head tail wc sort uniq cut tr grep sed find
      stat du df readlink dirname basename mktemp touch date hostname xargs
      tee which seq realpath"

rm -rf "$R"
mkdir -p "$R"/usr/{bin,lib,lib64} "$R"/etc "$R"/{dev,proc,sys,tmp,root} "$R"/var/tmp

for b in $BINS; do
	for d in /usr/bin /bin /usr/sbin /sbin; do
		if [ -f "$d/$b" ]; then
			cp -Ln "$d/$b" "$R/usr/bin/" 2>/dev/null || true
			break
		fi
	done
done
ln -sf bash "$R/usr/bin/sh"

# the library closure of whatever landed above, plus the ELF interpreter
for f in "$R"/usr/bin/*; do
	[ -f "$f" ] || continue
	ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u | while read -r lib; do
	[ -f "$lib" ] && cp -Ln "$lib" "$R/usr/lib64/" 2>/dev/null || true
done
cp -Ln /lib64/ld-linux.so.2 "$R/usr/lib64/ld-linux.so.2" 2>/dev/null || true

# This is a merged-usr system and the interpreter is referenced as
# /lib64/ld-linux.so.2, so without these symlinks nothing starts at all.
ln -sf usr/bin "$R/bin"
ln -sf usr/bin "$R/sbin"
ln -sf usr/lib "$R/lib"
ln -sf usr/lib64 "$R/lib64"
ln -sf bin "$R/usr/sbin"

cat > "$R/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/:/sbin/nologin
EOF
cat > "$R/etc/group" <<'EOF'
root:x:0:
nogroup:x:65534:
EOF
cat > "$R/etc/nsswitch.conf" <<'EOF'
passwd: files
group: files
hosts: files dns
EOF
cat > "$R/etc/os-release" <<'EOF'
NAME="Gentoo Linux"
ID=gentoo
PRETTY_NAME="Gentoo Linux (sparc64, minimal container base)"
EOF
echo 'PS1="[\u@\h \W]\$ "' > "$R/etc/bash_bashrc"

tar -C "$R" -cf - . | docker import \
	-c 'CMD ["/bin/bash"]' \
	-c 'ENV PATH=/usr/bin:/bin' \
	- "$IMAGE"

echo
echo "built $IMAGE"
docker image inspect "$IMAGE" --format '  platform: {{.Os}}/{{.Architecture}}'
echo "  binaries: $(ls "$R"/usr/bin | wc -l)  libs: $(ls "$R"/usr/lib64 | wc -l)"
