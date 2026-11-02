-- The ominous banner a captain wears and drops, and the ominous bottle a pillager captain drops (I to V, its loot
-- table's amplifier 0 to 4): drunk, it gives Bad Omen at its level for 100 minutes (OminousBottleAmplifier), with no
-- swirls, as Minecraft gives it
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local E = goodluck_effects
local OMEN = 6000
local ROMAN = {"I", "II", "III", "IV", "V"}
-- dye colours (DyeColor's texture diffuse colours) and the banner's patterns, as Raid.getOminousBannerInstance has
-- them: white, a cyan rhombus, a light grey bottom stripe, a grey pale, a light grey border, a black fess, the
-- light grey upper half, a light grey roundel and a black border
local CYAN, LIGHT_GRAY, GRAY, BLACK = "#169c9c", "#9d9d97", "#474f52", "#1d1d21"
local PATTERNS = {{"rhombus", CYAN}, {"stripe_bottom", LIGHT_GRAY}, {"stripe_center", GRAY}, {"border", LIGHT_GRAY},
	{"stripe_middle", BLACK}, {"half_horizontal", LIGHT_GRAY}, {"circle", LIGHT_GRAY}, {"border", BLACK}}

local banner = {"goodluck_illagers_banner_base.png"}
for _, p in ipairs(PATTERNS) do
	banner[#banner + 1] = ("(goodluck_illagers_banner_%s.png^[multiply:%s)"):format(p[1], p[2])
end
goodluck_illagers.BANNER = table.concat(banner, "^")

-- in the inventory: the flag's face (20x40 at 1,1 of the texture) in the middle of a square
local face = goodluck_illagers.BANNER:gsub("%^", "\\^"):gsub(":", "\\:")
core.register_craftitem(N .. "ominous_banner", {
	description = core.colorize("#ffaa00", S("Ominous Banner")),
	short_description = S("Ominous Banner"),
	inventory_image = "[combine:42x42:10,0=" .. face,
	stack_max = 16,
})

E.register("bad_omen", {description = S("Bad Omen"), color = "#0b6138", icon = "goodluck_illagers_bad_omen.png",
	swirl = false})

for level = 1, 5 do
	core.register_craftitem(N .. "ominous_bottle_" .. level, {
		description = S("Ominous Bottle") .. "\n" .. core.colorize("#5555ff",
			S("Bad Omen") .. " " .. ROMAN[level] .. " (100:00)"),
		short_description = S("Ominous Bottle"),
		inventory_image = "goodluck_illagers_ominous_bottle.png",
		on_secondary_use = function(itemstack, user)
			return goodluck_illagers.drink(itemstack, user, level)
		end,
		on_place = function(itemstack, user, pointed)
			local node = pointed.type == "node" and core.get_node(pointed.under)
			local def = node and core.registered_nodes[node.name]
			if def and def.on_rightclick and not user:get_player_control().sneak then
				return def.on_rightclick(pointed.under, node, user, itemstack, pointed) or itemstack
			end
			return goodluck_illagers.drink(itemstack, user, level)
		end,
	})
end

function goodluck_illagers.drink(itemstack, user, level)
	if not user or not user:is_player() then
		return
	end
	E.apply(user, "bad_omen", OMEN, level)
	core.sound_play("goodluck_potions_drink", {pos = user:get_pos(), gain = 0.5, max_hear_distance = 16}, true)
	core.sound_play("goodluck_illagers_bad_omen", {to_player = user:get_player_name(), gain = 0.8}, true)
	if not core.is_creative_enabled(user:get_player_name()) then
		itemstack:take_item()
	end
	return itemstack
end

-- the bottle a captain drops, at a level of 1 to 5
function goodluck_illagers.bottle()
	return N .. "ominous_bottle_" .. math.random(1, 5)
end
