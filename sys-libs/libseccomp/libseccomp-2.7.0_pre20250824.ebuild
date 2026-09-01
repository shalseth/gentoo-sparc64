# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools multilib-minimal

# Head of https://github.com/seccomp/libseccomp/pull/471 ("RFE: Add SPARC
# support" plus a syscall-table update to Linux v6.17-rc2). Drop this
# ebuild once a libseccomp release containing SPARC support is keyworded
# in ::gentoo.
MY_COMMIT="51a837accc334a6fb9124cc5b83cf8eef6c31c24"

# What upstream master is heading towards; stamped into configure.ac,
# which carries 0.0.0 between releases.
PRERELEASE="2.7.0"

DESCRIPTION="High level interface to Linux seccomp filter, with SPARC support"
HOMEPAGE="https://github.com/seccomp/libseccomp"
SRC_URI="https://github.com/seccomp/libseccomp/archive/${MY_COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-${MY_COMMIT}"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="-* ~sparc"
IUSE="static-libs test"
RESTRICT="!test? ( test )"

DEPEND=">=sys-kernel/linux-headers-5.15"
BDEPEND="
	${DEPEND}
	dev-util/gperf
"

src_prepare() {
	default

	sed -i -e "s/0\.0\.0/${PRERELEASE}/" configure.ac || die
	eautoreconf
}

multilib_src_configure() {
	local myeconfargs=(
		$(use_enable static-libs static)
		--disable-python
	)

	ECONF_SOURCE="${S}" econf "${myeconfargs[@]}"
}

multilib_src_test() {
	emake -Onone check
}

multilib_src_install() {
	emake DESTDIR="${D}" install
}

multilib_src_install_all() {
	find "${ED}" -type f -name "${PN}.la" -delete || die

	einstalldocs
}
