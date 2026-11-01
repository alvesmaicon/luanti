#!/bin/sh
# run.sh: Luanti with its main menu, in the launcher's language. The App Installer's app runs it in its folder;
# worlds and settings stay in ~/.minetest, whose minetest.conf starts as goodluck/luanti.conf.
app=$(pwd)
dir=$HOME/.minetest
conf=$dir/minetest.conf
defaults=$app/goodluck/luanti.conf
mkdir -p "$dir"
[ -f "$conf" ] || cp "$defaults" "$conf"

# defaults added in a later version reach an existing minetest.conf too; set ones stay as they are
grep -E '^[a-z0-9_.:]+ *=' "$defaults" | while IFS= read -r line; do
    grep -q "^${line%%[ =]*} *=" "$conf" || echo "$line" >> "$conf"
done

set_conf() {
    if grep -q "^$1 *=" "$conf"; then sed -i "s|^$1 *=.*|$1 = $2|" "$conf"; else echo "$1 = $2" >> "$conf"; fi
}

# no menu sets these: they follow the app's defaults even when already in the conf
for key in loading_terrain_radius loading_terrain_timeout mob_active_limit; do
    value=$(sed -n "s/^$key *= *//p" "$defaults" | tail -n 1)
    [ -n "$value" ] && set_conf "$key" "$value"
done

# the same setting as gl-tr
code=$(sed -n 's/^language=//p' "$HOME/.config/puppy/settings" 2>/dev/null | tail -n 1)
if [ "$code" = pt-BR ]; then
    set_conf language pt_BR
    export LANG=pt_BR.UTF-8
else
    set_conf language en
fi

# test runs: ~/.minetest/perf.env exports its variables (LIMA_DEBUG...) and starts the logger
if [ -f "$dir/perf.env" ]; then
    set -a; . "$dir/perf.env"; set +a
    sh "$app/goodluck/luanti-perflog.sh" $$ "${PERFLOG_INTERVAL:-5}" &
fi

# by position as on an Xbox pad: B (bottom) is SDL's south button (jump, click in menus), A (right) east (sneak, back),
# Y (left) west (half a stack), X (top) north (shift-click)
[ -n "$SDL_GAMECONTROLLERCONFIG" ] && export SDL_GAMECONTROLLERCONFIG=$(echo "$SDL_GAMECONTROLLERCONFIG" |
    sed 's/,a:b1,/,a:B0,/; s/,b:b0,/,b:b1,/; s/,a:B0,/,a:b0,/; s/,x:b2,/,x:B3,/; s/,y:b3,/,y:b2,/; s/,x:B3,/,x:b3,/')

# the libraries a goodluckOS without Luanti lacks come with the app
export LD_LIBRARY_PATH=$app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec "$app/bin/luanti"
