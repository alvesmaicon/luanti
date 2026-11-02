-- Raids, as Minecraft's Raid has them: Bad Omen taken into a village (villagers within 32) turns into Raid Omen, and
-- 30 s later a raid starts there (milk before that, and none). Its waves come one at a time, 15 s apart, from about
-- 32 away: 3 on Easy, 5 on Normal, 7 on Hard and one more for an omen over I, each Raid.RaiderType's mix of pillagers,
-- vindicators, evokers, witches and ravagers with a few more by difficulty, the first illager of each with a banner,
-- the ravager of the fifth wave ridden by a pillager and those of the seventh by an evoker and a vindicator. Raiders
-- march on the village and go after its villagers, golems and players; the villagers go home as at night. A bar at the
-- top shows the raiders' health left, and fills while the next wave comes. When the last wave is down, the players
-- within 96 have Hero of the Village for 40 minutes at the omen's level; no villager left within 48 loses the raid,
-- and it ends after 40 minutes or with no player within 128 for a minute. Bad Omen taken into a raid raises its level.
-- At most 10 raiders are out at once here: the rest of a wave comes as they fall
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local E = goodluck_effects
local PILLAGER, VINDICATOR, EVOKER, RAVAGER = N .. "pillager", N .. "vindicator", N .. "evoker", N .. "ravager"
local WITCH = "goodluck_monsters:witch"
local VILLAGERS = {["mobs_npc:npc"] = true, ["mobs_npc:trader"] = true}
-- Raid.RaiderType: how many of each a wave brings, in its order
local ORDER = {VINDICATOR, EVOKER, PILLAGER, WITCH, RAVAGER}
local WAVES = {
	[VINDICATOR] = {0, 2, 0, 1, 4, 2, 5},
	[EVOKER] = {0, 0, 0, 0, 1, 1, 2},
	[PILLAGER] = {4, 3, 3, 4, 4, 4, 2},
	[WITCH] = {0, 0, 0, 3, 0, 0, 1},
	[RAVAGER] = {0, 0, 1, 0, 1, 0, 2},
}
local GROUPS = {3, 5, 7}
local OMEN, BETWEEN, HERO, TIMEOUT = 30, 15, 2400, 2400
local VILLAGE, RADIUS, GONE, SPAWN = 32, 96, 128, 32
local CAP = 10
local raids = {}
local omens = {}

E.register("raid_omen", {description = S("Raid Omen"), color = "#de4058", icon = "goodluck_illagers_raid_omen.png",
	swirl = false})
E.register("hero_of_the_village", {description = S("Hero of the Village"), color = "#44ff44",
	icon = "goodluck_illagers_hero_of_the_village.png"})

local function alive(obj)
	return goodluck_illagers.alive(obj)
end

local function villagers_near(pos, r)
	local n, sum = 0, vector.zero()
	for _, obj in ipairs(core.get_objects_inside_radius(pos, r)) do
		local ent = obj:get_luaentity()
		if ent and VILLAGERS[ent.name] and (ent.health or 0) > 0 then
			n, sum = n + 1, vector.add(sum, obj:get_pos())
		end
	end
	return n, n > 0 and vector.divide(sum, n) or nil
end

local function raid_at(pos)
	for _, r in pairs(raids) do
		if not r.over and vector.distance(r.center, pos) < RADIUS then
			return r
		end
	end
end

-- the centre of a raid, for its raiders' march; nil once it is over
function goodluck_illagers.raid_center(id)
	local r = raids[id]
	return r and not r.over and r.center or nil
end

