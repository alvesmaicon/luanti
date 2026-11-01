#!/usr/bin/env bash
# The Luanti app for goodluckOS: Buildroot builds this checkout's engine and the game with goodluckOS's toolchain and
# libraries, then the app's folder is put together and zipped into goodluckos/out (see goodluckos/README.md).
#   goodluckos/build.sh <goodluckOS checkout> <Buildroot root> [output dir] [downloads dir]
# The Buildroot root holds Buildroot's source in buildroot/, as goodluckOS's rootfs/Dockerfile (/src) and dev/gl's work
# volume (/work/br) have it: goodluckOS's external tree goes next to it, where its Config.in looks for it.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FORK=$(dirname "$HERE")
os=$1 br=$2 out=${3:-$2/out} dl=${4:-$2/dl}
LOCALES=${LOCALES:-pt_BR}      # the engine's translations the app keeps, as goodluckOS's image kept them

# goodluckOS's external tree, without the Luanti packages its older commits had, and its defconfig with the app's
for d in board configs package; do rsync -a --delete "$os/rootfs/$d/" "$br/$d/"; done
rm -rf "$br/package/luanti" "$br/package/luanti-game"
sed -i '/package\/luanti/d' "$br/package/Config.in"
printf 'name: GOODLUCKOS\ndesc: An enthusiast OS for the GA36-MB\n' > "$br/external.desc"
echo 'include $(sort $(wildcard $(BR2_EXTERNAL_GOODLUCKOS_PATH)/package/*/*.mk))' > "$br/external.mk"
echo "source \"$br/package/Config.in\"" > "$br/Config.in"
{ grep -v '^BR2_PACKAGE_LUANTI' "$br/configs/goodluck_defconfig"; printf 'BR2_PACKAGE_LUANTI=y\nBR2_PACKAGE_LUANTI_GAME=y\n'; } \
    > "$br/configs/luanti_app_defconfig"
mkdir -p "$out" "$dl"
make="make -C $br/buildroot O=$out BR2_EXTERNAL=$br:$HERE/buildroot BR2_DL_DIR=$dl"
$make luanti_app_defconfig
date +%T
# -reconfigure syncs this checkout into the build again and runs CMake with luanti.mk's options (only what changed is
# compiled again); the game is put together anew
$make luanti-reconfigure luanti-game-dirclean luanti-game
date +%T

# the commit's date in UTC and its hash; APP_STAMP when git can't read the checkout here (a worktree in a container)
git() { command git -c safe.directory='*' -C "$FORK" "$@"; }
mk=$HERE/buildroot/package/luanti/luanti.mk
ver=$(sed -n 's/^LUANTI_VERSION = //p' "$mk")-$(sed -n 's/.*-DVERSION_EXTRA=\([^ ]*\).*/\1/p' "$mk")
stamp=${APP_STAMP:-$(TZ=UTC git show -s --format=%cd --date=format-local:%Y%m%d-%H%M HEAD)-$(git rev-parse --short=9 HEAD)}
[ -n "${APP_STAMP:-}" ] || [ -z "$(git status --porcelain --untracked-files=no)" ] || stamp=$stamp-dirty
u=$out/images/luanti/usr t=$out/target a=$out/luanti-app/Luanti
strings "$u/bin/luanti" | grep -xF "$ver" > /dev/null || { echo "the engine built isn't $ver"; exit 1; }

rm -rf "${a%/*}"; mkdir -p "$a/bin" "$a/lib"
strip=$(ls "$out"/host/bin/*-buildroot-linux-gnueabihf-strip | head -n 1)
"$strip" --remove-section=.comment --remove-section=.note -o "$a/bin/luanti" "$u/bin/luanti"
cp -a "$u/builtin" "$u/client" "$u/fonts" "$u/textures" "$u/games" "$a/"
for l in $LOCALES; do
    [ -f "$u/locale/$l/LC_MESSAGES/luanti.mo" ] || continue
    mkdir -p "$a/locale/$l/LC_MESSAGES"; cp "$u/locale/$l/LC_MESSAGES/luanti.mo" "$a/locale/$l/LC_MESSAGES/"
done
cp "$FORK/LICENSE.txt" "$a/"
cp "$FORK/misc/luanti-xorg-icon-128.png" "$a/icon.png"
cp -a "$HERE/app/." "$a/"
sed -i "s/@VERSION@/$ver-${stamp%%-*}/" "$a/app.puppy"
echo "$stamp" > "$a/goodluck-version"

# what the engine needs that any goodluckOS has (glibc, the C++ runtime, SDL2 and the libraries Puppy draws with);
# everything else comes with the app in lib/, under its soname, with what it needs in turn
have=" ld-linux-armhf.so.3 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libstdc++.so.6 libgcc_s.so.1
    libSDL2-2.0.so.0 libz.so.1 libpng16.so.16 libfreetype.so.6 libasound.so.2 libdrm.so.2 libEGL.so.1 libGLESv2.so.2 "
have=$(echo $have | sed 's/^/ /; s/$/ /')
needed() { readelf -d "$1" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'; }
need=$(needed "$a/bin/luanti")
while [ -n "$need" ]; do
    set -- $need; need=
    for l; do
        case $have in *" $l "*) continue ;; esac
        have="$have$l "
        f=$t/usr/lib/$l; [ -e "$f" ] || f=$t/lib/$l
        [ -e "$f" ] || { echo "no $l in the target"; exit 1; }
        cp -L "$f" "$a/lib/$l"
        need="$need $(needed "$a/lib/$l")"
    done
done

# what the card (FAT) can't hold: links, names it refuses, names that differ only in case
bad=$(cd "${a%/*}" && { find Luanti -type l; find Luanti -name '*[\\:*?"<>|]*'; find Luanti | tr A-Z a-z | sort | uniq -d; })
[ -z "$bad" ] || { echo "not for a FAT card:"; echo "$bad"; exit 1; }

python=$(command -v python3 || echo "$out/host/bin/python3")
mkdir -p "$HERE/out"; zip=$HERE/out/Luanti-$ver-$stamp.zip; rm -f "$zip"
(cd "${a%/*}" && "$python" -c 'import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk("Luanti"):
        dirs.sort()
        for f in sorted(files): z.write(os.path.join(root, f))' "$zip")
echo "== goodluckos/out/${zip##*/}: $(find "$a" -type f | wc -l) files, $(du -sm "$a" | cut -f1) MB unpacked," \
    "$(($(stat -c %s "$zip") / 1024 / 1024)) MB zipped, lib/: $(ls "$a/lib" | tr '\n' ' ')"
