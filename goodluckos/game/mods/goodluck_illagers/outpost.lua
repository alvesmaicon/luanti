-- Pillager outposts, as Minecraft has them in the open lands (plains, savanna, the deserts, the taiga and the snowy
-- ones) and never by a village: a dark wood tower of three floors with a ladder inside, a roofed lookout on top with
-- a chest (pillager_outpost's loot), and now and then a cage with an iron golem in it by the tower. Pillagers keep
-- coming in it while a player is about, 6 % of them captains, as Minecraft's structure spawns them, 4 at a time at
-- most here. Built in the middle of a mapchunk whose index is odd both ways (villages take the even ones), one in 12
local N = "goodluck_illagers:"
local PILLAGER = N .. "pillager"
local CHANCE, CAP, EVERY, AROUND, MIN_AWAY = 12, 4, 10, 96, 16
local CAPTAIN = 0.06
local BIOMES = {grassland = true, savanna = true, desert = true, sandstone_desert = true, cold_desert = true,
	taiga = true, coniferous_forest = true, snowy_grassland = true, tundra = true}
local CHUNKSIZE = tonumber(core.get_mapgen_setting("chunksize")) or 5
local CHUNK = 16 * CHUNKSIZE
local OFFSET = -16 * math.floor(CHUNKSIZE / 2)
local structures = Settings(core.get_worldpath() .. "/world.mt"):get_bool("generate_structures", true)
local storage = core.get_mod_storage()
local outposts = core.deserialize(storage:get_string("outposts")) or {}
local IRON = "goodluck_golems:iron_golem"

local function id(name, fallback)
	return core.get_content_id(core.registered_nodes[name] and name or fallback)
end
local c = {}
core.register_on_mods_loaded(function()
	c.air = core.get_content_id("air")
	c.log = id("default:pine_tree", "default:tree")
	c.dark = id("default:pine_wood", "default:wood")
	c.light = id("default:aspen_wood", "default:wood")
	c.cobble = id("default:cobble", "default:stone")
	c.mossy = id("default:mossycobble", "default:cobble")
	c.fence = id("default:fence_pine_wood", "default:fence_wood")
	c.ladder = id("default:ladder_wood", "default:ladder_wood")
	c.slab = id("stairs:slab_pine_wood", "default:pine_wood")
	c.chest = id("default:chest", "default:chest")
	c.pumpkin = core.registered_nodes["goodluck_food:pumpkin"] and core.get_content_id("goodluck_food:pumpkin")
end)

-- pillager_outpost's chest: rolls of each pool, {item, min, max, weight}; a tripwire hook is an iron ingot here
local LOOT = {
	{0, 1, {{N .. "crossbow", 1, 1, 1}}},
	{2, 3, {{"farming:wheat", 3, 5, 7}, {"goodluck_food:potato", 2, 5, 5}, {"goodluck_food:carrot", 3, 5, 5}}},
	{1, 3, {{"default:pine_tree", 2, 3, 1}}},
	{2, 3, {{"farming:string", 1, 6, 4}, {"x_bows:arrow_wood", 2, 7, 4}, {"default:steel_ingot", 1, 3, 6},
		{"default:book", 1, 1, 1}}},
}

local function fill(pos, pr)
	local def = core.registered_nodes[core.get_node(pos).name]
	if def and def.on_construct then
		def.on_construct(pos)
	end
	local inv = core.get_meta(pos):get_inventory()
	inv:set_size("main", 8 * 4)
	for _, pool in ipairs(LOOT) do
		local total = 0
		for _, e in ipairs(pool[3]) do
			total = total + e[4]
		end
		for _ = 1, pr:next(pool[1], pool[2]) do
			local r = pr:next(1, total)
			for _, e in ipairs(pool[3]) do
				r = r - e[4]
				if r <= 0 then
					if core.registered_items[e[1]] then
						inv:set_stack("main", pr:next(1, inv:get_size("main")), e[1] .. " " .. pr:next(e[2], e[3]))
					end
					break
				end
			end
		end
	end
end

-- the tower about (x, y, z), y the first free node over the ground: 9 across, floors at 5 and 10, the lookout at 15
-- (11 across, fenced) under a roof at 20; the ladder up the north side inside; the chest in the lookout
local function tower(data, p2, a, x, y, z, pr)
	local function set(dx, dy, dz, cid, param2)
		local i = a:index(x + dx, y + dy, z + dz)
		data[i] = cid
		if param2 then
			p2[i] = param2
		end
	end
	local function solid(i)
		local cid = data[i]
		return cid ~= c.air and cid ~= core.CONTENT_IGNORE and core.registered_nodes[core.get_name_from_content_id(cid)]
			.walkable
	end
	for dx = -5, 5 do
		for dz = -5, 5 do
			-- the ground under the lookout's reach cleared up to the roof, and filled under the tower
			for dy = 0, 22 do
				set(dx, dy, dz, c.air)
			end
			if math.abs(dx) <= 4 and math.abs(dz) <= 4 then
				set(dx, -1, dz, pr:next(1, 4) == 1 and c.mossy or c.cobble)
				for dy = -2, -8, -1 do
					if solid(a:index(x + dx, y + dy, z + dz)) then
						break
					end
					set(dx, dy, dz, c.cobble)
				end
			end
		end
	end
	for _, f in ipairs({5, 10}) do
		for dx = -4, 4 do
			for dz = -4, 4 do
				set(dx, f, dz, c.dark)
				local edge = math.abs(dx) == 4 or math.abs(dz) == 4
				for dy = f + 1, f + 4 do
					local window = dy >= f + 2 and dy <= f + 3 and dz ~= 4 and (math.abs(dx) <= 1 or math.abs(dz) <= 1)
					if edge and not window then
						set(dx, dy, dz, c.light)
					end
				end
			end
		end
	end
	for dx = -5, 5 do
		for dz = -5, 5 do
			set(dx, 15, dz, c.dark)
			if math.abs(dx) == 5 or math.abs(dz) == 5 then
				set(dx, 16, dz, c.fence)
			end
			set(dx, 20, dz, c.slab)
			if math.abs(dx) <= 3 and math.abs(dz) <= 3 then
				set(dx, 21, dz, c.slab)
			end
		end
	end
	for _, s in ipairs({{-5, -5}, {-5, 5}, {5, -5}, {5, 5}}) do
		for dy = 17, 19 do
			set(s[1], dy, s[2], c.fence)
		end
	end
	for _, s in ipairs({{-4, -4}, {-4, 4}, {4, -4}, {4, 4}}) do
		for dy = 0, 15 do
			set(s[1], dy, s[2], c.log)
		end
	end
	-- the ladder on a wall of cobble below the first floor, then on the floors' north walls, through holes in them
	local wall = core.dir_to_wallmounted({x = 0, y = 0, z = 1})
	for dy = 0, 4 do
		for dx = -1, 1 do
			set(dx, dy, 4, c.cobble)
		end
	end
	for dy = 0, 15 do
		set(0, dy, 3, c.ladder, wall)
	end
	set(2, 16, -3, c.chest, 0)
	return {x = x + 2, y = y + 16, z = z - 3}
end

-- a cage of fences under a slab roof, 3 across inside, with an iron golem
local function cage(data, a, x, y, z)
	for dx = -2, 2 do
		for dz = -2, 2 do
			for dy = 0, 3 do
				local edge = math.abs(dx) == 2 or math.abs(dz) == 2
				data[a:index(x + dx, y + dy, z + dz)] = edge and c.fence or c.air
			end
			data[a:index(x + dx, y + 4, z + dz)] = c.slab
		end
	end
end

-- the tower about (x, y, z) in vm, a cage by it half the time and a few pumpkins, then its chest filled, the
-- golem let in and the outpost kept for its pillagers; height(x, z): the ground's y
local function place(vm, emin, emax, x, y, z, pr, height)
	local a = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data, p2 = vm:get_data(), vm:get_param2_data()
	local chest = tower(data, p2, a, x, y, z, pr)
	local golem
	if core.global_exists("goodluck_golems") and pr:next(1, 2) == 1 then
		local side = ({{11, 0}, {-11, 0}, {0, 11}, {0, -11}})[pr:next(1, 4)]
		local gy = (height(x + side[1], z + side[2]) or y - 1) + 1
		cage(data, a, x + side[1], gy, z + side[2])
		golem = {x = x + side[1], y = gy, z = z + side[2]}
	end
	if c.pumpkin then
		for _ = 1, pr:next(1, 3) do
			local px, pz = x + pr:next(-12, 12), z + pr:next(-12, 12)
			local ph = height(px, pz)
			if ph and (math.abs(px - x) > 6 or math.abs(pz - z) > 6) then
				local i = a:index(px, ph + 1, pz)
				if data[i] == c.air then
					data[i] = c.pumpkin
				end
			end
		end
	end
	vm:set_data(data)
	vm:set_param2_data(p2)
	vm:calc_lighting()
	vm:write_to_map()
	fill(chest, pr)
	local pos = {x = x, y = y, z = z}
	outposts[#outposts + 1] = pos
	storage:set_string("outposts", core.serialize(outposts))
	if golem then
		core.after(0, function()
			goodluck_golems.spawn(IRON, golem)
		end)
	end
	core.log("action", "[goodluck_illagers] outpost at " .. core.pos_to_string(pos))
	return pos
end

local function chunk_index(v)
	return math.floor((v - OFFSET) / CHUNK)
end

core.register_on_generated(function(minp, maxp, blockseed)
	if not structures or chunk_index(minp.x) % 2 ~= 1 or chunk_index(minp.z) % 2 ~= 1 then
		return
	end
	local pr = PcgRandom(blockseed)
	if pr:next(1, CHANCE) ~= 1 then
		return
	end
	local x, z = minp.x + CHUNK / 2, minp.z + CHUNK / 2
	local heightmap = core.get_mapgen_object("heightmap")
	local function height(px, pz)
		return heightmap and heightmap[(pz - minp.z) * CHUNK + (px - minp.x) + 1]
	end
	local h = height(x, z)
	if not h or h < math.max(1, minp.y) or h > maxp.y - 24 then
		return
	end
	-- fairly flat ground around it
	for _, d in ipairs({{-6, -6}, {-6, 6}, {6, -6}, {6, 6}, {12, 0}, {-12, 0}, {0, 12}, {0, -12}}) do
		local hd = height(x + d[1], z + d[2])
		if not hd or math.abs(hd - h) > 4 then
			return
		end
	end
	local biome = core.get_biome_data({x = x, y = h, z = z})
	if not biome or not BIOMES[core.get_biome_name(biome.biome)] then
		return
	end
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	if vm then
		place(vm, emin, emax, x, h + 1, z, pr, height)
	end
end)

-- an outpost on the ground under pos, for whoever may run /outpost
function goodluck_illagers.build_outpost(pos)
	local p = vector.round(pos)
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.offset(p, -16, -12, -16), vector.offset(p, 16, 26, 16))
	local function height(px, pz)
		for py = p.y + 8, p.y - 10, -1 do
			local def = core.registered_nodes[core.get_node({x = px, y = py, z = pz}).name]
			if def and def.walkable then
				return py
			end
		end
	end
	local h = height(p.x, p.z) or p.y - 1
	return place(vm, emin, emax, p.x, h + 1, p.z, PcgRandom(math.random(1, 2147483646)), height)
end

core.register_chatcommand("outpost", {
	description = core.translate("goodluck_illagers", "Build a pillager outpost here"),
	privs = {server = true},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false
		end
		goodluck_illagers.build_outpost(player:get_pos())
		return true
	end,
})

-- where a pillager can come in an outpost: a floor of the tower or the lookout, or the ground about it
local SPOTS = {{-3, 3, 0, 0}, {-3, 3, 6, 6}, {-3, 3, 11, 11}, {-4, 4, 16, 16}, {-12, 12, 0, 0}}
local function spot(o)
	local s = SPOTS[math.random(#SPOTS)]
	local p = {x = o.x + math.random(s[1], s[2]), y = o.y + s[3], z = o.z + math.random(s[1], s[2])}
	for dy = 2, -3, -1 do
		local q = vector.offset(p, 0, dy, 0)
		local under = core.get_node_or_nil(vector.offset(q, 0, -1, 0))
		local def = under and core.registered_nodes[under.name]
		local here, above = core.get_node_or_nil(q), core.get_node_or_nil(vector.offset(q, 0, 1, 0))
		local hdef = here and core.registered_nodes[here.name]
		local adef = above and core.registered_nodes[above.name]
		if def and def.walkable and hdef and not hdef.walkable and adef and not adef.walkable then
			return q
		end
	end
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < EVERY or goodluck_illagers.difficulty == 0 then
		return
	end
	timer = 0
	local players = core.get_connected_players()
	for _, o in ipairs(outposts) do
		local near, close = false, false
		for _, player in ipairs(players) do
			local d = vector.distance(player:get_pos(), o)
			near = near or d < AROUND
			close = close or d < MIN_AWAY
		end
		if near and not close then
			local count = 0
			for _, obj in ipairs(core.get_objects_inside_radius(o, 40)) do
				local ent = obj:get_luaentity()
				if ent and ent.name == PILLAGER then
					count = count + 1
				end
			end
			local p = count < CAP and spot(o)
			if p then
				local away = true
				for _, player in ipairs(players) do
					away = away and vector.distance(player:get_pos(), p) >= MIN_AWAY
				end
				if away then
					goodluck_illagers.spawn(PILLAGER, p, {_captain = math.random() < CAPTAIN or nil})
				end
			end
		end
	end
end)

-- the outposts known, for tests and maps
function goodluck_illagers.outposts()
	return outposts
end
