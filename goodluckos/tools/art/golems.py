#!/usr/bin/env python3
# The golems when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova Wostra (CC BY-SA 4.0,
# https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), which draws them in 26.x's layouts,
# copied under goodluck_golems' names: the iron golem and its three cracks, the snow golem, their spawn eggs
#   python3 goodluckos/tools/art/golems.py <pixel perfection legacy dir> [out dir]
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/game/mods/goodluck_golems/textures"
FILES = {
    "entity/iron_golem/iron_golem": "iron_golem",
    "entity/iron_golem/iron_golem_crackiness_low": "iron_golem_crackiness_low",
    "entity/iron_golem/iron_golem_crackiness_medium": "iron_golem_crackiness_medium",
    "entity/iron_golem/iron_golem_crackiness_high": "iron_golem_crackiness_high",
    "entity/snow_golem/snow_golem": "snow_golem",
    "item/iron_golem_spawn_egg": "iron_golem_egg", "item/snow_golem_spawn_egg": "snow_golem_egg",
}

os.makedirs(OUT, exist_ok=True)
for path, name in FILES.items():
    shutil.copyfile(SRC + path + ".png", f"{OUT}/goodluck_golems_{name}.png")
print(len(FILES), "textures in", os.path.relpath(OUT, ROOT))
