################################################################################
#
# luanti
#
################################################################################

# The engine is the checkout this tree is in (goodluckos/buildroot), for the app: its binary takes its data from the
# folder above bin/ (CUSTOM_SHAREDIR=.), never from a system's /usr/share/luanti, and it installs into the images
# folder, not the target, where goodluckos/build.sh puts the app together
LUANTI_VERSION = 5.18.0
LUANTI_SITE = $(BR2_EXTERNAL_LUANTI_PATH)/../..
LUANTI_SITE_METHOD = local
LUANTI_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = --exclude goodluckos --exclude android
LUANTI_LICENSE = LGPL-2.1+ (code), CC-BY-SA-3.0 (textures, sounds)
LUANTI_LICENSE_FILES = LICENSE.txt
LUANTI_SUPPORTS_IN_SOURCE_BUILD = NO

LUANTI_DEPENDENCIES = freetype jpeg jsoncpp libgles libpng libvorbis luanti-libzip openal \
	sdl2 sqlite zlib zstd

# the Mali-400 only does GLES2; no server, curl (ContentDB) or databases besides sqlite, and no OpenSSL:
# Luanti hashes with its own code otherwise, and libcrypto took ~4 MB of the process
# the number stays 5.18.0 for games' min_minetest_version, the suffix goes up with each version of the app
LUANTI_CONF_OPTS = \
	-DVERSION_EXTRA=handheld.33 \
	-DBUILD_CLIENT=ON \
	-DBUILD_SERVER=OFF \
	-DBUILD_UNITTESTS=OFF \
	-DBUILD_BENCHMARKS=OFF \
	-DBUILD_DOCUMENTATION=OFF \
	-DRUN_IN_PLACE=OFF \
	-DENABLE_UPDATE_CHECKER=OFF \
	-DENABLE_LTO=OFF \
	-DENABLE_GLES2=ON \
	-DENABLE_OPENGL=OFF \
	-DENABLE_OPENGL3=OFF \
	-DENABLE_SOUND=ON \
	-DENABLE_CURL=OFF \
	-DENABLE_OPENSSL=OFF \
	-DENABLE_CURSES=OFF \
	-DENABLE_POSTGRESQL=OFF \
	-DENABLE_LEVELDB=OFF \
	-DENABLE_REDIS=OFF \
	-DENABLE_SPATIAL=OFF \
	-DENABLE_PROMETHEUS=OFF \
	-DENABLE_SYSTEM_GMP=OFF \
	-DENABLE_SYSTEM_JSONCPP=ON \
	-DLIBZIP_INCLUDE_DIR=$(STAGING_DIR)/usr/include \
	-DLIBZIP_LIBRARY=$(STAGING_DIR)/usr/lib/libzip.a \
	-DCUSTOM_SHAREDIR=. \
	-DCUSTOM_LOCALEDIR=locale

ifeq ($(BR2_PACKAGE_LUAJIT),y)
LUANTI_DEPENDENCIES += luajit
LUANTI_CONF_OPTS += -DENABLE_LUAJIT=ON -DREQUIRE_LUAJIT=ON
else
LUANTI_CONF_OPTS += -DENABLE_LUAJIT=OFF
endif

ifeq ($(BR2_SYSTEM_ENABLE_NLS),y)
LUANTI_DEPENDENCIES += $(TARGET_NLS_DEPENDENCIES)
LUANTI_CONF_OPTS += -DENABLE_GETTEXT=ON
else
LUANTI_CONF_OPTS += -DENABLE_GETTEXT=OFF
endif

define LUANTI_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) DESTDIR=$(BINARIES_DIR)/luanti $(BR2_CMAKE) --install $(LUANTI_BUILDDIR)
endef

$(eval $(cmake-package))
