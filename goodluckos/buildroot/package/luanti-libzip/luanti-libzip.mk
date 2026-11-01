################################################################################
#
# luanti-libzip
#
################################################################################

# Luanti 5.18 extracts ZIP files with libzip: a static library with zlib only, so the app brings no shared libzip and
# loads no OpenSSL (Buildroot's libzip would pull libcrypto in)
LUANTI_LIBZIP_VERSION = 1.11.4
LUANTI_LIBZIP_SOURCE = libzip-$(LUANTI_LIBZIP_VERSION).tar.xz
LUANTI_LIBZIP_SITE = https://libzip.org/download
LUANTI_LIBZIP_LICENSE = BSD-3-Clause
LUANTI_LIBZIP_LICENSE_FILES = LICENSE
LUANTI_LIBZIP_INSTALL_STAGING = YES
LUANTI_LIBZIP_INSTALL_TARGET = NO
LUANTI_LIBZIP_DEPENDENCIES = zlib
LUANTI_LIBZIP_CONF_OPTS = \
	-DBUILD_SHARED_LIBS=OFF \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DBUILD_TOOLS=OFF \
	-DBUILD_REGRESS=OFF \
	-DBUILD_OSSFUZZ=OFF \
	-DBUILD_EXAMPLES=OFF \
	-DBUILD_DOC=OFF \
	-DENABLE_COMMONCRYPTO=OFF \
	-DENABLE_GNUTLS=OFF \
	-DENABLE_MBEDTLS=OFF \
	-DENABLE_OPENSSL=OFF \
	-DENABLE_WINDOWS_CRYPTO=OFF \
	-DENABLE_BZIP2=OFF \
	-DENABLE_LZMA=OFF \
	-DENABLE_ZSTD=OFF

$(eval $(cmake-package))
