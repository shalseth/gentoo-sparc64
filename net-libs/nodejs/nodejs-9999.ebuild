# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{12..14} )
RUST_MIN_VER="1.99.0"
inherit check-reqs flag-o-matic git-r3 python-any-r1 rust toolchain-funcs

DESCRIPTION="Node.js built from the out-of-tree Linux SPARC64 port"
HOMEPAGE="https://github.com/shalseth/node/tree/sparc64"
EGIT_REPO_URI="https://github.com/shalseth/node.git"
EGIT_BRANCH="sparc64"
EGIT_CLONE_TYPE="shallow"

LICENSE="Apache-1.1 Apache-2.0 Artistic-2 BlueOak-1.0.0 BSD BSD-2 MIT"
SLOT="0/26"
KEYWORDS=""
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND=">=dev-libs/icu-78:0=
	>=dev-libs/openssl-3:0="
DEPEND="${RDEPEND}"
BDEPEND="${PYTHON_DEPS}
	${RUST_DEPEND}
	>=sys-devel/gcc-16[cxx]
	sys-devel/binutils
	virtual/pkgconfig"
CHECKREQS_MEMORY="8G"
CHECKREQS_DISK_BUILD="22G"

pkg_pretend() {
	[[ ${CHOST} == sparc64-*-linux-* ]] || die "This port requires 64-bit Linux SPARC64"
	check-reqs_pkg_pretend
}

pkg_setup() {
	python-any-r1_pkg_setup
	rust_pkg_setup
}

src_prepare() {
	default
	tc-export AR CC CXX NM OBJCOPY PKG_CONFIG
}

src_configure() {
	filter-lto
	export CARGO_NET_OFFLINE=true
	"${EPYTHON}" configure.py --dest-cpu=sparc64 --enable-d8 \
		--prefix="${EPREFIX}/usr" --use-prefix-to-find-headers \
		--v8-disable-maglev --v8-enable-verify-heap \
		--shared-openssl --with-intl=system-icu --v8-enable-temporal-support \
		-Dv8_enable_sparkplug=1 -Dv8_enable_turbofan=1 || die
}

src_compile() {
	emake
}

src_test() {
	# Keep failures visible, including the unresolved intermittent futex EINVAL.
	out/Release/cctest || die "Native C++ tests failed; preserve build.log"
	local node="${S}/out/Release/node"
	local fixtures="${S}/tools/sparc64/release-validation"
	"${node}" "${fixtures}/typescript/main.ts" || die
	"${node}" --expose-gc --verify-heap "${fixtures}/temporal.cjs" || die
	"${node}" "${fixtures}/node-apis.cjs" || die
	local tier
	for tier in liftoff optimized; do
		local flags=( --liftoff-only )
		[[ ${tier} == optimized ]] && flags=( --no-liftoff --no-liftoff-only )
		WASM_SIMD_TIER="${tier}" "${node}" --allow-natives-syntax --expose-gc \
			--verify-heap --no-wasm-lazy-compilation "${flags[@]}" \
			"${fixtures}/wasm-simd.cjs" || die
		WASM_SIMD_TIER="${tier}" "${node}" --allow-natives-syntax --expose-gc \
			--verify-heap --no-wasm-lazy-compilation "${flags[@]}" \
			"${fixtures}/wasm-gc-jspi.cjs" || die
	done
}

src_install() {
	"${EPYTHON}" tools/install.py install --dest-dir="${D}" \
		--prefix="${EPREFIX}/usr" --silent || die
	dodir "/usr/share/doc/${PF}"
	mv "${ED}/usr/share/doc/node" "${ED}/usr/share/doc/${PF}/v8" || die
	cp -a tools/sparc64/release-validation "${ED}/usr/share/doc/${PF}/validation" || die
	docompress -x "/usr/share/doc/${PF}/validation"
	dodoc LICENSE README.sparc64.md doc/sparc64-maintenance.md
	newdoc "${FILESDIR}/nodejs-sparc64-notes.md" SPARC64-NOTES.md
	newdoc out/Release/obj/gen/release/libnode_crates.a.sparc64.a.json RUST-LIBM-ISOLATION.json

	insinto /etc/npm
	printf 'nodedir=%s/usr\nprefix=%s/usr/local\n' "${EPREFIX}" "${EPREFIX}" > "${T}/npmrc" || die
	doins "${T}/npmrc"
	printf 'NPM_CONFIG_GLOBALCONFIG=%s/etc/npm/npmrc\n' "${EPREFIX}" > "${T}/50npm" || die
	doenvd "${T}/50npm"
}

pkg_postinst() {
	elog "This is a live SPARC64 development build. Keep its commit and build/test logs."
	elog "Maglev is disabled; one intermittent native C++ futex EINVAL remains unresolved."
	elog "Run 'source /etc/profile' before using npm in your current shell."
	elog "Portage owns Node and npm; global npm packages use /usr/local."
}
