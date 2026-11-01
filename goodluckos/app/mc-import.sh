#!/bin/sh
# mc-import.sh: gives Luanti the textures, sounds and music of the player's own Minecraft while a copy of its
# .minecraft folder is in HOME, and takes them away once the copy is gone. The app's second launcher entry runs it, as
# the player, on the text console, in the app's folder.
HOMEDIR=$HOME
LOG=$HOMEDIR/logs/luanti-minecraft.log
GAME=$(pwd)/games/minetest_game
# the player's Minecraft: goodluck_mcassets names the textures, Luanti reads textures/server, the mod reads the list
MINETEST=$HOMEDIR/.minetest
TABLE=$GAME/mods/goodluck_mcassets/textures.txt
SOUNDS=$GAME/mods/goodluck_mcassets/sounds.txt
MUSIC=$GAME/mods/goodluck_mcassets/music.txt
MC_MUSIC=$MINETEST/music
MC_DEST=$MINETEST/textures/server/minecraft
MC_LIST=$MINETEST/mod_data/goodluck_mcassets/imported.txt
MC_STAGE=/tmp/luanti-minecraft

# Puppy's language setting; the Portuguese is here, not in pt-BR.lang, so that the app brings its messages' translation
LANGUAGE=$(sed -n 's/^language=//p' "$HOMEDIR/.config/puppy/settings" 2>/dev/null | tail -n 1)
translate() {
    [ "$LANGUAGE" = pt-BR ] || return 0
    awk -v key="$1" 'index($0, key " = ") == 1 { print substr($0, length(key) + 4); exit }' <<'LANG'
Minecraft look for Luanti = Visual do Minecraft no Luanti
Minecraft found in %s: taking its textures... = Minecraft encontrado em %s: pegando as texturas dele...
No Minecraft: Java Edition client (versions/<version>/<version>.jar) in the copy: nothing was taken = Não há um cliente do Minecraft: Java Edition (versions/<versão>/<versão>.jar) na cópia: nada foi pego
None of Luanti's textures is in Minecraft %s: nothing was taken = Nenhuma textura do Luanti está no Minecraft %s: nada foi pego
Could not write to HOME: Luanti's own textures are back = Não deu para gravar na HOME: as texturas do próprio Luanti voltaram
%s of the %s textures Luanti can take are Minecraft %s's now = %s das %s texturas que o Luanti pode pegar agora são as do Minecraft %s
%s sounds came from Minecraft %s too = %s sons também vieram do Minecraft %s
Copying the music of Minecraft %s (%s tracks)... = Copiando as músicas do Minecraft %s (%s faixas)...
%s music tracks are on the card = %s músicas estão no cartão
The copy has no assets folder: Luanti keeps its own sounds = A cópia não tem a pasta assets: o Luanti fica com os sons dele
The Minecraft copy is gone from HOME: Luanti's own textures are back = A cópia do Minecraft saiu da HOME: as texturas do próprio Luanti voltaram
Back to the menu in %s s = Voltando ao menu em %s s
No copy of .minecraft in HOME: copy it there as minecraft or .minecraft = Nenhuma cópia do .minecraft na HOME: copie a pasta para lá como minecraft ou .minecraft
LANG
}

# the console's font has no accents; one letter at a time, as BusyBox's sed reads a [...] of them byte by byte
ascii() {
    printf '%s' "$1" | sed 's/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/é/e/g; s/ê/e/g; s/í/i/g; s/ó/o/g; s/ô/o/g; s/õ/o/g;
        s/ú/u/g; s/ç/c/g; s/Á/A/g; s/À/A/g; s/Â/A/g; s/Ã/A/g; s/É/E/g; s/Ê/E/g; s/Í/I/g; s/Ó/O/g; s/Ô/O/g; s/Õ/O/g;
        s/Ú/U/g; s/Ç/C/g'
}

# say "English text with %s" [args]: translated as Puppy is, on the screen and in the log
say() {
    _fmt=$(translate "$1")
    [ -n "$_fmt" ] || _fmt=$1
    shift
    _msg=$(printf "$_fmt" "$@")
    ascii "$_msg" | fold -s -w 76 | sed 's/^/  /'
    printf '\n'
    echo "$(date '+%F %T') $_msg" >> "$LOG"
}

finish() {
    sync
    printf '\n'
    say "Back to the menu in %s s" 10
    sleep 10
    exit "$1"
}

fail() {
    say "$@"
    rm -rf "$MC_STAGE"
    finish 1
}

