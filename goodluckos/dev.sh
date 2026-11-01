#!/usr/bin/env bash
# build.sh on a Mac or PC, in goodluckOS's dev container (its dev/gl builds the image goodluck-dev), in the Buildroot
# tree dev/gl keeps in the goodluck-work volume, so only what changed is built again.
#   goodluckos/dev.sh [goodluckOS checkout, default ../goodluckOS]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FORK=$(dirname "$HERE")
OS=$(cd "${1:-$FORK/../goodluckOS}" && pwd)
VOLUME=goodluck-work

# one Buildroot at a time in the volume, as dev/gl does
busy=$(docker ps --filter volume=$VOLUME --format '{{.Names}} ({{.Image}}): {{.Command}}')
[ -z "$busy" ] || { echo "another container uses $VOLUME, try again when it ends:"; echo "$busy"; exit 1; }
docker image inspect goodluck-dev > /dev/null 2>&1 || { echo "no goodluck-dev image: run dev/gl image in $OS"; exit 1; }
tty=; [ -t 0 ] && tty=-t
stamp=$(TZ=UTC git -C "$FORK" show -s --format=%cd --date=format-local:%Y%m%d-%H%M HEAD)-$(git -C "$FORK" rev-parse --short=9 HEAD)
[ -z "$(git -C "$FORK" status --porcelain --untracked-files=no)" ] || stamp=$stamp-dirty
docker run --rm -i $tty -e APP_STAMP="$stamp" -v "$FORK:/luanti" -v "$OS:/os:ro" -v $VOLUME:/work goodluck-dev \
    bash -c '/luanti/goodluckos/build.sh /os /work/br /work/br/out /work/br/dl; rc=$?
        # dev/gl applies goodluckOS'"'"'s own defconfig at its next build, and the target keeps no Luanti
        rm -f /work/br/.defconfig-used; exit $rc'
