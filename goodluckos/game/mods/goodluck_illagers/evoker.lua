-- The evoker (Evoker and its spell goals): 24 of health, no weapon, after players, villagers and iron golems up to 12
-- away (it needs not see the villagers or golems). It runs from a player 8 away, and casts, standing with its arms up:
-- three vexes (cast 5 s, the vexes after 1 s, again in 17 s, while fewer than 8 are about), else fangs at its target
-- (cast 2 s, the fangs after 1 s, again in 5 s): two rings round itself when the target is within 3, else a line of 16
-- toward it, one more each tick. With no target it turns a blue sheep within 16 red (cast 3 s after 2, again in 7 s),
-- while mobs may change things. Drops the totem of undying and now and then an emerald.
-- The fangs come up out of the ground and bite 6 into whoever is on them 8 ticks later, but the evoker's side.
-- The vex (Vex): 14 of health, flies through blocks, and charges with its iron sword for 9 (scaled by the difficulty)
-- at its evoker's target or a player 16 away, flying off a moment after each hit; it lives 30 to 119 s, then loses a
-- heart a second
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local EVOKER, VEX, FANGS = N .. "evoker", N .. "vex", N .. "evoker_fangs"
local SKIN = "goodluck_illagers_evoker.png"
local VEX_SKIN, VEX_CHARGING = "goodluck_illagers_vex.png", "goodluck_illagers_vex_charging.png"
local FLEE, VEXES = 8, 8
local FANG_DAMAGE, VEX_DAMAGE = 6, 9 * ({0.5, 1, 1.5})[math.max(1, goodluck_illagers.difficulty)] +
	(goodluck_illagers.difficulty == 1 and 1 or 0)
local griefing = core.settings:get_bool("mobs_griefing", true)
local alive = goodluck_illagers.alive
goodluck_illagers.raiders[EVOKER] = true
-- the evoker's side: raiders and vexes, whom its fangs leave alone
local function ally(obj)
	local ent = obj and obj:get_luaentity()
	return ent and (goodluck_illagers.raiders[ent.name] or ent.name == VEX)
end
goodluck_illagers.ally = ally

local function creative(obj)
	return obj:is_player() and core.is_creative_enabled(obj:get_player_name())
end

core.register_entity(FANGS, {
	initial_properties = {
		visual = "mesh",
		mesh = "goodluck_models_evoker_fangs.glb",
		textures = {"goodluck_illagers_evoker_fangs.png"},
		physical = false,
		pointable = false,
		static_save = false,
		is_visible = false,
	},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		local wait = self._delay or 0
		if self._t < wait then
			return
		end
		if not self._up then
			self._up = true
			self.object:set_properties({is_visible = true})
			self.object:set_animation({x = 0, y = 1.1}, 1, 0, false)
			core.sound_play("goodluck_illagers_evoker_fangs", {pos = self.object:get_pos(), gain = 0.7,
				max_hear_distance = 16}, true)
		end
		if not self._bit and self._t >= wait + 0.4 then
			self._bit = true
			local pos = self.object:get_pos()
			for _, obj in ipairs(core.get_objects_inside_radius(vector.offset(pos, 0, 0.4, 0), 0.9)) do
				local ent = obj:get_luaentity()
				if obj ~= self._owner and not ally(obj) and (obj:is_player() and not creative(obj) and
						obj:get_hp() > 0 or ent and ent._cmi_is_mob and (ent.health or 0) > 0) then
					local by = alive(self._owner) and self._owner or self.object
					obj:punch(by, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = FANG_DAMAGE}}, nil)
				end
			end
		end
		if self._t >= wait + 1.1 then
			self.object:remove()
		end
	end,
})

-- fangs on the ground at x, z between the evoker's and its target's heights (EvokerAttackSpellGoal.createSpellEntity)
local function fang(owner, x, z, low, high, yaw, delay)
	for y = math.floor(high + 1.5), math.floor(low - 0.5), -1 do
		local p = vector.new(math.floor(x + 0.5), y, math.floor(z + 0.5))
		local under = core.registered_nodes[core.get_node(vector.offset(p, 0, -1, 0)).name]
		local here = core.registered_nodes[core.get_node(p).name]
		if under and under.walkable and here and not here.walkable then
			local obj = core.add_entity(vector.new(x, y - 0.5, z), FANGS)
			if obj then
				obj:set_yaw(yaw)
				local ent = obj:get_luaentity()
				ent._owner, ent._delay = owner, delay
			end
			return
		end
	end