-- villagers go home while their village is raided (goodluck_villages' sleep.lua asks)
if core.global_exists("goodluck_villages") then
	function goodluck_villages.raided(pos)
		return pos ~= nil and raid_at(pos) ~= nil
	end
end

-- Raid.getPotentialBonusSpawns
local function bonus(name, wave, last)
	local d = goodluck_illagers.difficulty
	local i
	if name == WITCH then
		if d == 1 or wave <= 2 or wave == 4 then
			return 0
		end
		i = 1
	elseif name == PILLAGER or name == VINDICATOR then
		i = d == 1 and math.random(0, 1) or d == 2 and 1 or 2
	elseif name == RAVAGER then
		i = d ~= 1 and last and 1 or 0
	else
		return 0
	end
	return i > 0 and math.random(0, i) or 0
end

-- the wave's raiders, in order: {name, rider}
local function group(r, wave)
	local extra = wave > r.groups
	local list = {}
	for _, name in ipairs(ORDER) do
		if core.registered_entities[name] then
			local count = WAVES[name][extra and r.groups or wave] + bonus(name, wave, extra)
			for i = 1, count do
				local rider
				if name == RAVAGER then
					rider = wave == GROUPS[2] and PILLAGER or wave >= GROUPS[3] and (i == 1 and EVOKER or VINDICATOR)
				end
				list[#list + 1] = {name, rider}
			end
		end
	end
	return list
end

local function ground(x, z, y0)
	for y = y0 + 20, y0 - 20, -1 do
		local here = core.get_node_or_nil(vector.new(x, y, z))
		local under = core.get_node_or_nil(vector.new(x, y - 1, z))
		local above = core.get_node_or_nil(vector.new(x, y + 1, z))
		local hd = here and core.registered_nodes[here.name]
		local ud = under and core.registered_nodes[under.name]
		local ad = above and core.registered_nodes[above.name]
		if ud and ud.walkable and hd and not hd.walkable and hd.liquidtype == "none" and ad and not ad.walkable then
			return vector.new(x, y, z)
		end
	end
end

-- where a wave comes from: open ground about 32 from the centre, nearer if none is found
local function spawn_spot(r)
	for _, dist in ipairs({SPAWN, 24, 16, 8}) do
		for _ = 1, 20 do
			local a = math.random() * 2 * math.pi
			local p = ground(math.floor(r.center.x + math.cos(a) * dist + 0.5),
				math.floor(r.center.z + math.sin(a) * dist + 0.5), math.floor(r.center.y + 0.5))
			if p then
				return p
			end
		end
	end
	return vector.round(r.center)
end

local function bring(r, entry)
	local p = vector.offset(r.from, math.random(-2, 2), 0, math.random(-2, 2))
	p = ground(p.x, p.z, p.y) or r.from
	local leader = not r.leader and entry[1] ~= WITCH and entry[1] ~= RAVAGER
	local ent = goodluck_illagers.spawn(entry[1], p, {_raid = r.id, _raid_leader = leader or nil})
	if not ent then
		return
	end
	r.leader = r.leader or leader
	r.raiders[#r.raiders + 1] = ent.object
	if entry[2] then
		local rider = goodluck_illagers.spawn(entry[2], vector.offset(p, 0, 2.5, 0), {_raid = r.id})
		if rider then
			rider.object:set_attach(ent.object, "", {x = 0, y = 17, z = 2}, {x = 0, y = 0, z = 0})
			r.raiders[#r.raiders + 1] = rider.object
		end
	end
end

local function hud_off(r, name)
	local h = r.huds[name]
	local p = core.get_player_by_name(name)
	if h and p then
		p:hud_remove(h.bg)
		p:hud_remove(h.fill)
		p:hud_remove(h.label)
	end
	r.huds[name] = nil
end

-- the bar over the players within 96: the label and its share
local function bars(r, label, share)
	local seen = {}
	for _, p in ipairs(core.get_connected_players()) do
		local name = p:get_player_name()
		if vector.distance(p:get_pos(), r.center) < RADIUS then
			seen[name] = true
			local h = r.huds[name]
			if not h then
				h = {
					bg = p:hud_add({type = "image", position = {x = 0.5, y = 0}, offset = {x = 0, y = 22},
						text = "[fill:182x5:0,0:#4a0a0a", scale = {x = 1.6, y = 1.6}, alignment = {x = 0, y = 0},
						z_index = 20}),
					fill = p:hud_add({type = "image", position = {x = 0.5, y = 0}, offset = {x = -145.6, y = 22},
						text = "[fill:182x5:0,0:#e02020", scale = {x = 1.6 * share, y = 1.6}, alignment = {x = 1, y = 0},
						z_index = 21}),
					label = p:hud_add({type = "text", position = {x = 0.5, y = 0}, offset = {x = 0, y = 10},
						text = label, number = 0xFFFFFF, alignment = {x = 0, y = 0}, z_index = 22}),
					share = share, text = label,
				}
				r.huds[name] = h
			else
				if math.abs(h.share - share) > 0.002 then
					p:hud_change(h.fill, "scale", {x = 1.6 * share, y = 1.6})
					h.share = share
				end
				if h.text ~= label then
					p:hud_change(h.label, "text", label)
					h.text = label
				end
			end
		end
	end
	for name in pairs(r.huds) do
		if not seen[name] then
			hud_off(r, name)
		end
	end
end

local function finish(r, label)
	r.over, r.ending, r.label = true, 5, label
end

local function start(pos, level)
	local r = raid_at(pos)
	if r then
		-- another omen in the same raid raises its level, up to V
		r.level = math.min(5, r.level + level)
		r.waves = r.groups + (r.level > 1 and 1 or 0)
		return
	end
	local n, middle = villagers_near(pos, VILLAGE + 16)
	if n == 0 then
		return
	end
	local id = ("%x%04x"):format(os.time(), math.random(0, 0xffff))
	local groups = GROUPS[math.max(1, goodluck_illagers.difficulty)]
	raids[id] = {id = id, center = vector.round(middle), level = level, groups = groups,
		waves = groups + (level > 1 and 1 or 0), wave = 0, wait = BETWEEN, raiders = {}, queue = {}, max = 0,
		huds = {}, age = 0, alone = 0}
	core.log("action", ("[goodluck_illagers] raid of level %d at %s"):format(level, core.pos_to_string(middle)))
end
goodluck_illagers.start_raid = start

local function step(r, dt)
	r.age = r.age + dt
	if r.over then
		r.ending = r.ending - dt
		bars(r, r.label, r.label == S("Raid - Victory") and 1 or 0)
		if r.ending <= 0 then
			for name in pairs(r.huds) do
				hud_off(r, name)
			end
			raids[r.id] = nil
		end
		return
	end
	local near = false
	for _, p in ipairs(core.get_connected_players()) do
		near = near or vector.distance(p:get_pos(), r.center) < GONE
	end
	r.alone = near and 0 or r.alone + dt
	if r.alone > 60 or r.age > TIMEOUT then
		r.over, r.ending, r.label = true, 0, ""
		return
	end
	if villagers_near(r.center, 48) == 0 then
		return finish(r, S("Raid - Defeat"))
	end
	local live, health = {}, 0
	for _, obj in ipairs(r.raiders) do
		if alive(obj) then
			live[#live + 1] = obj
			health = health + (obj:get_luaentity().health or 0)
		end
	end
	r.raiders = live
	while #r.queue > 0 and #r.raiders < CAP do
		bring(r, table.remove(r.queue, 1))
	end
	if r.wave > 0 and (#r.raiders > 0 or #r.queue > 0) then
		for _, entry in ipairs(r.queue) do
			health = health + (core.registered_entities[entry[1]].hp_max or 0)
		end
		local label = S("Raid")
		local left = #r.raiders + #r.queue
		if left <= 2 then
			label = label .. " - " .. S("Raiders Remaining: @1", left)
		end
		bars(r, label, math.min(1, health / math.max(1, r.max + 0.001)))
		return
	end
	if r.wave >= r.waves then
		for _, p in ipairs(core.get_connected_players()) do
			if vector.distance(p:get_pos(), r.center) < RADIUS then
				E.apply(p, "hero_of_the_village", HERO, r.level)
			end
		end
		core.log("action", "[goodluck_illagers] raid won at " .. core.pos_to_string(r.center))
		return finish(r, S("Raid - Victory"))
	end
	r.wait = r.wait - dt
	bars(r, S("Raid"), math.max(0, 1 - r.wait / BETWEEN))
	if r.wait <= 0 then
		r.wave, r.wait, r.leader, r.max = r.wave + 1, BETWEEN, nil, 0
		r.from = spawn_spot(r)
		r.queue = group(r, r.wave)
		-- the bar's whole: the wave's health, riders too
		for _, entry in ipairs(r.queue) do
			r.max = r.max + (core.registered_entities[entry[1]].hp_max or 0) +
				(entry[2] and core.registered_entities[entry[2]].hp_max or 0)
		end
		while #r.queue > 0 and #r.raiders < CAP do
			bring(r, table.remove(r.queue, 1))
		end
		for _, p in ipairs(core.get_connected_players()) do
			if vector.distance(p:get_pos(), r.center) < RADIUS then
				core.sound_play("goodluck_illagers_raid_horn", {to_player = p:get_player_name(), gain = 1}, true)
			end
		end
	end
end

-- the witch joins raids too (goodluck_monsters'), marching as the illagers do
core.register_on_mods_loaded(function()
	local def = core.registered_entities[WITCH]
	if def then
		local custom = def.do_custom
		def.do_custom = function(self, dtime, moveresult)
			if self._raid and self.state ~= "attack" and goodluck_illagers.patrol(self, dtime) == false then
				return false
			end
			if custom then
				return custom(self, dtime, moveresult)
			end
		end
	end
end)

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.5 then
		return
	end
	local dt = timer
	timer = 0
	for _, p in ipairs(core.get_connected_players()) do
		local name = p:get_player_name()
		local level = E.get(p, "bad_omen")
		local pos = p:get_pos()
		if level and goodluck_illagers.difficulty > 0 and villagers_near(pos, VILLAGE) > 0 then
			-- Bad Omen in a village: Raid Omen for 30 s, a raid where it began when it runs out (BadOmenMobEffect)
			E.remove(p, "bad_omen")
			E.apply(p, "raid_omen", OMEN, level)
			omens[name] = vector.round(pos)
			core.sound_play("goodluck_illagers_raid_omen", {to_player = name, gain = 0.8}, true)
		end
		local rlevel, left = E.get(p, "raid_omen")
		if rlevel and left <= 0.6 and omens[name] then
			E.remove(p, "raid_omen")
			start(omens[name], rlevel)
			omens[name] = nil
		elseif not rlevel then
			omens[name] = nil
		end
	end
	for _, r in pairs(raids) do
		step(r, dt)
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	omens[name] = nil
	for _, r in pairs(raids) do
		r.huds[name] = nil
	end
end)

-- the raids under way, for tests
function goodluck_illagers.raids()
	return raids
end
