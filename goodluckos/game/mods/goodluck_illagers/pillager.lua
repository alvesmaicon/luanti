-- The pillager (Pillager, RangedCrossbowAttackGoal): 24 of health, after players, villagers and iron golems
-- (goodluck_golems' fights.lua) up to 32 away. It walks up to 8 away and, once it has seen its target a quarter of
-- a second, stands and loads its crossbow (1.25 s), waits 1 to 2 s and shoots: 1.6 a tick aimed at a third of the
-- target's height, a fifth of the distance above, spread by 14 less 4 a difficulty level, for 3, 4 or 5 by
-- difficulty. Its arrows go through raiders. Drops 0-2 arrows, now and then its crossbow. A captain (a patrol's
-- leader, or 6 % of those an outpost brings) wears the ominous banner and drops it with an ominous bottle
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local PILLAGER, BOLT, BANNER = N .. "pillager", N .. "arrow", N .. "worn_banner"
local SKIN = "goodluck_illagers_pillager.png"
local STANDBY, LOADED = "goodluck_illagers_crossbow.png", "goodluck_illagers_crossbow_arrow.png"
local PULLS = {"goodluck_illagers_crossbow_pulling_0.png", "goodluck_illagers_crossbow_pulling_1.png",
	"goodluck_illagers_crossbow_pulling_2.png"}
local RANGE, CHARGE, SEEN, SPEED = 8, 1.25, 0.25, 32
local D = goodluck_illagers.difficulty
local DAMAGE = ({3, 4, 5})[math.max(1, D)]
local SPREAD = 0.0172275 * (14 - 4 * D)
local bows = core.get_modpath("x_bows") ~= nil
goodluck_illagers.raiders = {[PILLAGER] = true}

local function alive(obj)
	if not obj or not obj:is_valid() then
		return false
	end
	local ent = obj:get_luaentity()
	return ent and (ent.health or 0) > 0 or not ent and obj:get_hp() > 0
end
goodluck_illagers.alive = alive

local function aim(obj)
	local box = obj:get_properties().collisionbox
	return vector.offset(obj:get_pos(), 0, box[2] + (box[5] - box[2]) / 3, 0)
end

local function crossbow(self, tex)
	if self._crossbow ~= tex then
		self._crossbow = tex
		self.base_texture = {SKIN, tex}
		self.textures = self.base_texture
		self.object:set_properties({textures = self.base_texture})
	end
end

mobs:register_arrow(BOLT, {
	visual = "mesh",
	mesh = "goodluck_models_arrow.glb",
	textures = {"goodluck_models_arrow.png"},
	visual_size = {x = 0.9, y = 0.9},
	velocity = SPEED,
	lifetime = 3,
	do_custom = function(self)
		local v = self.object:get_velocity()
		if v and (v.x ~= 0 or v.z ~= 0) then
			self.object:set_rotation({x = math.atan2(v.y, math.hypot(v.x, v.z)), y = core.dir_to_yaw(v), z = 0})
		end
	end,
	hit_player = function(self, player)
		local by = alive(self._shooter) and self._shooter or self.object
		player:punch(by, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = DAMAGE}}, nil)
	end,
	hit_mob = function(self, mob)
		local ent = mob:get_luaentity()
		if ent and goodluck_illagers.raiders[ent.name] then
			return
		end
		local by = alive(self._shooter) and self._shooter or self.object
		mob:punch(by, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = DAMAGE}}, nil)
	end,
	hit_node = function() end,
})

local function triangle()
	return (math.random() - math.random()) * SPREAD
end

local function fire(self, target)
	local from = vector.offset(self.object:get_pos(), 0, 1.5, 0)
	local d = vector.subtract(aim(target), from)
	d.y = d.y + math.hypot(d.x, d.z) * 0.2
	d = vector.normalize(d)
	d = vector.normalize(vector.offset(d, triangle(), triangle(), triangle()))
	local obj = core.add_entity(vector.add(from, vector.multiply(d, 0.8)), BOLT)
	if obj then
		obj:set_velocity(vector.multiply(d, SPEED))
		obj:set_acceleration({x = 0, y = -20, z = 0})
		obj:get_luaentity()._shooter = self.object
	end
	self:mob_sound({name = "goodluck_illagers_crossbow_shoot", gain = 0.5})
end