end

local function cast_fangs(self, target)
	local pos, tp = self.object:get_pos(), target:get_pos()
	local low, high = math.min(pos.y, tp.y), math.max(pos.y, tp.y)
	local f = math.atan2(tp.z - pos.z, tp.x - pos.x)
	if vector.distance(pos, tp) < 3 then
		for i = 0, 4 do
			local a = f + i * math.pi * 0.4
			fang(self.object, pos.x + math.cos(a) * 1.5, pos.z + math.sin(a) * 1.5, low, high, a, 0)
		end
		for i = 0, 7 do
			local a = f + i * math.pi * 2 / 8 + 1.2566371
			fang(self.object, pos.x + math.cos(a) * 2.5, pos.z + math.sin(a) * 2.5, low, high, a, 3 / 20)
		end
	else
		for i = 0, 15 do
			local d = 1.25 * (i + 1)
			fang(self.object, pos.x + math.cos(f) * d, pos.z + math.sin(f) * d, low, high, f, i / 20)
		end
	end
end

local function vexes_near(pos)
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 16)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == VEX then
			n = n + 1
		end
	end
	return n
end

local function cast_vexes(self)
	local pos = vector.round(self.object:get_pos())
	for _ = 1, 3 do
		local p = vector.offset(pos, math.random(-2, 2), 1, math.random(-2, 2))
		local obj = core.add_entity(p, VEX, core.serialize({_home = pos, _life = 30 + math.random(0, 89)}))
		local ent = obj and obj:get_luaentity()
		if ent then
			ent._owner = self.object
		end
	end
end

local function blue_sheep(pos)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 16)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "mobs_animal:sheep_blue" and (ent.health or 0) > 0 and
				math.abs(obj:get_pos().y - pos.y) <= 4 then
			return obj
		end
	end
end

-- wololo: the blue sheep is a red one from now on, with what it had
local function cast_wololo(self, sheep)
	local ent = sheep:get_luaentity()
	if not ent or not alive(sheep) then
		return
	end
	local keep = {}
	for _, k in ipairs({"gotten", "child", "tamed", "owner", "health", "_nametag", "hornytimer", "food"}) do
		keep[k] = ent[k]
	end
	local pos, yaw = sheep:get_pos(), sheep:get_yaw()
	sheep:remove()
	local red = core.add_entity(pos, "mobs_animal:sheep_red", core.serialize(keep))
	if red then
		red:set_yaw(yaw)
	end
end

-- each spell's warm-up, cast and wait in seconds, its particles' colour and the sound it starts with
local SPELLS = {
	vexes = {warmup = 1, length = 5, every = 17, color = "#b3b3cc", sound = "goodluck_illagers_evoker_prepare_summon"},
	fangs = {warmup = 1, length = 2, every = 5, color = "#664d59", sound = "goodluck_illagers_evoker_prepare_attack"},
	wololo = {warmup = 2, length = 3, every = 7, color = "#b38033", sound = "goodluck_illagers_evoker_prepare_wololo"},
}

local function start(self, spell, on)
	local s = SPELLS[spell]
	self._cast = {spell = spell, t = 0, on = on}
	self["_next_" .. spell] = s.every
	self:set_velocity(0)
	self:set_animation("cast", true)
	self:mob_sound({name = s.sound, gain = 1})
end

