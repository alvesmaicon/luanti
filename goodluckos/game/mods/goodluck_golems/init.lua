-- Minecraft's golems (26.x) in its models (goodluck_models' meshes, Pixel Perfection Legacy's skins), built as in
-- Minecraft: a carved pumpkin or a jack o'lantern put last on two snow blocks makes a snow golem, on a T of four iron
-- blocks an iron golem. Every village has an iron golem and its villagers call one when they panic; who goes after
-- whom (fights.lua). Snowballs, and snow giving them (snow.lua)
goodluck_golems = {}
local S = core.get_translator("goodluck_golems")
local G = "goodluck_golems:"
local IRON, SNOW = G .. "iron_golem", G .. "snow_golem"
local IRON_SKIN = "goodluck_golems_iron_golem.png"
local SNOW_SKIN = "goodluck_golems_snow_golem.png"
-- the carved pumpkin on the snow golem's head, its faces where the model's 16 box takes them
local PUMPKIN = "[combine:64x64:16,0=goodluck_food_pumpkin_top.png:32,0=goodluck_food_pumpkin_top.png" ..
	":0,16=goodluck_food_pumpkin_side.png:16,16=goodluck_food_carved_pumpkin.png" ..
	":32,16=goodluck_food_pumpkin_side.png:48,16=goodluck_food_pumpkin_side.png"
local SHEARS = "mobs:shears"
local mushroom = "goodluck_monsters:mushroom"
local nether = core.get_modpath("goodluck_nether") ~= nil

local function creative(player)
	return player:is_player() and core.is_creative_enabled(player:get_player_name())
end

-- one that is still there and alive (mobs keep their health in Lua)
function goodluck_golems.alive(obj)
	if not obj or not obj:is_valid() then
		return false
	end
	local ent = obj:get_luaentity()
	if ent then
		return (ent.health or 0) > 0
	end
	return obj:get_hp() > 0
end
local alive = goodluck_golems.alive

-- The iron golem: 100 of health, takes no knockback and no fall, hits once a second for 7 to 21 (15 / 2 and up to
-- 14 more) and throws what it hits back and up. As it loses health its cracks show (under 3/4, 1/2 and 1/4), and an
-- iron ingot (L1) mends 25. One a player built never turns on a player; another one does when hit
local TOSS = 5.5
local CRACKS = {{0.25, "high"}, {0.5, "medium"}, {0.75, "low"}}

local function cracks(self)
	local f = self.health / 100
	local c
	for _, k in ipairs(CRACKS) do
		if f < k[1] then
			c = k[2]
			break
		end
	end
	if c ~= self._cracks then
		self._cracks = c
		self.base_texture = {IRON_SKIN .. (c and "^goodluck_golems_iron_golem_crackiness_" .. c .. ".png" or "")}
		self.textures = self.base_texture
		self.object:set_properties({textures = self.base_texture})
	end
end

local function smash(self)
	local t = self.attack
	if not alive(t) then
		return false
	end
	self:set_animation("punch", true)
	self:mob_sound(self.sounds.attack)
	t:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 7 + math.random(0, 14),
		knockback = 3}}, nil)
	local ent = t:is_valid() and t:get_luaentity()
	if t:is_valid() and t:is_player() then
		t:add_velocity({x = 0, y = TOSS, z = 0})
	elseif ent and not ent.fly then
		local v = t:get_velocity()
		t:set_velocity({x = v.x, y = TOSS, z = v.z})
	end
	return false
end

-- a village's golem goes back to it when it strays 32 away with no one to fight (Minecraft's MoveBackToVillageGoal)
local function homeward(self, dtime)
	self._homeward = (self._homeward or 0) - dtime
	if self._homeward > 0 or not self._home or self.state == "attack" then
		return
	end
	self._homeward = 2
	local pos = self.object:get_pos()
	if pos and vector.distance(pos, self._home) > 32 then
		self.state = "walk"
		self:yaw_to_pos(self._home)
		self:set_velocity(self.walk_velocity)
		self:set_animation("walk")
	end
end

