# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit check-reqs git-r3 java-pkg-2 java-vm-2 multiprocessing toolchain-funcs

# Based on ::gentoo dev-java/openjdk-25.0.5.1_p2. The source is the newest
# jdk25u tag that has a .pls.linux list in the patch repository, with
# Peter Tribble's .pls and .pls.sparc lists and our .pls.linux applied.
BOOT_PV="25.0.5.1"
JDK_REPO_URI="https://github.com/openjdk/jdk25u.git"

DESCRIPTION="OpenJDK 25 with the SPARC JIT, built from the Linux sparc64 patch lists"
HOMEPAGE="https://github.com/shalseth/jdk-sunos-patches/tree/linux-sparc"
EGIT_REPO_URI="https://github.com/shalseth/jdk-sunos-patches.git"
EGIT_BRANCH="linux-sparc"
EGIT_CLONE_TYPE="shallow"
# Used only when no openjdk:25 is installed. ::gentoo's system-bootstrap
# flag cannot do this: the base profile forces it on for openjdk:25.
SRC_URI="https://github.com/shalseth/jdk-sunos-patches/releases/download/bootstrap-${BOOT_PV}/openjdk-bootstrap-${BOOT_PV}-sparc64.tar.xz"

LICENSE="GPL-2-with-classpath-exception"
SLOT="25"
KEYWORDS=""
IUSE="alsa cups debug examples headless-awt selinux source"

COMMON_DEPEND="
	media-libs/freetype:2=
	media-libs/giflib:0/7
	media-libs/harfbuzz:=
	media-libs/libpng:0=
	media-libs/lcms:2=
	virtual/zlib:=
	!headless-awt? (
		x11-libs/libX11
		x11-libs/libXext
		x11-libs/libXi
		x11-libs/libXrandr
		x11-libs/libXrender
		x11-libs/libXt
		x11-libs/libXtst
	)
	media-libs/libjpeg-turbo:0=
"
RDEPEND="
	${COMMON_DEPEND}
	>=sys-apps/baselayout-java-0.1.0-r1
	alsa? ( media-libs/alsa-lib )
	cups? ( net-print/cups )
	selinux? ( sec-policy/selinux-java )
"
DEPEND="
	${COMMON_DEPEND}
	app-arch/zip
	media-libs/alsa-lib
	net-print/cups
	!headless-awt? ( x11-base/xorg-proto )
"

CHECKREQS_DISK_BUILD="8G"

pkg_pretend() {
	[[ ${CHOST} == sparc64-*-linux-* ]] || die "This port requires 64-bit Linux SPARC64"
	if [[ ${MERGE_TYPE} != binary ]]; then
		has ccache ${FEATURES} && die "FEATURES=ccache doesn't work with ${PN}, bug #677876"
	fi
	check-reqs_pkg_pretend
}

pkg_setup() {
	check-reqs_pkg_setup
	java-vm-2_pkg_setup

	[[ ${MERGE_TYPE} == "binary" ]] && return

	JAVA_PKG_WANT_BUILD_VM="openjdk-${SLOT}"
	JAVA_PKG_WANT_SOURCE="${SLOT}"
	JAVA_PKG_WANT_TARGET="${SLOT}"
}

# The lists for one tag are named after the tag, e.g. jdk25u-jdk-25.0.5.1-ga.
# JDK_SPARC_ALIAS picks an older one.
jdk_alias() {
	cat "${WORKDIR}"/jdk-alias || die
}