local function casting(self, dtime)
	local c = self._cast
	local s = SPELLS[c.spell]
	c.t = c.t + dtime
	self:set_velocity(0)
	if alive(c.on) then
		self:yaw_to_pos(c.on:get_pos())
	end
	self._spark = (self._spark or 0) - dtime
	if self._spark <= 0 then
		self._spark = 0.25
		core.add_particlespawner({amount = 4, time = 0.25, attached = self.object,
			pos = {min = vector.new(-0.6, 1.6, -0.6), max = vector.new(0.6, 2.1, 0.6)},
			vel = {min = vector.new(0, 0.4, 0), max = vector.new(0, 0.8, 0)},
			exptime = {min = 0.5, max = 0.9}, size = {min = 1, max = 1.6},
			texture = "goodluck_effects_particle.png^[multiply:" .. s.color})
	end
	if not c.done and c.t >= s.warmup then
		c.done = true
		self:mob_sound({name = "goodluck_illagers_evoker_cast", gain = 1})
		if c.spell == "fangs" and alive(c.on) then
			cast_fangs(self, c.on)
		elseif c.spell == "vexes" then
			cast_vexes(self)
		elseif c.spell == "wololo" then
			cast_wololo(self, c.on)
		end
	end
	if c.t >= s.length then
		self._cast = nil
		self:set_animation("stand", true)
	end
end

-- the nearest player within 8 that it would run from (AvoidEntityGoal: not one in creative)
local function threat(pos)
	local best, near = nil, FLEE
	for _, player in ipairs(core.get_connected_players()) do
		local d = vector.distance(pos, player:get_pos())
		if d < near and player:get_hp() > 0 and not creative(player) then
			best, near = player, d
		end
	end
	return best
end

local function evoker_step(self, dtime)
	if self._cast then
		casting(self, dtime)
		return false
	end
	for spell in pairs(SPELLS) do
		local k = "_next_" .. spell
		self[k] = math.max(0, (self[k] or 0) - dtime)
	end
	local pos = self.object:get_pos()
	local p = threat(pos)
	if p then
		self:yaw_to_pos(p:get_pos(), math.pi)
		self:set_velocity(self.run_velocity)
		self:set_animation("run")
	end
	if self.state == "attack" then
		local t = self.attack
		if not alive(t) or vector.distance(pos, t:get_pos()) > self.view_range + 4 then
			self:stop_attack()
			return false
		end
		if self._next_vexes <= 0 and vexes_near(pos) < VEXES then
			start(self, "vexes", t)
		elseif self._next_fangs <= 0 then
			start(self, "fangs", t)
		elseif not p then
			self:set_velocity(0)
			self:yaw_to_pos(t:get_pos())
			self:set_animation("stand")
		end
		return false
	end
	if self._next_wololo <= 0 and griefing then
		local sheep = blue_sheep(pos)
		if sheep then
			start(self, "wololo", sheep)
			return false
		end
		self._next_wololo = 1
	end
	if p then
		return false
	end
end

mobs:register_mob(EVOKER, {
	type = "monster",
	description = S("Evoker"),
	passive = false,
	attack_type = "dogfight",
	custom_attack = function() return false end,
	reach = 2,
	damage = 0,
	hp_min = 24, hp_max = 24,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.95, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_evoker.glb",
	textures = {{SKIN}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {random = "goodluck_illagers_evoker", damage = "goodluck_illagers_evoker_hurt",
		death = "goodluck_illagers_evoker_death", distance = 16},
	walk_velocity = 1, run_velocity = 2.6,
	view_range = 12,
	jump = true,
	floats = 1,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = {{name = N .. "totem_of_undying", chance = 1, min = 1, max = 1},
		{name = "goodluck_emerald:emerald", chance = 1, min = 0, max = 1}},
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 1,
		walk_start = 1, walk_end = 2,
		run_start = 3, run_end = 3.5,
		die_start = 4, die_end = 5, die_loop = false,
		cast_start = 6, cast_end = 6.94,
	},
	after_activate = function(self)
		self._cast = nil
	end,
	do_custom = evoker_step,
})

mobs:register_egg(EVOKER, S("Evoker"), "goodluck_illagers_evoker_egg.png", 0)

-- the vex: its target, its evoker's or a player it sees within 16; it flies straight at it (through anything), strikes
-- and flies off 1 to 2.5 s; with none it drifts about where it was summoned
local function vex_target(self)
	local own = self._owner
	local ent = own and own:get_luaentity()
	if ent and alive(ent.attack) then
		return ent.attack
	end
	if alive(self.attack) then
		return self.attack
	end
	local pos = self.object:get_pos()
	local best, near = nil, 16
	for _, player in ipairs(core.get_connected_players()) do
		local d = vector.distance(pos, player:get_pos())
		if d < near and player:get_hp() > 0 and not creative(player) then
			best, near = player, d
		end
	end
	return best
