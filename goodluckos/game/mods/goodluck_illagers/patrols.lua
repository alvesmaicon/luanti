-- Patrols, as PatrolSpawner sends them: every 10 to 11 minutes of daytime from the fifth day on, one time in five, a
-- patrol comes out on the ground 24 to 48 away each way from a player away from villages (and outside the Nether and
-- the End), where no lamp lights it over 8: 2, 3 or 4 pillagers by difficulty (Minecraft's ceil of the local
-- difficulty and 1), the first their captain. The captain walks to a point up to 500 away each way and then on to
-- another, a new one when it gets stuck; the others keep up with it, the captain slower than them (0.595 against
-- 0.7, LongDistancePatrolGoal). Each goes after what it sees, as any pillager does
local N = "goodluck_illagers:"
local PILLAGER = N .. "pillager"
local EVERY, JITTER, FIRST_DAY, CHANCE = 600, 60, 5, 5
local COUNT = ({2, 3, 4})[math.max(1, goodluck_illagers.difficulty)]
local VILLAGERS = {["mobs_npc:npc"] = true, ["mobs_npc:trader"] = true}
local FAR, NEAR, LOOK, STUCK = 500, 10, 1, 3
local LEADER_SPEED = 0.595 / 0.7
local alive = goodluck_illagers.alive
local nether, the_end = core.global_exists("goodluck_nether"), core.global_exists("goodluck_end")
local timer = EVERY + math.random(0, JITTER)

-- the captain's way to its point, the others' to their captain, a raider's to its raid's village; false while it
-- walks there (and so skips mobs_redo's wandering), looking for targets once a second as mobs_redo would, and on a
-- ravager it only looks. Every 3 s on the move it checks it went a node; if not (a tree, a wall, a drop), the captain
-- takes another point and the others step aside a moment
function goodluck_illagers.patrol(self, dtime)
	local rider = self.object:get_attach() ~= nil
	local center = self._raid and goodluck_illagers.raid_center(self._raid)
	if not self._patrol and not center and not rider then
		return
	end
	self._look = (self._look or math.random() * LOOK) - dtime
	if self._look <= 0 then
		self._look = LOOK
		self:general_attack()
		if self.state == "attack" then
			return false
		end
	end
	if rider then
		-- on a ravager, which does the walking
		self:set_animation("sit")
		return false
	end
	local pos = self.object:get_pos()
	if center then
		-- a raider marches on the village's middle, and roams there
		if vector.distance(pos, center) < 8 then
			return
		end
		self._patrol_to = center
	end
	if (self._aside or 0) > 0 then
		self._aside = self._aside - dtime
		self:set_velocity(self.walk_velocity)
		self:set_animation("walk")
		return false
	end
	local goal, speed = nil, self.walk_velocity
	if center then
		goal = center
	elseif self._captain then
		goal = self._patrol_to
		if not goal or self.at_cliff or math.hypot(goal.x - pos.x, goal.z - pos.z) < NEAR then
			goal = vector.offset(vector.round(pos), math.random(-FAR, FAR), 0, math.random(-FAR, FAR))
			self._patrol_to = goal
		end
		speed = speed * LEADER_SPEED
	else
		local leader = self._leader
		if not alive(leader) then
			self._leader = nil
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 24)) do
				local ent = obj:get_luaentity()
				if ent and ent._captain and ent._patrol == self._patrol and alive(obj) then
					self._leader = obj
					break
				end
			end
			if not self._leader then
				-- no captain left: an ordinary pillager from now on
				self._patrol = nil
				return
			end
			leader = self._leader
		end
		goal = leader:get_pos()
		if vector.distance(pos, goal) < 3 then
			self._was = nil
			self:set_velocity(0)
			self:set_animation("stand")
			return false
		end
	end
	self._stuck = (self._stuck or STUCK) - dtime
	if self._stuck <= 0 then
		self._stuck = STUCK
		if self._was and vector.distance(self._was, pos) < 1 then
			self._was = nil
			if self._captain and not center then
				self._patrol_to = nil
			else
				self._aside = 1.5
				self:yaw_to_pos(goal, math.random(2) == 1 and 1.5 or -1.5)
			end
			return false
		end
		self._was = pos
	end
	if self.at_cliff then
		-- at a drop it turns at once, the captain to its new point and the others aside, and goes on when clear
		self:yaw_to_pos(goal, self._captain and not center and 0 or (math.random(2) == 1 and 1.5 or -1.5))
		self:set_velocity(0)
		self:set_animation("stand")
		return false
	end
	self:yaw_to_pos(goal, 0, 6)
	self:set_velocity(speed)
	self:set_animation("walk")
	return false
end

local function free(pos)
	local def = core.registered_nodes[(core.get_node_or_nil(pos) or {name = "ignore"}).name]
	return def and not def.walkable and def.liquidtype == "none" and def.name ~= "ignore"
end

-- the ground at x, z between 24 above and 16 below y: open to the sky, two free nodes over it, no lamp over 8
local function ground(x, y, z)
	for py = y + 24, y - 16, -1 do
		local p = vector.new(x, py, z)
		local under = core.get_node_or_nil(vector.offset(p, 0, -1, 0))
		local def = under and core.registered_nodes[under.name]
		if def and def.walkable and free(p) and free(vector.offset(p, 0, 1, 0)) then
			local node = core.get_node(p)
			if (core.get_natural_light(p, 0.5) or 0) < 15 or core.get_artificial_light(node.param1) > 8 then
				return
			end
			return p
		end
	end
end

local function near_village(pos)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 48)) do
		local ent = obj:get_luaentity()
		if ent and VILLAGERS[ent.name] then
			return true
		end
	end
end

-- a patrol by player: true when it came
function goodluck_illagers.send_patrol(player)
	local pos = vector.round(player:get_pos())
	if nether and goodluck_nether.inside(pos) or the_end and goodluck_end.inside(pos) or near_village(pos) then
		return false
	end
	local function side()
		return (24 + math.random(0, 24)) * (math.random(2) == 1 and -1 or 1)
	end
	local x, z = pos.x + side(), pos.z + side()
	local first = ground(x, pos.y, z)
	if not first then
		return false
	end
	local id = ("%x%04x"):format(os.time(), math.random(0, 0xffff))
	for i = 1, COUNT do
		local p = i == 1 and first or ground(first.x + math.random(-5, 5), first.y, first.z + math.random(-5, 5))
		if p then
			goodluck_illagers.spawn(PILLAGER, p, {_patrol = id, _captain = i == 1 or nil})
		end
	end
	core.log("action", ("[goodluck_illagers] patrol of %d at %s"):format(COUNT, core.pos_to_string(first)))
	return true
end

local function daytime()
	local t = core.get_timeofday()
	return t > 0.22 and t < 0.78
end

core.register_globalstep(function(dtime)
	timer = timer - dtime
	if timer > 0 then
		return
	end
	timer = EVERY + math.random(0, JITTER)
	local players = core.get_connected_players()
	if goodluck_illagers.difficulty == 0 or #players == 0 or core.get_day_count() < FIRST_DAY or not daytime() or
			math.random(CHANCE) ~= 1 then
		return
	end
	goodluck_illagers.send_patrol(players[math.random(#players)])
end)
