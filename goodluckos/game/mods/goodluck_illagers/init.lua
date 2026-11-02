-- Minecraft's illagers: the pillager (pillager.lua) and its crossbow, which the player can make and shoot too
-- (crossbow.lua), the vindicator (vindicator.lua), the evoker with its fangs and vexes (evoker.lua), the ravager
-- (ravager.lua) and the evoker's totem of undying (totem.lua); patrols of pillagers led by a captain wearing the
-- ominous banner (patrols.lua) and their outposts (outpost.lua); the ominous bottle a captain drops, which gives Bad
-- Omen (omen.lua), and the raid Bad Omen brings on a village (raid.lua). Who they go after is goodluck_golems'
-- fights.lua, with the rest of the monsters
local S = core.get_translator("goodluck_illagers")
local M = core.get_modpath("goodluck_illagers")
local DIFFICULTY = {peaceful = 0, easy = 1, normal = 2, hard = 3}
goodluck_illagers = {S = S,
	difficulty = DIFFICULTY[Settings(core.get_worldpath() .. "/world.mt"):get("difficulty") or "normal"] or 2}
if not core.settings:get_bool("mobs_spawn", true) or core.settings:get_bool("only_peaceful_mobs", false) then
	goodluck_illagers.difficulty = 0
end

dofile(M .. "/omen.lua")
dofile(M .. "/crossbow.lua")
dofile(M .. "/pillager.lua")
dofile(M .. "/vindicator.lua")
dofile(M .. "/evoker.lua")
dofile(M .. "/ravager.lua")
dofile(M .. "/totem.lua")
dofile(M .. "/patrols.lua")
dofile(M .. "/outpost.lua")
dofile(M .. "/raid.lua")