end

local function vex_step(self, dtime)
	if self._life then
		self._life = self._life - dtime
		if self._life <= 0 then
			self._life, self._withering = nil, 0
		end
	elseif self._withering then
		self._withering = self._withering - dtime
		if self._withering <= 0 then
			self._withering = 1
			self.health = self.health - 1
			if self:check_for_death({type = "unknown"}) then
				return false
			end
		end
	end
	self._think = (self._think or 0) - dtime
	if self._think <= 0 then
		self._think = 0.5
		local t = vex_target(self)
		self.attack = t
		self._charging = t ~= nil
		local skin = self._charging and VEX_CHARGING or VEX_SKIN
		if self._skin ~= skin then
			self._skin = skin
			self.object:set_properties({textures = {skin, "default_tool_steelsword.png"}})
		end
		self:set_animation(self._charging and "charge" or "stand")
	end
	local pos = self.object:get_pos()
	local t = self.attack
	local goal, speed
	self._back = (self._back or 0) - dtime
	if alive(t) and self._back > 0 then
		-- after a strike it flies off a moment before it charges again, as VexChargeAttackGoal ends with each hit
		goal, speed = self._away, 4
	elseif alive(t) then
		goal = vector.offset(t:get_pos(), 0, t:is_player() and 1 or 0.6, 0)
		speed = 6
		if vector.distance(pos, goal) < 1.4 then
			t:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = VEX_DAMAGE}}, nil)
			self:mob_sound({name = "goodluck_illagers_vex_charge", gain = 1})
			local a = math.random() * 2 * math.pi
			self._back = 1 + math.random() * 1.5
			self._away = vector.offset(goal, math.cos(a) * 4, 1 + math.random() * 2, math.sin(a) * 4)
		end
	else
		local home = self._home or vector.round(pos)
		self._home = home
		if not self._drift or vector.distance(pos, self._drift) < 1 then
			self._drift = vector.offset(home, math.random(-7, 7), math.random(0, 4), math.random(-7, 7))
		end
		goal, speed = self._drift, 2
	end
	local d = vector.subtract(goal, pos)
	local len = vector.length(d)
	self.object:set_velocity(len > 0.5 and vector.multiply(d, math.min(speed, len * 3) / len) or vector.zero())
	if len > 0.1 then
		self.object:set_yaw(math.atan2(-d.x, d.z))
	end
	return false
end

mobs:register_mob(VEX, {
	type = "monster",
	description = S("Vex"),
	passive = false,
	attack_type = "dogfight",
	custom_attack = function() return false end,
	reach = 1,
	damage = 0,
	hp_min = 14, hp_max = 14,
	armor = 100,
	collisionbox = {-0.2, 0, -0.2, 0.2, 0.8, 0.2},
	visual = "mesh",
	mesh = "goodluck_models_vex.glb",
	textures = {{VEX_SKIN, "default_tool_steelsword.png"}},
	use_texture_alpha = true,
	fly = true,
	fly_in = {"air"},
	sounds = {random = "goodluck_illagers_vex", damage = "goodluck_illagers_vex_hurt",
		death = "goodluck_illagers_vex_death", distance = 16},
	walk_velocity = 2, run_velocity = 6,
	view_range = 16,
	water_damage = 0, lava_damage = 0, light_damage = 0, fall_damage = false,
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 0.39,
		walk_start = 0, walk_end = 0.39,
		run_start = 0, run_end = 0.39,
		charge_start = 1, charge_end = 1.39,
		die_start = 4, die_end = 5, die_loop = false,
	},
	after_activate = function(self)
		self.object:set_properties({physical = false, collide_with_objects = false})
		self.object:set_acceleration(vector.zero())
	end,
	do_custom = vex_step,
})

mobs:register_egg(VEX, S("Vex"), "goodluck_illagers_vex_egg.png", 0)
