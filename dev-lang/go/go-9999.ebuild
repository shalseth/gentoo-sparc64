# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3

DESCRIPTION="Go toolchain for linux/sparc64, built from the port's git branch"
HOMEPAGE="https://github.com/shalseth/go"
EGIT_REPO_URI="https://github.com/shalseth/go.git"
EGIT_BRANCH="sparc64"

LICENSE="BSD"
SLOT="0/${PV}"
KEYWORDS=""

# Go builds with Go. Either an installed toolchain or the binary
# bootstrap package can serve.
BDEPEND="|| ( dev-lang/go dev-lang/go-bootstrap )"

RESTRICT="strip test"
QA_FLAGS_IGNORED=".*"
QA_MULTILIB_PATHS="usr/lib/go/pkg/tool/.*/.*"
QA_PREBUILT="*"

src_compile() {
	# make.bash needs a Go to build with; take the installed one unless
	# the caller points somewhere else.
	export GOROOT_BOOTSTRAP="${GOROOT_BOOTSTRAP:-$(go env GOROOT)}"
	# The binary releases are built with cgo, so build the same way here.
	export GOOS=linux GOARCH=sparc64 CGO_ENABLED=1
	cd src || die
	./make.bash || die
}

src_install() {
	dodir /usr/lib/go
	cp -R . "${ED}"/usr/lib/go || die

	rm -rf "${ED}"/usr/lib/go/.git || die
	find "${ED}"/usr/lib/go -type d -name testdata -prune -exec rm -r {} + || die
	rm -rf "${ED}"/usr/lib/go/pkg/bootstrap || die

	local x f
	for x in bin/*; do
		f=${x##*/}
		dosym ../lib/go/bin/${f} /usr/bin/${f}
	done
}
