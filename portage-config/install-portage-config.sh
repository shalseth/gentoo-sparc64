#!/usr/bin/env bash
# Install this directory's Portage configuration onto the system.
#
# sync-arch-files.sh mirrors the architecture files from go-sparc64-deps.
# Everything else the hook needs lives here in the overlay and used to be
# copied by hand, which is how a runc patch ended up on one machine and in
# no repository at all.
#
#   ./install-portage-config.sh                  # install
#   DESTDIR=/tmp/x ./install-portage-config.sh   # somewhere else, to inspect
#
# Additive, like sync-arch-files.sh: /etc/portage/patches also holds patches
# that have nothing to do with sparc64, so nothing here deletes.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DESTDIR=${DESTDIR:-}

install -Dm0644 "$HERE/bashrc" "$DESTDIR/etc/portage/bashrc"
echo "==> bashrc"

# The fixers go where the hook looks for them, which is the directory
# sync-arch-files.sh populates from the other repo. The two sets coexist
# because both scripts copy rather than mirror; keep it that way.
n=0
for f in "$HERE"/fix-*.py; do
	[ -e "$f" ] || continue
	install -Dm0755 "$f" "$DESTDIR/etc/portage/sparc64-arch/$(basename "$f")"
	n=$((n + 1))
done
echo "==> $n fixers -> /etc/portage/sparc64-arch/"

if [ -d "$HERE/patches" ]; then
	mkdir -p "$DESTDIR/etc/portage/patches"
	cp -rf "$HERE/patches/." "$DESTDIR/etc/portage/patches/"
	echo "==> $(find "$HERE/patches" -type f | wc -l) user patches -> /etc/portage/patches/"
fi

echo
echo "Architecture files are a separate repo; run ./sync-arch-files.sh for those."
