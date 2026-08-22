# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Go toolchain for linux/sparc64, built from the out-of-tree port"
HOMEPAGE="https://github.com/shalseth/go"

# Release assets are immutable, unlike GitHub's generated archive
# tarballs, so the Manifest hashes stay valid.
MY_TAG="sparc64-20260823"
SRC_URI="https://github.com/shalseth/go/releases/download/${MY_TAG}/go-${PV}-linux-sparc64.tar.xz"
S="${WORKDIR}/go"

LICENSE="BSD"
SLOT="0/${PV}"
KEYWORDS="~sparc"

# A prebuilt toolchain: stripping breaks Go binaries.
RESTRICT="strip test"
QA_FLAGS_IGNORED=".*"
QA_MULTILIB_PATHS="usr/lib/go/pkg/tool/.*/.*"
QA_PREBUILT="*"

src_install() {
	dodir /usr/lib/go
	# cp, not doins: the tool binaries need their executable bits.
	cp -R . "${ED}"/usr/lib/go || die

	local x f
	for x in bin/*; do
		f=${x##*/}
		dosym ../lib/go/bin/${f} /usr/bin/${f}
	done
}

pkg_postinst() {
	elog "This is the out-of-tree linux/sparc64 port of the Go toolchain."
	elog "cgo works, in both internal and external link modes. -buildmode"
	elog "is limited to exe, and the race detector is unavailable. go tool"
	elog "objdump and pprof's disassembly view do not work, as there is no"
	elog "sparc64 disassembler; collecting and reading profiles is fine."
}
