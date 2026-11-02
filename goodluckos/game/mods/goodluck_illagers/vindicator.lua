-- The vindicator (Vindicator): 24 of health and an iron axe for 13 (its 5 and the axe's 8, scaled by the difficulty as
-- mobs_redo does), after players, villagers and iron golems up to 12 away. Its arms stay crossed until it goes after
-- someone, and then the axe goes up. Named Johnny with a name tag it goes after every mob but the raiders, as
-- VindicatorJohnnyAttackGoal has it. Drops an emerald now and then, and its axe one time in 12
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local VINDICATOR = N .. "vindicator"
local SKIN, AXE = "goodluck_illagers_vindicator.png", "default_tool_steelaxe.png"
goodluck_illagers.raiders[VINDICATOR] = true

-- once a second: a Johnny goes after any mob but the raiders, and back to its own targets when renamed
local function johnny(self, dtime)
	self._johnny_look = (self._johnny_look or 0) - dtime
	if self._johnny_look > 0 then
		return
	end
	self._johnny_look = 1
	local on = self._nametag == "Johnny"
	if on == (self._johnny or false) then
		return
	end
	self._johnny = on or nil
	-- false, not nil, for no list: nil lets the registered one through again
	if on then
		local ignore = {}
		for name in pairs(goodluck_illagers.raiders) do
			ignore[#ignore + 1] = name
		end
		self.specific_attack, self.attack_ignore = false, ignore
		self.attack_animals, self.attack_monsters, self.attack_npcs = true, true, true
	else
		self.specific_attack, self.attack_ignore = nil, nil
		self.attack_animals, self.attack_monsters, self.attack_npcs = nil, nil, nil
	end
end

mobs:register_mob(VINDICATOR, {
	type = "monster",
	description = S("Vindicator"),
	passive = false,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 2,
	damage = 13,
	hp_min = 24, hp_max = 24,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.95, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_vindicator.glb",
	textures = {{SKIN, AXE}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {random = "goodluck_illagers_vindicator", damage = "goodluck_illagers_vindicator_hurt",
		death = "goodluck_illagers_vindicator_death", distance = 16},
	walk_velocity = 1, run_velocity = 3,
	view_range = 12,
	jump = true,
	floats = 1,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = {{name = "goodluck_emerald:emerald", chance = 1, min = 0, max = 1},
		{name = "default:axe_steel", chance = 12, min = 1, max = 1}},
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 1,
		walk_start = 1, walk_end = 2,
		run_start = 3, run_end = 3.5,
		punch_start = 6, punch_end = 6.5,
		die_start = 4, die_end = 5, die_loop = false,
	},
	do_custom = johnny,
})

mobs:register_egg(VINDICATOR, S("Vindicator"), "goodluck_illagers_vindicator_egg.png", 0)
