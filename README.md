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

* `dev-lang/go-1.28.0_pre20260823` unpacks a prebuilt toolchain from a
  release of the port's repository. Nothing needs to be compiled, which
  also solves the bootstrap problem: Go is written in Go, so building it
  requires a Go.
* `dev-lang/go-9999` builds from the `sparc64` branch with `git-r3`,
  using an already-installed toolchain to bootstrap. Useful after
  pushing changes to the port.

## Building Go packages

cgo and external linking both work, so packages that need them - `runc`,
`containerd`, `github-cli` - build like anywhere else. Most Go packages in
`::gentoo` are keyworded `~amd64`/`~arm64` only, so each needs its own
entry - an overlay cannot override another repository's keywords:

```sh
echo 'app-benchmarks/hey **' >> /etc/portage/package.accept_keywords/sparc64-go
emerge -av app-benchmarks/hey
```

## Limitations

These come from the port, not from the packaging:

* `-buildmode` is limited to `exe`. There is no PIE support, because
  SPARC V9 has no PC-relative addressing and position-independent code
  needs a register dedicated to the GOT; packages whose build system
  hard-codes `-buildmode=pie` need that turned off, as the
  `app-containers/containerd` patch here does.
* No race detector. It needs a TSan runtime port, which lives in LLVM,
  not in Go.
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

## Building other Go packages

Go software vendors its dependencies, and several very widely vendored
modules carry per-architecture files with no sparc64 variant. Without them
the vendored package has no function bodies, or no type definitions, and
the build fails — so this affects most Go software rather than a few
packages:

| module | what is missing |
|---|---|
| `golang.org/x/sys/unix` | the gc syscall trampolines. `syscall_unix_gc.go` declares those functions for every gc unix target, so the package does not compile here at all |
| `golang.org/x/sys/cpu` | `cacheLineSize`, `initOptions` |
| `golang.org/x/net/internal/socket` | the `cmsghdr`, `iovec`, `msghdr` and `mmsghdr` layouts |
| `github.com/moby/sys/signal` | SPARC has no `SIGSTKFLT`. It follows the SunOS numbering, where signal 16 is `SIGURG` and `SIGEMT` sits at 7 |
| `go.etcd.io/bbolt` | `MaxMapSize`, `MaxAllocSize` |

Patching each consumer separately does not scale, so `portage-config/`
closes the gap once, for every package that inherits `go-module`:

```sh
cp portage-config/bashrc /etc/portage/bashrc
./portage-config/sync-arch-files.sh
cp -r portage-config/patches/. /etc/portage/patches/
```

The hook runs after unpack and prepare, and handles two kinds of file:

* **Additions** — anything named `*_sparc64.*`, which upstream simply does
  not have. Added only when absent, so each becomes a no-op the day
  upstream ships its own.
* **Replacements** — for the fixes that are an edit rather than an
  addition, such as adding sparc64 to a `_64bit.go` build tag. These are
  applied only when the vendored copy still hashes to a version recorded
  in `pristine-checksums.txt`. Over anything else the file is left alone
  and a warning printed, because a newer upstream may have fixed it
  differently, or moved on.

The files themselves are not kept in this repo. They are generic to the
architecture rather than to Gentoo, so they live in
[shalseth/go-sparc64-deps](https://github.com/shalseth/go-sparc64-deps) and
`sync-arch-files.sh` mirrors them into `/etc/portage/sparc64-arch/`. One
copy, so the two cannot drift.

Verified this way: `dev-util/github-cli`, `app-containers/runc`,
`app-containers/containerd`, `app-containers/docker`,
`app-containers/docker-cli`.

`portage-config/patches/` is then only for the genuinely package-specific
remainder — currently just the two build systems that add
`-buildmode=pie` for every architecture except a short list, which sparc64
belongs on because the port has no position-independent code model.

Two things that are not sparc64 problems but look like them:

* Some ebuilds for repositories with nested Go modules ship an incomplete
  module cache — containerd's `api/` submodule is one — and need
  `FEATURES="-network-sandbox" emerge …` to fetch the remainder.
* Docker and docker-cli before 29.7.2 vendor `golang.org/x/net` v0.54.0,
  whose `http2.TrailerPrefix` is declared only in a file excluded under Go
  1.27 and newer, so `google.golang.org/grpc` fails to compile. x/net
  v0.55.0 moved the constant to an untagged file; 29.7.2 vendors v0.57.0
  and needs nothing. On an older release, build with the `http2legacy` tag.

`dockerd` creates iptables rules on startup unless told not to. On a
kernel built without those modules, `/etc/docker/daemon.json`:

```json
{
  "iptables": false,
  "ip6tables": false
}
```

## Docker

`app-containers/docker`, `docker-cli`, `containerd` and `runc` all build and
run. Containers work, including bridge networking. Three things stood between
a working toolchain and a running container, and all three are handled by the
config in `portage-config/`:

* **A wrong `Stat_t` in `golang.org/x/sys`.** The generated struct never
  matched what the sparc64 kernel writes, and `Stat`/`Lstat`/`Fstat` pointed at
  the legacy stat calls while `Fstatat` used `fstatat64` - four functions
  filling one struct from two incompatible layouts. runc reads the inode of
  `/proc` to confirm it is really procfs, got garbage, and refused to start
  anything. `fix-xsys-stat.py` corrects it in whatever x/sys version a package
  vendored.
* **A hardcoded `O_PATH` in `containerd/fifo`.** `handle_linux.go` carries its
  own `const O_PATH = 010000000`, which is right on x86, arm and mips. SPARC
  numbers its open flags differently: `O_PATH` is `0x1000000` there and
  `0x200000` is `O_NOATIME`. So the FIFO was opened for reading and blocked
  until a writer appeared - every `docker run` hung with the container stuck in
  `Created` and nothing in the log. `fix-fifo-opath.py` points it at
  `syscall.O_PATH`.
* **Missing kernel options**, none sparc64-specific. In the order they bite:
  `CONFIG_OVERLAY_FS`; `CONFIG_POSIX_MQUEUE`; `CONFIG_BPF_SYSCALL` with
  `CONFIG_CGROUP_BPF` (runc applies the device cgroup through eBPF on cgroup v2
  and there is no way to opt out); the cgroup controllers `CONFIG_MEMCG`,
  `CONFIG_CGROUP_SCHED`, `CONFIG_CPUSETS`, `CONFIG_BLK_CGROUP`,
  `CONFIG_CGROUP_PIDS`, `CONFIG_CGROUP_DEVICE`, `CONFIG_CGROUP_FREEZER`; and
  `CONFIG_VETH` for networking. `contrib/check-config.sh` from the docker
  source audits all of it.

`CONFIG_SECCOMP_FILTER` is optional - without it the daemon warns and runs
containers with no default profile. Outbound NAT needs the `IP_NF_*` set and
`"iptables": true`; with `"iptables": false` in `/etc/docker/daemon.json`,
container-to-host and container-to-container traffic still work.

### A container base image

There are no sparc64 images in any registry, so build one:

```sh
./contrib/mkimage.sh
docker run --rm -it sparc64/gentoo-base:1 bash
```

`contrib/mkimage.sh` assembles a rootfs from the running system - bash, the
core utilities, and their library closure - and imports it. It uses
`docker import` rather than a Dockerfile because `docker build` defaults to
BuildKit, which wants to pull `moby/buildkit`, and no sparc64 build of that
exists.
