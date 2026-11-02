#!/usr/bin/env python3
# The illagers when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova Wostra (CC BY-SA 4.0,
# https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), which draws them in 26.x's layouts,
# copied under goodluck_illagers' names: the pillager, the crossbow and its pulls, the banner and the ominous banner's
# patterns, the ominous bottle, the omen effects' icons, the spawn eggs
#   python3 goodluckos/tools/art/illagers.py <pixel perfection legacy dir> [out dir]
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/game/mods/goodluck_illagers/textures"
FILES = {
    "entity/illager/pillager": "pillager",
    "item/crossbow_standby": "crossbow", "item/crossbow_pulling_0": "crossbow_pulling_0",
    "item/crossbow_pulling_1": "crossbow_pulling_1", "item/crossbow_pulling_2": "crossbow_pulling_2",
    "item/crossbow_arrow": "crossbow_arrow",
    "item/ominous_bottle": "ominous_bottle",
    "mob_effect/bad_omen": "bad_omen", "mob_effect/raid_omen": "raid_omen",
    "item/pillager_spawn_egg": "pillager_egg",
}
for pattern in ("base", "rhombus", "stripe_bottom", "stripe_center", "border", "stripe_middle", "half_horizontal",
                "circle"):
    FILES["entity/banner/" + pattern] = "banner_" + pattern

os.makedirs(OUT, exist_ok=True)
for path, name in FILES.items():
    shutil.copyfile(SRC + path + ".png", f"{OUT}/goodluck_illagers_{name}.png")
print(len(FILES), "textures in", os.path.relpath(OUT, ROOT))
