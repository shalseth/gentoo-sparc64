# Node.js for Linux SPARC64

This package builds the live `sparc64` branch of shalseth/node from Git using
native C/C++ and Rust toolchains. An existing Node.js installation is not needed.
Record the fetched commit and preserve Portage's build/test logs for reproducibility.

Sparkplug and TurboFan provide native JavaScript compilation. Liftoff and the
optimizing Wasm compiler support production Wasm, including GC, SIMD and JSPI.
TypeScript stripping, Temporal, FFI and snapshots are enabled together. Maglev
is disabled, and SIMD currently uses scalar SPARC instructions rather than VIS.

One intermittent native C++ failure remains unresolved:
`PlatformTest.SkipNewTasksInFlushForegroundTasks` once aborted with Abseil
`Futex operation failed with error -22` (EINVAL). Ordinary and kernel-traced
reruns, repeated platform tests and signal/waiter stress on T7 and T4 have not
reproduced it. Passing reruns do not establish that it is fixed. USE=test keeps
this failure visible if it recurs. This is an experimental out-of-tree port.

The validated hardware is SPARC T4 and M7/T7 with a 64-bit big-endian glibc
Linux userland. Initial validation used GCC 16.2.1, Rust/Cargo 1.99.0, binutils
2.47, ICU 78.3 and OpenSSL 3.6.5. Other hardware and toolchains need validation.

The ebuild uses shared system ICU and OpenSSL. Portage owns Node, npm/npx and
the headers. Its npm global configuration selects /usr headers for native addon
builds and /usr/local for separately installed global packages. Run
`source /etc/profile` after installation to pick up the environment entry.
Update Node and bundled npm through Portage. Third-party native addons may
need their own SPARC fixes and usually have no prebuilt SPARC package.

Some upstream Wasm/FFI tests assume a little-endian host, skip big-endian
architectures or retain a stale FFI arity expectation. Their original outcomes
are retained separately from derived controls; no all-tests-pass claim is made.
Experimental Wasm extensions outside the production feature set remain outside
the validated scope.

The fork's README.sparc64.md and doc/sparc64-maintenance.md describe the current
source-build workflow, upstream v26.x merges, regression gates and limitations.