-- the crossbow's state: nil (empty), "charging" (_load seconds in) or "loaded" (_wait seconds to the shot)
local function attack(self, dtime)
	local t = self.attack
	if not alive(t) then
		self:stop_attack()
		self._load = nil
		crossbow(self, self._loaded and LOADED or STANDBY)
		return false
	end
	local pos = self.object:get_pos()
	local sees = self:line_of_sight(vector.offset(pos, 0, 1.5, 0), aim(t))
	self._seen = sees and (self._seen or 0) + dtime or 0
	if self._load then
		self._load = self._load + dtime
		local f = self._load / CHARGE
		crossbow(self, PULLS[f < 0.58 and 1 or f < 1 and 2 or 3])
		if f >= 1 then
			self._load, self._loaded, self._wait = nil, true, (20 + math.random(0, 19)) / 20
			crossbow(self, LOADED)
			self:mob_sound({name = "goodluck_illagers_crossbow_loading_end", gain = 0.4})
		end
	end
	if not sees or vector.distance(pos, t:get_pos()) > RANGE then
		-- too far or out of sight: mobs_redo walks it there (and its punch is custom_attack's: none)
		return
	end
	self:set_velocity(0)
	self:yaw_to_pos(t:get_pos())
	if self._loaded then
		self._wait = self._wait - dtime
		if self._wait <= 0 then
			self._loaded = nil
			crossbow(self, STANDBY)
			fire(self, t)
		end
		self:set_animation("stand")
	elseif self._load then
		self:set_animation("charge")
	elseif self._seen >= SEEN then
		self._load = 0
		self:set_animation("charge", true)
		self:mob_sound({name = "goodluck_illagers_crossbow_loading_start", gain = 0.4})
	else
		self:set_animation("stand")
	end
	return false
end

local function step(self, dtime)
	if self.state == "attack" then
		return attack(self, dtime)
	end
	if self._load then
		self._load = nil
		crossbow(self, STANDBY)
	end
	return goodluck_illagers.patrol(self, dtime)
end

-- the captain's banner, worn as Minecraft draws a banner on a head: it goes with its wearer
core.register_entity(BANNER, {
	initial_properties = {
		visual = "mesh",
		mesh = "goodluck_models_banner.glb",
		textures = {goodluck_illagers.BANNER},
		visual_size = {x = 0.625, y = 0.625, z = 0.625},
		physical = false,
		pointable = false,
		static_save = false,
	},
	on_activate = function(self)
		self.object:set_animation({x = 0, y = 5}, 1, 0, true)
	end,
	on_step = function(self)
		local parent = self.object:get_attach()
		local ent = parent and parent:get_luaentity()
		if not ent or ent.state == "die" or (ent.health or 0) <= 0 then
			self.object:remove()
		end
	end,
})

function goodluck_illagers.wear_banner(self)
	if self._captain and not (self._banner and self._banner:is_valid()) then
		local obj = core.add_entity(self.object:get_pos(), BANNER)
		if obj then
			obj:set_attach(self.object, "head", {x = 0, y = 7, z = 3}, {x = 0, y = 180, z = 0})
			self._banner = obj
		end
	end
end

mobs:register_mob(PILLAGER, {
	type = "monster",
	description = S("Pillager"),
	passive = false,
	attack_type = "dogfight",
	custom_attack = function() return false end,
	pathfinding = 1,
	reach = 2,
	damage = 0,
	hp_min = 24, hp_max = 24,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.95, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_pillager.glb",
	textures = {{SKIN, STANDBY}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {random = "goodluck_illagers_pillager", damage = "goodluck_illagers_pillager_hurt",
		death = "goodluck_illagers_pillager_death", distance = 16},
	walk_velocity = 1, run_velocity = 3,
	view_range = 32,
	jump = true,
	floats = 1,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = bows and {{name = "x_bows:arrow_wood", chance = 1, min = 0, max = 2},
		{name = N .. "crossbow", chance = 12, min = 1, max = 1}} or {{name = N .. "crossbow", chance = 12, min = 1, max = 1}},
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 1,
		walk_start = 1, walk_end = 2,
		run_start = 3, run_end = 3.5,
		die_start = 4, die_end = 5, die_loop = false,
		charge_start = 6, charge_end = 7.25, charge_loop = false,
	},
	after_activate = function(self)
		self._load = nil
		self._crossbow = nil
		crossbow(self, self._loaded and LOADED or STANDBY)
		goodluck_illagers.wear_banner(self)
	end,
	do_custom = step,
	on_die = function(self, pos)
		if self._captain then
			core.add_item(pos, goodluck_illagers.bottle())
			core.add_item(pos, N .. "ominous_banner")
		end
	end,
})

mobs:register_egg(PILLAGER, S("Pillager"), "goodluck_illagers_pillager_egg.png", 0)

-- a pillager where it can stand at pos; data: fields it starts with (_captain, _patrol...)
function goodluck_illagers.spawn(name, pos, data)
	local obj = core.add_entity(pos, name, data and core.serialize(data))
	return obj and obj:get_luaentity()
end
