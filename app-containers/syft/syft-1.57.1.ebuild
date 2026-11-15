# Copyright 2022-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

GIT_COMMIT=a0c0d3890a9d79421c403e8fcadec50a2e55bf21

DESCRIPTION="Generate a Software Bill of Materials from container images and filesystems"
HOMEPAGE="https://github.com/anchore/syft"
SRC_URI="https://github.com/anchore/syft/archive/v${PV}.tar.gz -> ${P}.tar.gz"
# `go mod vendor` of the tag above, as a release asset of this overlay.
SRC_URI+=" https://github.com/shalseth/gentoo-sparc64/releases/download/${P}/${P}-vendor.tar.xz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~sparc"

# tests require a running docker daemon
RESTRICT="test"

BDEPEND=">=dev-lang/go-1.26.8"

PATCHES=(
	"${FILESDIR}"/${P}-sparc64-no-modernc-sqlite.patch
)

src_compile() {
	local BUILD_DATE
	BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	# as upstream's .goreleaser.yaml
	CGO_ENABLED=0 ego build -o bin/syft -ldflags "
		-X main.version=${PV}
		-X main.gitCommit=${GIT_COMMIT}
		-X main.buildDate=${BUILD_DATE}
		-X main.gitDescription=v${PV}
		" ./cmd/syft
}

src_install() {
	dobin bin/syft
	insinto /usr/share/${PN}
	doins -r examples
}