src_unpack() {
	local patches="${WORKDIR}"/patches
	git-r3_fetch
	git-r3_checkout "${EGIT_REPO_URI}" "${patches}"
	echo "${EGIT_VERSION}" > "${WORKDIR}"/patches-commit || die

	local alias=${JDK_SPARC_ALIAS}
	if [[ -z ${alias} ]]; then
		alias=$(cd "${patches}"/jdk${SLOT} &&
			ls jdk${SLOT}u-jdk-*.pls.linux | sed 's/\.pls\.linux$//' | sort -V | tail -n 1)
	fi
	[[ -f ${patches}/jdk${SLOT}/${alias}.pls.linux ]] || die "No Linux patch list for ${alias}"
	echo "${alias}" > "${WORKDIR}"/jdk-alias || die

	local tag=${alias#jdk${SLOT}u-}
	einfo "Building ${tag} with patch lists ${alias} from ${EGIT_VERSION}"
	git-r3_fetch "${JDK_REPO_URI}" "refs/tags/${tag}" "${CATEGORY}/${PN}/${SLOT}-jdk"
	git-r3_checkout "${JDK_REPO_URI}" "${S}" "${CATEGORY}/${PN}/${SLOT}-jdk"

	unpack ${A}
}

src_prepare() {
	local alias=$(jdk_alias)
	local dir="${WORKDIR}"/patches/jdk${SLOT}
	local list arg file

	# Same order and options as jdk-sunos-builder: the version's list, then
	# the cpu list, then the os list. "-p1+-R" means "-p1 -R".
	for list in pls pls.sparc pls.linux; do
		while read -r arg file; do
			eapply ${arg/+/ } "${dir}/${file}"
		done < "${dir}/${alias}.${list}" || die
	done

	eapply_user
	chmod +x configure || die
}

src_configure() {
	if has_version -b dev-java/openjdk:${SLOT}; then
		export JDK_HOME=${BROOT}/usr/$(get_libdir)/openjdk-${SLOT}
	else
		export JDK_HOME="${WORKDIR}/openjdk-bootstrap-${BOOT_PV}"
		addpredict /dev/random
		addpredict /proc/self/coredump_filter
	fi

	local alias=$(jdk_alias)
	local version=${alias#jdk${SLOT}u-jdk-}
	version=${version%-ga}

	# The port is tested with the JDK's own compiler flags, so user CFLAGS
	# and LDFLAGS are not passed on.
	local myconf=(
		--disable-ccache
		--disable-precompiled-headers
		--disable-warnings-as-errors
		--enable-full-docs=no
		--enable-unlimited-crypto
		--with-boot-jdk="${JDK_HOME}"
		--with-toolchain-type=gcc
		--with-freetype=system
		--with-giflib=system
		--with-harfbuzz=system
		--with-lcms=system
		--with-libjpeg=system
		--with-libpng=system
		--with-zlib=system
		--with-stdc++lib=dynamic
		--with-native-debug-symbols=$(usex debug internal none)
		--with-vendor-version-string="sparc64-$(head -c 8 "${WORKDIR}"/patches-commit)"
		--with-version-pre=""
		--with-version-opt=""
		--with-version-string="${version}"
		--enable-headless-only=$(usex headless-awt yes no)
	)

	(
		unset _JAVA_OPTIONS JAVA JAVA_TOOL_OPTIONS JAVAC XARGS
		CFLAGS= CXXFLAGS= LDFLAGS= \
		CONFIG_SITE=/dev/null \
		econf "${myconf[@]}"
	)
}

src_compile() {
	export MAKEOPTS="-j$(makeopts_jobs) -l$(makeopts_loadavg)"
	unset GNUMAKEFLAGS MAKEFLAGS

	local myemakeargs=(
		JOBS=$(makeopts_jobs)
		LOG=info
		CFLAGS_WARNINGS_ARE_ERRORS= # No -Werror
		NICE= # Use PORTAGE_NICENESS, don't adjust further down
		product-images
	)
	emake "${myemakeargs[@]}" -j1
}

src_test() {
	:
}

src_install() {
	local dest="/usr/$(get_libdir)/${PN}-${SLOT}"
	local ddest="${ED}/${dest#/}"

	docompress "${dest}/man"

	cd "${S}"/build/*-release/images/jdk || die

	# Create files used as storage for system preferences.
	mkdir .systemPrefs || die
	touch .systemPrefs/.system.lock || die
	touch .systemPrefs/.systemRootModFile || die

	if ! use alsa ; then
		rm -v lib/libjsound.* || die
	fi

	if ! use examples ; then
		rm -vr demo/ || die
	fi

	if ! use source ; then
		rm -v lib/src.zip || die
	fi

	rm -v lib/security/cacerts || die

	dodir "${dest}"
	cp -pPR * "${ddest}" || die

	dosym -r /etc/ssl/certs/java/cacerts "${dest}"/lib/security/cacerts

	# must be done before running itself
	java-vm_set-pax-markings "${ddest}"

	einfo "Creating the Class Data Sharing archives and disabling usage tracking"
	"${ddest}/bin/java" -server -Xshare:dump -Djdk.disableLastUsageTracking || die

	java-vm_install-env "${FILESDIR}"/${PN}.env.sh
	java-vm_revdep-mask
	java-vm_sandbox-predict /dev/random /proc/self/coredump_filter
}

pkg_postinst() {
	java-vm-2_pkg_postinst
	elog "This is a live build of the Linux sparc64 JIT port."
	elog "'java -version' shows the patch list commit after 'sparc64-'."
}