mobs:register_mob(IRON, {
	type = "npc",
	description = S("Iron Golem"),
	passive = false,
	attack_type = "dogfight",
	attack_monsters = true, attack_animals = false, attack_npcs = false, attack_players = false,
	attack_ignore = {mushroom},
	reach = 2.5,
	damage = 15,
	hp_min = 100, hp_max = 100,
	armor = 100,
	knock_back = false,
	collisionbox = {-0.7, 0, -0.7, 0.7, 2.7, 0.7},
	visual = "mesh",
	mesh = "goodluck_models_iron_golem.glb",
	textures = {{IRON_SKIN}},
	makes_footstep_sound = true,
	sounds = {damage = "goodluck_golems_iron_golem_hurt", death = "goodluck_golems_iron_golem_death",
		attack = "goodluck_golems_iron_golem_attack", distance = 16},
	walk_velocity = 0.65, run_velocity = 2.2,
	view_range = 16,
	jump = true,
	fall_damage = false,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = {{name = "default:steel_ingot", chance = 1, min = 3, max = 5},
		{name = "flowers:rose", chance = 1, min = 0, max = 2}},
	animation = {speed_normal = 1, speed_run = 1, stand_start = 0, stand_end = 1, walk_start = 1, walk_end = 3,
		run_start = 3, run_end = 4.5, punch_start = 7, punch_end = 7.5, punch_loop = false,
		die_start = 5, die_end = 6, die_loop = false},
	custom_attack = smash,
	after_activate = function(self)
		-- golems stay where they are, as tamed mobs do
		self.tamed = true
		self._cracks = false
		cracks(self)
	end,
	do_custom = function(self, dtime)
		cracks(self)
		homeward(self, dtime)
	end,
	on_rightclick = function(self, clicker)
		local stack = clicker:get_wielded_item()
		if stack:get_name() ~= "default:steel_ingot" or self.health >= 100 then
			return
		end
		self.health = math.min(100, self.health + 25)
		self.object:set_hp(self.health)
		cracks(self)
		core.sound_play("goodluck_golems_iron_golem_repair", {object = self.object, max_hear_distance = 16,
			pitch = 1 + (math.random() - math.random()) * 0.2}, true)
		if not creative(clicker) then
			stack:take_item()
			clicker:set_wielded_item(stack)
		end
	end,
})

-- The snow golem: 4 of health, after every monster it sees within 16; it comes up to 10 away and throws a snowball a
-- second (as Minecraft's, 1.6 a tick, aimed 0.2 a node of the way above its target's eyes, 12 of spread), which
-- hurts only blazes. Hot places (deserts, savannas, the Nether) and water melt it, 2 a second, and where it is cold
-- enough it leaves snow behind it unless mobs may not change blocks. Shears (L1) take its pumpkin off and drop it
local BURN = {desert = true, sandstone_desert = true, savanna = true}
local TRAIL = {icesheet = true, tundra = true, taiga = true, snowy_grassland = true, coniferous_forest = true,
	deciduous_forest = true, cold_desert = true}
local griefing = core.settings:get_bool("mobs_griefing") ~= false

local function climate(pos)
	if nether and goodluck_nether.inside(pos) then
		return BURN
	end
	local data = core.get_biome_data(pos)
	local name = data and core.get_biome_name(data.biome) or ""
	name = name:gsub("_ocean$", ""):gsub("_shore$", ""):gsub("_dunes$", ""):gsub("_under$", "")
	return BURN[name] and BURN or TRAIL[name] and TRAIL
end

local function weather(self, pos)
	local feet = vector.round(pos)
	local kind = climate(feet)
	if kind == BURN then
		self.health = self.health - 0.5
		return self:check_for_death({type = "environment", pos = pos})
	end
	if kind == TRAIL and griefing and core.get_node(feet).name == "air" then
		local below = core.registered_nodes[core.get_node(vector.offset(feet, 0, -1, 0)).name]
		if below and below.walkable and below.drawtype == "normal" then
			core.set_node(feet, {name = "default:snow"})
		end
	end
end

local function aim(target)
	local p = target:get_pos()
	local h = target:is_player() and target:get_properties().eye_height or
		target:get_properties().collisionbox[5] * 0.85
	return vector.offset(p, 0, h - 1.1, 0)
end

local function snow_step(self, dtime)
	self._weather = (self._weather or 0) + dtime
	if self._weather >= 0.25 then
		self._weather = 0
		if weather(self, self.object:get_pos()) then
			return false
		end
	end
	if self.state ~= "attack" then
		return
	end
	-- only ever a monster: hit by anything else, it doesn't hit back (mobs_redo would)
	local t = self.attack
	local pos = self.object:get_pos()
	local ent = t and t:get_luaentity()
	if not alive(t) or not (ent and ent.type == "monster") or vector.distance(pos, t:get_pos()) > self.view_range then
		self:stop_attack()
		return false
	end
	local tp = t:get_pos()
	self:yaw_to_pos(tp)
	if vector.distance(pos, tp) > 10 then
		self:set_velocity(self.run_velocity)
		self:set_animation("walk")
		return false
	end
	self:set_velocity(0)
	self:set_animation("stand")
	self._throw = (self._throw or 0) - dtime
	local eye = vector.offset(pos, 0, 1.6, 0)
	if self._throw <= 0 and self:line_of_sight(eye, aim(t)) then
		self._throw = 1
		local to = aim(t)
		local d = vector.subtract(to, eye)
		d.y = d.y + math.hypot(d.x, d.z) * 0.2
		goodluck_golems.throw(eye, d, 1.6, 12, self.object)
		self:mob_sound({name = "goodluck_golems_throw", gain = 1, pitch = 1 / (math.random() * 0.4 + 0.8)})
	end
	return false
end

