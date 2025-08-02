TERMUX_PKG_HOMEPAGE=https://github.com/bylaws/wine/tree/upstream-arm64ec
TERMUX_PKG_DESCRIPTION="A compatibility layer for running Windows programs (FEX-Emu’s fork)"
TERMUX_PKG_LICENSE="LGPL-2.1"
TERMUX_PKG_LICENSE_FILE="LICENSE, LICENSE.OLD, COPYING.LIB"
TERMUX_PKG_MAINTAINER="Mir Amir Mousavi @mamousavi"
_COMMIT_DATE=2024.10.01
_COMMIT_HASH=510c42c147182dab2fcb24c68d3ceb2a4fe64e40
_FEX_VERSION=2508
TERMUX_PKG_VERSION=$_COMMIT_DATE
TERMUX_PKG_SRCURL=https://github.com/bylaws/wine/archive/$_COMMIT_HASH.tar.gz
TERMUX_PKG_SHA256=5ba4bc7d8e17972b9eb8bb19b91936bc22853700f0b71b3ebab179d77faa0506
TERMUX_PKG_DEPENDS="fontconfig, freetype, gst-plugins-base, gstreamer, krb5, libandroid-spawn, libc++, libgmp, libgnutls, libxcb, libxcomposite, libxcursor, libxfixes, libxrender, opengl, pulseaudio, sdl2 | sdl2-compat, vulkan-loader, xorg-xrandr"
TERMUX_PKG_ANTI_BUILD_DEPENDS="sdl2-compat, vulkan-loader"
TERMUX_PKG_BUILD_DEPENDS="libandroid-spawn-static, vulkan-loader-generic"
TERMUX_PKG_RECOMMENDS="gst-plugins-good"
TERMUX_PKG_SUGGESTS="gst-libav, gst-plugins-bad, gst-plugins-ugly"
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_HOSTBUILD=true
TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS="
--without-x
--disable-tests
"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
enable_wineandroid_drv=no
exec_prefix=$TERMUX_PREFIX
--with-wine-tools=$TERMUX_PKG_HOSTBUILD_DIR
--enable-nls
--disable-tests
--without-alsa
--without-capi
--without-coreaudio
--without-cups
--without-dbus
--with-fontconfig
--with-freetype
--without-gettext
--with-gettextpo=no
--without-gphoto
--with-gnutls
--with-gstreamer
--without-inotify
--with-krb5
--with-mingw=clang
--without-netapi
--without-opencl
--with-opengl
--without-osmesa
--without-oss
--without-pcap
--with-pthread
--with-pulse
--without-sane
--with-sdl
--without-udev
--without-unwind
--without-usb
--without-v4l2
--with-vulkan
--with-xcomposite
--with-xcursor
--with-xfixes
--without-xinerama
--with-xinput
--with-xinput2
--with-xrandr
--with-xrender
--without-xshape
--without-xshm
--without-xxf86vm
"

# Enable win64 on 64-bit arches.
if [ "$TERMUX_ARCH_BITS" = 64 ]; then
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --enable-win64"
fi

# Enable new WoW64 support on x86_64.
if [ "$TERMUX_ARCH" = "x86_64" ]; then
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --enable-archs=i386,x86_64"
fi

# Enable ARM64EC and new WoW64 support on aarch64.
if [ "$TERMUX_ARCH" = "aarch64" ]; then
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --enable-archs=arm64ec,aarch64,i386"
fi

TERMUX_PKG_EXCLUDED_ARCHES="arm"

termux_step_post_get_source() {
	local _fex_url="https://launchpad.net/~fex-emu/+archive/ubuntu/fex/+files/fex-emu-wine_$_FEX_VERSION~n_arm64.deb"
	local _fex_sha256=0c8ec0c15cfac425af2fa78fc59ee0811725005e54b0dbfca7a5276e91bf1339
	termux_download $_fex_url "$TERMUX_PKG_CACHEDIR/fex.deb" $_fex_sha256
}

_setup_llvm_mingw_toolchain() {
	# LLVM-mingw's version number must not be the same as the NDK's.
	local _llvm_mingw_version=19
	local _version="20240929"
	local _url="https://github.com/bylaws/llvm-mingw/releases/download/$_version/llvm-mingw-$_version-ucrt-ubuntu-20.04-x86_64.tar.xz"
	local _path="$TERMUX_PKG_CACHEDIR/$(basename $_url)"
	local _sha256sum=ce75ad076c87663fd4a77513e947252d97ce799a11926c1f3ac7afed1d6ab85c
	termux_download $_url $_path $_sha256sum
	local _extract_path="$TERMUX_PKG_CACHEDIR/llvm-mingw-toolchain-$_llvm_mingw_version"
	if [ ! -d "$_extract_path" ]; then
		mkdir -p "$_extract_path"-tmp
		tar -C "$_extract_path"-tmp --strip-component=1 -xf "$_path"
		mv "$_extract_path"-tmp "$_extract_path"
	fi
	export PATH="$_extract_path/bin:$PATH"
}

termux_step_host_build() {
	# Setup llvm-mingw toolchain
	_setup_llvm_mingw_toolchain

	# Make host wine-tools
	"$TERMUX_PKG_SRCDIR/configure" ${TERMUX_PKG_EXTRA_HOSTBUILD_CONFIGURE_ARGS}
	make -j "$TERMUX_PKG_MAKE_PROCESSES" __tooldeps__ nls/all
}

termux_step_pre_configure() {
	# Setup llvm-mingw toolchain
	_setup_llvm_mingw_toolchain

	# Fix overoptimization
	CPPFLAGS="${CPPFLAGS/-Oz/}"
	CFLAGS="${CFLAGS/-Oz/}"
	CXXFLAGS="${CXXFLAGS/-Oz/}"

	# Disable hardening
	CPPFLAGS="${CPPFLAGS/-fstack-protector-strong/}"
	CFLAGS="${CFLAGS/-fstack-protector-strong/}"
	CXXFLAGS="${CXXFLAGS/-fstack-protector-strong/}"
	LDFLAGS="${LDFLAGS/-Wl,-z,relro,-z,now/}"

	LDFLAGS+=" -landroid-spawn"

	if [ "$TERMUX_ARCH" = "x86_64" ]; then
		mkdir -p "$TERMUX_PKG_TMPDIR/bin"
		cat <<- EOF > "$TERMUX_PKG_TMPDIR/bin/x86_64-linux-android-clang"
			#!/bin/bash
			set -- "\${@/-mabi=ms/}"
			exec $TERMUX_STANDALONE_TOOLCHAIN/bin/x86_64-linux-android-clang "\$@"
		EOF
		chmod +x "$TERMUX_PKG_TMPDIR/bin/x86_64-linux-android-clang"
		export PATH="$TERMUX_PKG_TMPDIR/bin:$PATH"
	fi
}

termux_step_make_install() {
	make -j $TERMUX_PKG_MAKE_PROCESSES install
}

termux_step_post_make_install() {
	# Install FEX-based dlls
	dpkg-deb -x "$TERMUX_PKG_CACHEDIR/fex.deb" "$TERMUX_BASE_DIR"
}
