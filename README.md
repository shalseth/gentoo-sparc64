# Gentoo overlay for linux/sparc64

Provides `dev-lang/go` built from the out-of-tree Go port at
[shalseth/go, branch `sparc64`](https://github.com/shalseth/go/tree/sparc64),
so that Gentoo packages which need a Go toolchain can be built on SPARC.

The Go tree in `::gentoo` has no sparc keyword, so nothing here conflicts
with it; the version in this overlay is higher, and Portage picks it
automatically.

## Requirements

SPARC T3 or later, or Fujitsu SPARC64 X or later. VIS3 is the port's
baseline - the compiler emits its register-file moves for every
conversion between integer and floating-point values - so earlier
machines fault with SIGILL during runtime startup.

A `sparc` profile with a 64-bit userland, such as
`default/linux/sparc/23.0/64ul`. Gentoo's `go-env.eclass` already maps
`sparc64-unknown-linux-gnu` to `GOARCH=sparc64`, so consumers need no
special configuration.

## Adding the overlay

With `app-eselect/eselect-repository`:

```sh
eselect repository add sparc64 git https://github.com/shalseth/gentoo-sparc64.git
emaint sync -r sparc64
```

Or by hand, as `/etc/portage/repos.conf/sparc64.conf`:

```ini
[sparc64]
location = /var/db/repos/sparc64
sync-type = git
sync-uri = https://github.com/shalseth/gentoo-sparc64.git
auto-sync = yes
priority = 100
```

## Installing Go

The ebuild is keyworded `~sparc`, so accept it first:

```sh
echo 'dev-lang/go::sparc64 ~sparc' >> /etc/portage/package.accept_keywords/sparc64-go
emerge -av dev-lang/go
go version
```

Two ebuilds are available:

* `dev-lang/go-1.28.0_pre20260820` unpacks a prebuilt toolchain from a
  release of the port's repository. Nothing needs to be compiled, which
  also solves the bootstrap problem: Go is written in Go, so building it
  requires a Go.
* `dev-lang/go-9999` builds from the `sparc64` branch with `git-r3`,
  using an already-installed toolchain to bootstrap. Useful after
  pushing changes to the port.

## Building Go packages

Anything that does not need cgo should build. Most Go packages in
`::gentoo` are keyworded `~amd64`/`~arm64` only, so each needs its own
entry - an overlay cannot override another repository's keywords:

```sh
echo 'app-benchmarks/hey **' >> /etc/portage/package.accept_keywords/sparc64-go
emerge -av app-benchmarks/hey
```

## Limitations

These come from the port, not from the packaging:

* No cgo and no external linking. The toolchain defaults to
  `CGO_ENABLED=0`; packages that force cgo, such as
  `app-containers/runc`, cannot be built.
* `-buildmode` is limited to `exe`, and the race detector is
  unavailable.
* No sparc64 disassembler, so `go tool objdump` and pprof's
  annotated-assembly view do not work. Collecting and reading profiles
  is unaffected. GNU `objdump` reads the binaries perfectly well.

`README.sparc64.md` in the port's repository documents the port itself,
including what the toolchain uses the T4's on-core crypto instructions
for and where the hand-written assembly lives.

## Updating the binary ebuild

On a machine with the port checked out and built:

```sh
cd /path/to/go
git log --oneline -1                      # the commit the tarball will report
(cd src && GOROOT_BOOTSTRAP=... ./make.bash)
cd .. && tar -c --exclude=go/.git --exclude=testdata \
	--exclude=go/pkg/bootstrap --exclude=go/pkg/obj go |
	xz -T0 -6 > go-<PV>-linux-sparc64.tar.xz
```

That command is deterministic: the same tree produces the same bytes.
Attach the tarball to a release of the port's repository, bump `PV` and
`MY_TAG` in the ebuild, then regenerate the digests with `ebuild
dev-lang/go/go-<PV>.ebuild manifest`. Note that `ebuild --force
manifest` deletes the local distfile in order to re-fetch it, which
fails if the release is not published yet.