# one setting in HOME/.minetest/minetest.conf, as run.sh sets them
set_conf() {
    mkdir -p "$MINETEST"
    if grep -q "^$1 *=" "$MINETEST/minetest.conf" 2>/dev/null; then
        sed -i "s|^$1 *=.*|$1 = $2|" "$MINETEST/minetest.conf"
    else
        echo "$1 = $2" >> "$MINETEST/minetest.conf"
    fi
}

# Luanti's look and sounds from the player's own Minecraft, a copy of its .minecraft folder in HOME: the textures
# textures.txt names ({path} = assets/minecraft/textures/<path>.png), from the client jar with the most textures among
# the copy's versions, as mc_<path with _>.png, and the list of what came; a texture the jar lacks keeps Luanti's own.
# Then the sounds sounds.txt names, found by hash in the asset index of the jar's version (the newest index when that
# is not known), each under the game's file names so that it plays in place of the game's, and the music music.txt
# names into HOME/.minetest/music/<set>, where the engine plays it (a track already there, of the same size, stays).
# The copy gone, so are they.
minecraft() {
    src=""
    for d in "$HOMEDIR/minecraft" "$HOMEDIR/.minecraft"; do
        [ -d "$d/versions" ] && src=$d && break
    done
    if [ -z "$src" ]; then
        [ -d "$MC_DEST" ] || return 1
        say "The Minecraft copy is gone from HOME: Luanti's own textures are back"
        rm -rf "$MC_DEST" "$MC_LIST" "$MC_MUSIC"
        set_conf goodluck_mc_assets false
        return 0
    fi
    say "Minecraft found in %s: taking its textures..." "${src##*/}"
    jar="" best=0
    for j in "$src"/versions/*/*.jar; do
        [ -f "$j" ] || continue
        n=$(unzip -l "$j" 2>/dev/null | grep -c 'assets/minecraft/textures/.*\.png$')
        [ "$n" -gt "$best" ] && jar=$j && best=$n
    done
    if [ -z "$jar" ]; then
        say "No Minecraft: Java Edition client (versions/<version>/<version>.jar) in the copy: nothing was taken"
        return 1
    fi
    v=${jar%/*}
    v=${v##*/}
    paths=$(awk '!/^#/ { while (match($0, /\{[^}]+\}/)) { print substr($0, RSTART + 1, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH) } }' "$TABLE" | sort -u)
    total=$(echo "$paths" | wc -l | tr -d ' ')
    rm -rf "$MC_STAGE" && mkdir -p "$MC_STAGE/new" || fail "Could not write to HOME: Luanti's own textures are back"
    # a member the jar lacks is just not there afterwards
    unzip -o -q "$jar" $(echo "$paths" | sed 's|^|assets/minecraft/textures/|; s|$|.png|') -d "$MC_STAGE" 2>/dev/null
    : > "$MC_STAGE/list"
    for p in $paths; do
        f=$MC_STAGE/assets/minecraft/textures/$p.png
        [ -f "$f" ] || continue
        mv "$f" "$MC_STAGE/new/mc_${p//\//_}.png" && echo "mc_${p//\//_}.png" >> "$MC_STAGE/list"
    done
    # "file" lines: the image under the Luanti name too, for what the game draws from code
    awk '!/^#/ && $3 ~ /file/ && match($2, /\{[^}]+\}/) { print $1, substr($2, RSTART + 1, RLENGTH - 2) }' "$TABLE" |
        while read -r to p; do
            [ -f "$MC_STAGE/new/mc_${p//\//_}.png" ] && cp "$MC_STAGE/new/mc_${p//\//_}.png" "$MC_STAGE/new/$to"
        done
    got=$(wc -l < "$MC_STAGE/list" | tr -d ' ')
    if [ "$got" -eq 0 ]; then
        rm -rf "$MC_STAGE"
        say "None of Luanti's textures is in Minecraft %s: nothing was taken" "$v"
        return 1
    fi
    if ! { rm -rf "$MC_DEST" && mkdir -p "${MC_DEST%/*}" "${MC_LIST%/*}" && cp -r "$MC_STAGE/new" "$MC_DEST" &&
            cp "$MC_STAGE/list" "$MC_LIST"; }; then
        rm -rf "$MC_DEST" "$MC_LIST"
        set_conf goodluck_mc_assets false
        fail "Could not write to HOME: Luanti's own textures are back"
    fi
    set_conf goodluck_mc_assets true
    say "%s of the %s textures Luanti can take are Minecraft %s's now" "$got" "$total" "$v"

    index=$(sed -n 's/.*"assets": *"\([^"]*\)".*/\1/p' "${jar%.jar}.json" 2>/dev/null | head -n 1)
    [ -n "$index" ] && [ -f "$src/assets/indexes/$index.json" ] ||
        index=$(ls -t "$src"/assets/indexes/*.json 2>/dev/null | head -n 1 | sed 's|.*/||; s|\.json$||')
    if [ -z "$index" ] || [ ! -f "$SOUNDS" ]; then
        say "The copy has no assets folder: Luanti keeps its own sounds"
        rm -rf "$MC_STAGE"
        return 0
    fi
    # the index, one object a line: "minecraft/sounds/dig/stone1.ogg":{"hash":"4ec8...","size":7434
    tr -d ' \n\r' < "$src/assets/indexes/$index.json" | tr '}' '\n' |
        awk -F'"' '$2 ~ /^minecraft\/sounds\// { print substr($2, 18), $6, substr($9, 2) }' > "$MC_STAGE/sounds.map"
    find "$GAME/mods" -name '*.ogg' | sed 's|.*/||' | sort > "$MC_STAGE/sounds.have"
    # for each line of sounds.txt: the game's file names of that sound, then name.<n>.ogg for what is left, each with
    # one of Minecraft's objects (xx/hash) in turn
    awk 'FNR == 1 { f++ }
        f == 1 { n = $0; sub(/\.ogg$/, "", n); sub(/\.[0-9]$/, "", n); have[n] = (n in have) ? have[n] " " $0 : $0; next }
        f == 2 { hash[$1] = $2; next }
        /^#/ || NF < 2 { next }
        {
            k = 0
            for (i = 2; i <= NF; i++) if (($i ".ogg") in hash) mc[++k] = hash[$i ".ogg"]
            if (!k) next
            m = split(have[$1], out, " ")
            for (n = 1; m < k && n <= 9; n++) {
                name = $1 "." n ".ogg"
                taken = 0
                for (i = 1; i <= m; i++) if (out[i] == name) taken = 1
                if (!taken) out[++m] = name
            }
            for (i = 1; i <= m; i++) { h = mc[(i - 1) % k + 1]; print substr(h, 1, 2) "/" h, out[i] }
        }' "$MC_STAGE/sounds.have" "$MC_STAGE/sounds.map" "$SOUNDS" > "$MC_STAGE/sounds.copy"
    sgot=0
    while read -r obj name; do
        cp "$src/assets/objects/$obj" "$MC_DEST/$name" 2>/dev/null && echo "$name" >> "$MC_LIST" && sgot=$((sgot + 1))
    done < "$MC_STAGE/sounds.copy"
    say "%s sounds came from Minecraft %s too" "$sgot" "$v"

    # the index's size tells a track already copied: 250 MB would take a while every time
    awk 'FNR == 1 { f++ }
        f == 1 { hash[$1] = $2; size[$1] = $3; next }
        /^#/ || NF < 2 { next }
        { for (i = 2; i <= NF; i++) { n = "music/" $i ".ogg"; if (n in hash) { h = hash[n]; m = $i; sub(/.*\//, "", m);
            print substr(h, 1, 2) "/" h, size[n], $1 "/" m ".ogg" } } }' "$MC_STAGE/sounds.map" "$MUSIC" > "$MC_STAGE/music.copy"
    total=$(wc -l < "$MC_STAGE/music.copy" | tr -d ' ')
    if [ "$total" -gt 0 ]; then
        say "Copying the music of Minecraft %s (%s tracks)..." "$v" "$total"
        mgot=0
        while read -r obj size name; do
            mkdir -p "$MC_MUSIC/${name%/*}"
            [ -f "$MC_MUSIC/$name" ] && [ "$(wc -c < "$MC_MUSIC/$name" | tr -d ' ')" = "$size" ] ||
                cp "$src/assets/objects/$obj" "$MC_MUSIC/$name" 2>/dev/null || continue
            mgot=$((mgot + 1))
        done < "$MC_STAGE/music.copy"
        say "%s music tracks are on the card" "$mgot"
    fi
    rm -rf "$MC_STAGE"
}

mkdir -p "${LOG%/*}"
printf '\033[2J\033[H\033[?25l\n'
say "Minecraft look for Luanti"
printf '\n'
if minecraft; then finish 0; fi
[ -d "$HOMEDIR/minecraft/versions" ] || [ -d "$HOMEDIR/.minecraft/versions" ] ||
    say "No copy of .minecraft in HOME: copy it there as minecraft or .minecraft"
finish 1
