#!/usr/bin/env bash
# Install the sparc64 arch files that the bashrc hook injects into
# vendored Go dependencies.
#
# The files themselves are not kept here. They are generic to the
# architecture rather than to Gentoo - a Buildroot or Debian port would
# want exactly the same bytes - so they live in their own repo and this
# script mirrors them into /etc/portage/sparc64-arch/, where the hook
# looks for them. Keeping one copy means the two cannot drift.
#
#   ./sync-arch-files.sh          # clone or update, then install
#   DEST=/tmp/x ./sync-arch-files.sh   # somewhere else, to inspect first
set -euo pipefail

DEPS_REPO=${DEPS_REPO:-https://github.com/shalseth/go-sparc64-deps.git}
CACHE=${CACHE:-/var/cache/sparc64-go-deps}
DEST=${DEST:-/etc/portage/sparc64-arch}

if [ -d "$CACHE/.git" ]; then
	echo "==> updating $CACHE"
	git -C "$CACHE" pull --quiet --ff-only
else
	echo "==> cloning into $CACHE"
	git clone --quiet "$DEPS_REPO" "$CACHE"
fi

echo "==> installing into $DEST"
mkdir -p "$DEST"
cp -rf "$CACHE/patches/." "$DEST/"
cp -f "$CACHE/pristine-checksums.txt" "$DEST/"

echo "==> $(find "$DEST" -type f -not -name pristine-checksums.txt | wc -l) arch files, at $(git -C "$CACHE" rev-parse --short HEAD)"
