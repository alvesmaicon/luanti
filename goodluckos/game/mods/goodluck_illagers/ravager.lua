-- The ravager (Ravager): 100 of health, hardly pushed back, a bite for 12 that throws what it hits 1.5 away, after
-- players, villagers and iron golems up to 32 away; it steps up a block, and breaks through the leaves it walks into
-- while mobs may change blocks. Drops a saddle. In a raid a pillager rides it. A bite on a raised shield stuns it half
-- the time (Ravager.blockedByItem): 2 s in a daze, and then it roars, 6 to everything within 4 but the illagers, and
-- throws them off (strongKnockback: 4 over the square of the distance, a tick)
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local RAVAGER = N .. "ravager"
local STUN, ROAR_REACH, ROAR_DAMAGE = 2, 4, 6
local ILLAGERS = {[N .. "pillager"] = true, [N .. "vindicator"] = true, [N .. "evoker"] = true}
local griefing = core.settings:get_bool("mobs_griefing", true)
goodluck_illagers.raiders[RAVAGER] = true

-- mobs_redo's custom_attack, called as self:custom_attack(self, pos)
local function bite(self)
	local target = self.attack
	if not goodluck_illagers.alive(target) then
		return false
	end
	self:set_animation("punch", true)
	self:mob_sound({name = "goodluck_illagers_ravager_bite", gain = 1})
	local blocked = target:is_player() and core.global_exists("goodluck_shield") and
		goodluck_shield.blocks(target, self.object)
	if blocked and not self._stunned and math.random() < 0.5 then
		self._stunned = STUN
		self:mob_sound({name = "goodluck_illagers_ravager_stun", gain = 1})
	end
	target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
	if not blocked then
		local d = vector.subtract(target:get_pos(), self.object:get_pos())
		d.y = 0
		d = vector.length(d) > 0 and vector.normalize(d) or vector.new(0, 0, 1)
		target:add_velocity(vector.new(d.x * 7.5, 2.5, d.z * 7.5))
	end
	return false
end

local function roar(self)
	local pos = self.object:get_pos()
	self:set_animation("punch", true)
	self:mob_sound({name = "goodluck_illagers_ravager_roar", gain = 1})
	core.add_particlespawner({amount = 40, time = 0.3,
		pos = {min = vector.offset(pos, -2, 0.2, -2), max = vector.offset(pos, 2, 2, 2)},
		vel = {min = vector.new(-3, 0, -3), max = vector.new(3, 1.5, 3)}, exptime = {min = 0.4, max = 0.9},
		size = {min = 2, max = 4}, texture = "goodluck_effects_particle.png^[multiply:#e0e0e0"})
	for _, obj in ipairs(core.get_objects_inside_radius(pos, ROAR_REACH)) do
		local ent = obj:get_luaentity()
		local living = obj:is_player() and obj:get_hp() > 0 and not core.is_creative_enabled(obj:get_player_name()) or
			ent and ent._cmi_is_mob and (ent.health or 0) > 0
		if obj ~= self.object and living and not (ent and ILLAGERS[ent.name]) then
			obj:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = ROAR_DAMAGE}}, nil)
			local d = vector.subtract(obj:get_pos(), pos)
			local square = math.max(d.x * d.x + d.z * d.z, 0.001)
			obj:add_velocity(vector.new(d.x / square * 16, 4, d.z / square * 16))
		end
	end
end

-- dazed: it stands, grey sparks over it, and roars when it comes to
local function dazed(self, dtime)
	self._stunned = self._stunned - dtime
	self:set_velocity(0)
	self:set_animation("stand")
	self._spark = (self._spark or 0) - dtime
	if self._spark <= 0 then
		self._spark = 0.3
		core.add_particlespawner({amount = 3, time = 0.3, attached = self.object,
			pos = {min = vector.new(-0.6, 2.2, -1.4), max = vector.new(0.6, 2.6, -0.6)},
			vel = {min = vector.new(-0.3, 0.6, -0.3), max = vector.new(0.3, 1, 0.3)}, exptime = {min = 0.5, max = 0.8},
			size = {min = 1, max = 1.5}, texture = "goodluck_effects_particle.png^[multiply:#7f8392"})
	end
	if self._stunned <= 0 then
		self._stunned = nil
		roar(self)
	end
end

-- the leaves it walks into go, as Ravager.aiStep breaks them on a horizontal collision with mobGriefing
local function trample(self, dtime)
	self._trample = (self._trample or 0) - dtime
	if self._trample > 0 or not griefing then
		return
	end
	self._trample = 0.5
	local pos = self.object:get_pos()
	local yaw = self.object:get_yaw()
	local ahead = vector.offset(pos, -math.sin(yaw) * 1.4, 0, math.cos(yaw) * 1.4)
	for _, p in ipairs(core.find_nodes_in_area(vector.offset(ahead, -1, 0, -1), vector.offset(ahead, 1, 2, 1),
			{"group:leaves"})) do
		local node = core.get_node(p)
		if not core.is_protected(p, "") then
			core.remove_node(p)
			for _, item in ipairs(core.get_node_drops(node.name, "")) do
				core.add_item(p, item)
			end
		end
	end
end

mobs:register_mob(RAVAGER, {
	type = "monster",
	description = S("Ravager"),
	passive = false,
	attack_type = "dogfight",
	custom_attack = bite,
	pathfinding = 1,
	reach = 3,
	damage = 12,
	hp_min = 100, hp_max = 100,
	armor = 100,
	knock_back = false,
	collisionbox = {-0.975, 0, -0.975, 0.975, 2.2, 0.975},
	visual = "mesh",
	mesh = "goodluck_models_ravager.glb",
	textures = {{"goodluck_illagers_ravager.png"}},
	makes_footstep_sound = true,
	sounds = {random = "goodluck_illagers_ravager", damage = "goodluck_illagers_ravager_hurt",
		death = "goodluck_illagers_ravager_death", distance = 16},
	walk_velocity = 1, run_velocity = 2.6,
	stepheight = 1.1,
	view_range = 32,
	jump = true,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = {{name = "mobs:saddle", chance = 1, min = 1, max = 1}},
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 1,
		walk_start = 1, walk_end = 3,
		run_start = 3, run_end = 4,
		punch_start = 7, punch_end = 7.5,
		die_start = 5, die_end = 6, die_loop = false,
	},
	do_custom = function(self, dtime)
		if self._stunned then
			dazed(self, dtime)
			return false
		end
		trample(self, dtime)
		if self.state ~= "attack" then
			return goodluck_illagers.patrol(self, dtime)
		end
	end,
})

mobs:register_egg(RAVAGER, S("Ravager"), "goodluck_illagers_ravager_egg.png", 0)
