-- Who goes after whom, as Minecraft's mobs do: the zombie and the illagers after players, villagers and iron golems;
-- the skeleton, the wither skeleton, the spider and the magma cube after players and iron golems; every other monster
-- after players only. Golems go after monsters (init.lua), and a mob hit by another one (or by its arrow, fireball or
-- snowball) goes after it. Villagers fight no one: they run from a zombie 8 away (an illager 10 to 15), and when they
-- panic (that, or being hit), three to five of them within 10 that slept in the last day and saw no iron golem for 30
-- s call one, as Minecraft's villagers do. Every village has its iron golem, by the crossroads (goodluck_villages)
local G = "goodluck_golems:"
local IRON = G .. "iron_golem"
local NPC, TRADER = "mobs_npc:npc", "mobs_npc:trader"
local TARGETS = {
	["goodluck_monsters:zombie"] = {"player", NPC, TRADER, IRON},
	["goodluck_monsters:skeleton"] = {"player", IRON},
	["goodluck_monsters:spider"] = {"player", IRON},
	["goodluck_nether:wither_skeleton"] = {"player", IRON},
	["goodluck_nether:magma_cube"] = {"player", IRON},
	["goodluck_illagers:pillager"] = {"player", NPC, TRADER, IRON},
	["goodluck_illagers:vindicator"] = {"player", NPC, TRADER, IRON},
	["goodluck_illagers:evoker"] = {"player", NPC, TRADER, IRON},
	["goodluck_illagers:ravager"] = {"player", NPC, TRADER, IRON},
}
-- what a villager runs from, and from how near (Minecraft's VillagerHostilesSensor)
local FEARED = {["goodluck_monsters:zombie"] = 8, ["goodluck_illagers:pillager"] = 15,
	["goodluck_illagers:vindicator"] = 10, ["goodluck_illagers:evoker"] = 12, ["goodluck_illagers:ravager"] = 12,
	["goodluck_illagers:vex"] = 8}
local VILLAGER = {[NPC] = true, [TRADER] = true}
-- s that a golem seen keeps them from calling one, s between their looks for one, days since they last slept
local SEEN, LOOK, SLEPT = 30, 10, 1
local alive = goodluck_golems.alive

local function free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and not def.walkable and def.liquidtype == "none"
end

local function room(p)
	local under = core.registered_nodes[core.get_node(vector.offset(p, 0, -1, 0)).name]
	return under and under.walkable and free(p) and free(vector.offset(p, 0, 1, 0)) and free(vector.offset(p, 0, 2, 0))
end

-- where an iron golem can stand up to 8 away and 6 up or down (10 tries, as Minecraft's)
local function spot(pos)
	for _ = 1, 10 do
		local x, z = math.floor(pos.x + 0.5) + math.random(-8, 8), math.floor(pos.z + 0.5) + math.random(-8, 8)
		for y = math.floor(pos.y + 0.5) + 6, math.floor(pos.y + 0.5) - 6, -1 do
			local p = vector.new(x, y, z)
			if room(p) then
				return p
			end
		end
	end
end

-- a new village's golem, at its crossroads (pos: where one stands there), which it keeps coming back to
function goodluck_golems.village(pos)
	local p = room(pos) and pos or spot(pos)
	if p then
		goodluck_golems.spawn(IRON, p, {_home = pos})
	end
end

local function slept(ent)
	return ent.goodluck_slept and core.get_day_count() + core.get_timeofday() - ent.goodluck_slept <= SLEPT
end

local function wants(ent, t)
	return slept(ent) and (ent._golem_seen or -SEEN) <= t - SEEN
end

local function panic(self)
	local t = core.get_gametime()
	if not wants(self, t) then
		return
	end
	local pos = self.object:get_pos()
	local group = {}
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 10)) do
		local ent = obj:get_luaentity()
		if ent and VILLAGER[ent.name] and wants(ent, t) then
			group[#group + 1] = ent
			if #group == 5 then
				break
			end
		end
	end
	local p = #group >= 3 and spot(pos)
	if p then
		goodluck_golems.spawn(IRON, p, {_home = vector.round(pos)})
		for _, ent in ipairs(group) do
			ent._golem_seen = t
		end
	end
end

-- once a second a villager awake looks for a zombie near it (and runs), every 10 s for an iron golem
local function watch(self, dtime)
	local pos = self.object:get_pos()
	self._golem_look = (self._golem_look or math.random() * LOOK) - dtime
	if self._golem_look <= 0 then
		self._golem_look = LOOK
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 16)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == IRON then
				self._golem_seen = core.get_gametime()
				break
			end
		end
	end
	self._fear = (self._fear or 0) - dtime
	if self._fear > 0 or self.goodluck_sleeping then
		return
	end
	self._fear = 1
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 8)) do
		local ent = obj:get_luaentity()
		local near = ent and FEARED[ent.name]
		if near and alive(obj) and vector.distance(pos, obj:get_pos()) <= near then
			self:yaw_to_pos(obj:get_pos(), 3)
			self.state, self.runaway_timer, self.following = "runaway", 3, nil
			panic(self)
			return
		end
	end
end

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_entities) do
		if def._cmi_is_mob and def.type == "monster" then
			def.specific_attack = TARGETS[name]
			def.attack_npcs = TARGETS[name] ~= nil
		end
	end
	for name in pairs(VILLAGER) do
		local def = core.registered_entities[name]
		if def then
			def.passive, def.attack_monsters, def.runaway = true, false, true
			local step, punched = def.do_custom, def.do_punch
			def.do_custom = function(self, dtime, moveresult)
				watch(self, dtime)
				if step then
					return step(self, dtime, moveresult)
				end
			end
			def.do_punch = function(self, ...)
				panic(self)
				if punched then
					return punched(self, ...)
				end
			end
		end
	end
end)
