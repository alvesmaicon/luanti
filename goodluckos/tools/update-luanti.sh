#!/bin/sh
# The app's zip as a package for Update Luanti, the updater of goodluckOS images from before the App Installer (they
# carry Luanti in /usr and update it from HOME/updates): luanti-<version>.tar.xz, data only, the paths that updater
# takes. The whole app goes in usr/share/luanti, which it swaps at once; usr/bin/luanti, which the image's luanti.sh
# runs, becomes a script that runs the app there with its libraries; the image's scripts and the conf's defaults come
# with it, the scripts from goodluckOS's last commit that had them (898642d), the defaults from the app. Worlds and
# settings stay in ~/.minetest, as with the app. The updater checks files.md5 and the version (the app's
# goodluck-version: the commit's UTC date and hash, only forward) before it touches anything.
# GNU tar writes it (ustar, root's), so it runs on Linux, as in goodluckOS's dev container.
#   goodluckos/tools/update-luanti.sh <app zip> <goodluckOS checkout> [out dir]
set -eu
ZIP=$1 GLOS=$2 OUT=${3:-$(dirname "$ZIP")}
SCRIPTS=898642d
OVERLAY=rootfs/board/my-device/rootfs-overlay
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

unzip -q "$ZIP" -d "$stage/zip"
app=$stage/zip/Luanti
version=$(head -n 1 "$app/goodluck-version")
s=$stage/pkg
mkdir -p "$s/usr/share" "$s/usr/bin" "$s/usr/local/bin" "$s/usr/share/goodluck/defaults"
mv "$app" "$s/usr/share/luanti"
cat > "$s/usr/bin/luanti" <<'EOF'
#!/bin/sh
# Luanti as the App Installer's app, where Update Luanti puts it (CUSTOM_SHAREDIR is the folder it runs in)
cd /usr/share/luanti || exit 1
export LD_LIBRARY_PATH=/usr/share/luanti/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /usr/share/luanti/bin/luanti "$@"
EOF
for f in luanti.sh luanti-update.sh luanti-perflog.sh; do
    git -C "$GLOS" show "$SCRIPTS:$OVERLAY/usr/local/bin/$f" > "$s/usr/local/bin/$f"
done
cp "$s/usr/share/luanti/goodluck/luanti.conf" "$s/usr/share/goodluck/defaults/luanti.conf"
chmod 755 "$s/usr/bin/luanti" "$s"/usr/local/bin/*.sh
(cd "$s" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum) > "$s/files.md5"
pkg=$OUT/luanti-$version.tar.xz
(cd "$s" && tar --format=ustar --owner=root:0 --group=root:0 --sort=name -cf - usr files.md5) | xz -9 > "$pkg"
echo "${pkg##*/}: $(wc -l < "$s/files.md5") files, $(($(wc -c < "$pkg") / 1024)) KB"