mobs:register_mob(SNOW, {
	type = "npc",
	description = S("Snow Golem"),
	passive = false,
	attack_type = "shoot",
	attack_monsters = true, attack_animals = false, attack_npcs = false, attack_players = false,
	hp_min = 4, hp_max = 4,
	armor = 100,
	collisionbox = {-0.35, 0, -0.35, 0.35, 1.9, 0.35},
	visual = "mesh",
	mesh = "goodluck_models_snow_golem.glb",
	textures = {{SNOW_SKIN, PUMPKIN}},
	use_texture_alpha = true,
	sounds = {damage = "goodluck_golems_snow_golem_hurt", death = "goodluck_golems_snow_golem_death", distance = 16},
	walk_velocity = 0.9, run_velocity = 2.2,
	view_range = 16,
	jump = true,
	water_damage = 2, lava_damage = 4, light_damage = 0,
	drops = {{name = G .. "snowball", chance = 1, min = 0, max = 15}},
	animation = {speed_normal = 1, speed_run = 1, stand_start = 0, stand_end = 1, walk_start = 0, walk_end = 1,
		run_start = 0, run_end = 1, shoot_start = 0, shoot_end = 1, die_start = 4, die_end = 5, die_loop = false},
	after_activate = function(self)
		self.tamed = true
		if self._sheared then
			self.base_texture = {SNOW_SKIN, "blank.png"}
			self.textures = self.base_texture
			self.object:set_properties({textures = self.base_texture})
		end
	end,
	do_custom = snow_step,
	on_rightclick = function(self, clicker)
		local stack = clicker:get_wielded_item()
		if stack:get_name() ~= SHEARS or self._sheared then
			return
		end
		self._sheared = true
		self.base_texture = {SNOW_SKIN, "blank.png"}
		self.textures = self.base_texture
		self.object:set_properties({textures = self.base_texture})
		core.sound_play("mobs_shears", {object = self.object, max_hear_distance = 16}, true)
		core.add_item(vector.offset(self.object:get_pos(), 0, 1.7, 0), "goodluck_food:carved_pumpkin")
		if not creative(clicker) then
			stack:add_wear(65535 / 238)
			clicker:set_wielded_item(stack)
		end
	end,
})

for name, egg in pairs({[IRON] = "goodluck_golems_iron_golem_egg.png", [SNOW] = "goodluck_golems_snow_golem_egg.png"}) do
	mobs:register_egg(name, core.registered_entities[name].description, egg, 0)
end

-- a golem standing on pos (the block under its feet one lower); data: what it starts with (fights.lua: its village)
function goodluck_golems.spawn(name, pos, data)
	local obj = core.add_entity(vector.offset(pos, 0, -0.45, 0), name, data and core.serialize(data))
	return obj and obj:get_luaentity()
end

-- Building one: the pumpkin put last, the blocks under it in the shape (the iron golem's arms along x or z, with
-- air beside its head and its legs, as Minecraft wants), then they turn into the golem with a puff of their bits
local function puff(positions, node)
	for _, p in ipairs(positions) do
		core.add_particlespawner({amount = 12, time = 0.1, pos = {min = vector.offset(p, -0.4, -0.4, -0.4),
			max = vector.offset(p, 0.4, 0.4, 0.4)}, vel = {min = vector.new(-1, 0, -1), max = vector.new(1, 2, 1)},
			acc = vector.new(0, -9.81, 0), exptime = {min = 0.4, max = 0.8}, size = {min = 1, max = 2},
			node = {name = node}})
	end
end

local function is(pos, name)
	return core.get_node(pos).name == name
end

local function build(pos, placer)
	local below, legs = vector.offset(pos, 0, -1, 0), vector.offset(pos, 0, -2, 0)
	local owner = placer and placer:is_player() and placer:get_player_name() or nil
	local data = owner and {owner = owner, _built = true} or nil
	if is(below, "default:snowblock") and is(legs, "default:snowblock") then
		local parts = {pos, below, legs}
		puff({below, legs}, "default:snowblock")
		for _, p in ipairs(parts) do
			core.remove_node(p)
		end
		goodluck_golems.spawn(SNOW, legs, data)
		return true
	end
	if not (is(below, "default:steelblock") and is(legs, "default:steelblock")) then
		return
	end
	for _, axis in ipairs({vector.new(1, 0, 0), vector.new(0, 0, 1)}) do
		local arms = {vector.add(below, axis), vector.subtract(below, axis)}
		if is(arms[1], "default:steelblock") and is(arms[2], "default:steelblock") and
				is(vector.add(pos, axis), "air") and is(vector.subtract(pos, axis), "air") and
				is(vector.add(legs, axis), "air") and is(vector.subtract(legs, axis), "air") then
			local blocks = {below, legs, arms[1], arms[2]}
			puff(blocks, "default:steelblock")
			core.remove_node(pos)
			for _, p in ipairs(blocks) do
				core.remove_node(p)
			end
			goodluck_golems.spawn(IRON, legs, data)
			return true
		end
	end
end

for _, name in ipairs({"goodluck_food:carved_pumpkin", "goodluck_food:jack_o_lantern"}) do
	local after_place = core.registered_nodes[name].after_place_node
	core.override_item(name, {after_place_node = function(pos, placer, itemstack, pointed_thing)
		if build(pos, placer) then
			return false
		end
		if after_place then
			return after_place(pos, placer, itemstack, pointed_thing)
		end
	end})
end

local modpath = core.get_modpath("goodluck_golems")
dofile(modpath .. "/snow.lua")
dofile(modpath .. "/fights.lua")
