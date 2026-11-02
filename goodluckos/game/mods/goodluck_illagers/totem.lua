-- The totem of undying (the evoker's): held in the hand, it takes the blow that would kill, as Minecraft's
-- death_protection does: health back to 1, the effects gone, Regeneration II for 45 s, Absorption II for 5 s and Fire
-- Resistance for 40 s, the totem used up, with its burst of green and yellow and the totem itself coming at the screen
local S = goodluck_illagers.S
local TOTEM = "goodluck_illagers:totem_of_undying"
local E = goodluck_effects

core.register_craftitem(TOTEM, {
	description = S("Totem of Undying"),
	inventory_image = "goodluck_illagers_totem_of_undying.png",
	stack_max = 1,
})

local function show(player)
	local pos = player:get_pos()
	for _, color in ipairs({"#4ec13c", "#e5d32a"}) do
		core.add_particlespawner({amount = 40, time = 0.6, attached = player,
			pos = {min = vector.new(-0.5, 0.2, -0.5), max = vector.new(0.5, 1.8, 0.5)},
			vel = {min = vector.new(-3, 1, -3), max = vector.new(3, 5, 3)}, acc = vector.new(0, -4, 0),
			exptime = {min = 0.8, max = 1.6}, size = {min = 1, max = 2}, glow = 10,
			texture = "goodluck_effects_particle.png^[multiply:" .. color})
	end
	core.sound_play("goodluck_illagers_totem", {pos = pos, gain = 1, max_hear_distance = 24}, true)
	local id = player:hud_add({type = "image", position = {x = 0.5, y = 0.5}, alignment = {x = 0, y = 0},
		scale = {x = 4, y = 4}, text = "goodluck_illagers_totem_of_undying.png", z_index = 100})
	for i = 1, 8 do
		core.after(i * 0.12, function()
			if player:is_valid() then
				player:hud_change(id, "scale", {x = 4 + i * 1.5, y = 4 + i * 1.5})
			end
		end)
	end
	core.after(1.2, function()
		if player:is_valid() then
			player:hud_remove(id)
		end
	end)
end

-- the last modifier of a blow, so that armor and the shield have had their say
core.register_on_mods_loaded(function()
	core.register_on_player_hpchange(function(player, change, reason)
		local hp = player:get_hp()
		if change >= 0 or hp + change > 0 or reason.type == "respawn" or
				player:get_wielded_item():get_name() ~= TOTEM then
			return change
		end
		local stack = player:get_wielded_item()
		stack:take_item()
		player:set_wielded_item(stack)
		core.after(0, function()
			if not player:is_valid() then
				return
			end
			E.clear(player)
			E.apply(player, "regeneration", 45, 2)
			E.apply(player, "absorption", 5, 2)
			E.apply(player, "fire_resistance", 40, 1)
			show(player)
		end)
		return 1 - hp
	end, true)
end)
