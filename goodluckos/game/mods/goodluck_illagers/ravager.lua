-- The ravager (Ravager): 100 of health, hardly pushed back, a bite for 12 that throws what it hits 1.5 away, after
-- players, villagers and iron golems up to 32 away; it steps up a block, and breaks through the leaves it walks into
-- while mobs may change blocks. Drops a saddle. In a raid a pillager rides it
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local RAVAGER = N .. "ravager"
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
	target:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = self.damage}}, nil)
	local d = vector.subtract(target:get_pos(), self.object:get_pos())
	d.y = 0
	d = vector.length(d) > 0 and vector.normalize(d) or vector.new(0, 0, 1)
	target:add_velocity(vector.new(d.x * 7.5, 2.5, d.z * 7.5))
	return false
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
		trample(self, dtime)
		if self.state ~= "attack" then
			return goodluck_illagers.patrol(self, dtime)
		end
	end,
})

mobs:register_egg(RAVAGER, S("Ravager"), "goodluck_illagers_ravager_egg.png", 0)
