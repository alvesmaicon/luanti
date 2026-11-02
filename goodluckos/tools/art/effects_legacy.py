#!/usr/bin/env python3
# The icons of the effects Mineclonia's Pixel Perfection lacks (Absorption, Resistance) and Absorption's golden hearts
# when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova Wostra (CC BY-SA 4.0,
# https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), the heart laid over the heart's
# container as the game's own hearts are, under goodluck_effects' names
#   python3 goodluckos/tools/art/effects_legacy.py <pixel perfection legacy dir> [out dir]
import os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/game/mods/goodluck_effects/textures"

os.makedirs(OUT, exist_ok=True)
for name in ["absorption", "resistance"]:
    shutil.copyfile(SRC + f"mob_effect/{name}.png", OUT + f"/goodluck_effects_{name}.png")
heart = Image.open(SRC + "gui/sprites/hud/heart/container.png").convert("RGBA")
heart.alpha_composite(Image.open(SRC + "gui/sprites/hud/heart/absorbing_full.png").convert("RGBA"))
heart.save(OUT + "/goodluck_effects_heart_absorbing.png", optimize=True)
print("3 textures in", os.path.relpath(OUT, ROOT))
