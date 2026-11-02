-- Woodland mansions, Minecraft's rarest building, of our own drawing (Minecraft's are put together from pieces of its
-- own, which aren't free): in the deciduous forest (this game's nearest to the dark forest), one in 10 of the
-- mapchunks villages and outposts leave (index odd one way, even the other), so still rare. Dark wood on a cobblestone
-- footing, three floors under a stepped roof, log pillars and glass panes outside; inside, two halls across each floor
-- and four rooms off them, ladders up the east end: guard rooms with two vindicators, spell rooms with an evoker on a
-- wool circle, libraries, bedrooms, store rooms with chests and a dining room. Its illagers stay (they never despawn,
-- and walk back when they wander 16 out), as Minecraft's do; its chests have woodland_mansion's loot. /mansion builds
-- one
local N = "goodluck_illagers:"
local VINDICATOR, EVOKER = N .. "vindicator", N .. "evoker"
local CHANCE = 10
local BIOMES = {deciduous_forest = true}
local CHUNKSIZE = tonumber(core.get_mapgen_setting("chunksize")) or 5
local CHUNK = 16 * CHUNKSIZE
local OFFSET = -16 * math.floor(CHUNKSIZE / 2)
local structures = Settings(core.get_worldpath() .. "/world.mt"):get_bool("generate_structures", true)
-- half the outside: 31 by 25, floors every 6, the roof from 18
local HX, HZ, STOREY, ROOF = 15, 12, 6, 18
local ROOMS = {"guard", "guard", "guard", "spell", "spell", "library", "library", "bedroom", "bedroom", "storage",
	"storage", "dining"}

local c = {}
core.register_on_mods_loaded(function()
	local function id(name, fallback)
		return core.get_content_id(core.registered_nodes[name] and name or fallback)
	end
	c.air = core.get_content_id("air")
	c.log = id("default:pine_tree", "default:tree")
	c.dark = id("default:pine_wood", "default:wood")
	c.light = id("default:aspen_wood", "default:wood")
	c.cobble = id("default:cobble", "default:stone")
	c.mossy = id("default:mossycobble", "default:cobble")
	c.pane = id("xpanes:pane_flat", "default:glass")
	c.slab = id("stairs:slab_pine_wood", "default:pine_wood")
	c.fence = id("default:fence_pine_wood", "default:fence_wood")
	c.ladder = id("default:ladder_wood", "default:ladder_wood")
	c.shelf = id("default:bookshelf", "default:wood")
	c.chest = id("default:chest", "default:chest")
	c.torch = id("default:torch", "default:torch")
	c.bed_bottom = id("beds:bed_bottom", "default:wood")
	c.bed_top = id("beds:bed_top", "default:wood")
	c.wool_red = id("wool:red", "default:wood")
	c.wool_white = id("wool:white", "default:wood")
	c.wool_gray = id("wool:dark_grey", "default:wood")
	c.stair = id("stairs:stair_pine_wood", "default:pine_wood")
	c.pane_flat = core.registered_nodes["xpanes:pane_flat"] ~= nil
end)

-- woodland_mansion's chest: rolls, {item, min, max, weight}; what this game hasn't (leads, discs, chainmail, resin,
-- the enchanted golden apple yet) is left out
local LOOT = {
	{1, 3, {{"goodluck_horse:golden_apple", 1, 1, 15}, {"farming:hoe_diamond", 1, 1, 15},
		{"3d_armor:chestplate_diamond", 1, 1, 5}, {"default:book", 1, 1, 10}, {"mobs:lasso", 1, 1, 20}}},
	{1, 4, {{"default:steel_ingot", 1, 4, 10}, {"default:gold_ingot", 1, 4, 5}, {"farming:bread", 1, 1, 20},
		{"farming:wheat", 1, 4, 20}, {"bucket:bucket_empty", 1, 1, 10}, {"goodluck_redstone:redstone", 1, 4, 15},
		{"default:coal_lump", 1, 4, 15}, {"goodluck_food:melon_seeds", 2, 4, 10},
		{"goodluck_food:pumpkin_seeds", 2, 4, 10}, {"goodluck_food:beetroot_seeds", 2, 4, 10}}},
	{3, 3, {{"goodluck_monsters:bone", 1, 8, 10}, {"tnt:gunpowder", 1, 8, 10},
		{"goodluck_monsters:rotten_flesh", 1, 8, 10}, {"farming:string", 1, 8, 10}}},
}

local function fill(pos, pr)
	local def = core.registered_nodes[core.get_node(pos).name]
	if def and def.on_construct then
		def.on_construct(pos)
	end
	local inv = core.get_meta(pos):get_inventory()
	inv:set_size("main", 8 * 4)
	for _, pool in ipairs(LOOT) do
		local items, total = {}, 0
		for _, e in ipairs(pool[3]) do
			if core.registered_items[e[1]] then
				items[#items + 1] = e
				total = total + e[4]
			end
		end
		for _ = 1, total > 0 and pr:next(pool[1], pool[2]) or 0 do
			local r = pr:next(1, total)
			for _, e in ipairs(items) do
				r = r - e[4]
				if r <= 0 then
					inv:set_stack("main", pr:next(1, 32), e[1] .. " " .. pr:next(e[2], e[3]))
					break
				end
			end
		end
	end
end

-- the building about (x, y, z), y the first free node over the ground; what it fills in and where its illagers go
local function build(data, p2, a, x, y, z, pr)
	local chests, spawns = {}, {}
	local function set(dx, dy, dz, cid, param2)
		local i = a:index(x + dx, y + dy, z + dz)
		data[i] = cid
		if param2 then
			p2[i] = param2
		end
	end
	local function solid(dx, dy, dz)
		local cid = data[a:index(x + dx, y + dy, z + dz)]
		if cid == c.air or cid == core.CONTENT_IGNORE then
			return false
		end
		local def = core.registered_nodes[core.get_name_from_content_id(cid)]
		return def and def.walkable and not def.groups.leaves and not def.groups.tree
	end
	-- the ground cleared over it (trees too) and filled under it
	for dx = -HX - 1, HX + 1 do
		for dz = -HZ - 1, HZ + 1 do
			for dy = 0, ROOF + 14 do
				set(dx, dy, dz, c.air)
			end
			if math.abs(dx) <= HX and math.abs(dz) <= HZ then
				for dy = -1, -10, -1 do
					if dy < -1 and solid(dx, dy, dz) then
						break
					end
					set(dx, dy, dz, pr:next(1, 5) == 1 and c.mossy or c.cobble)
				end
			end
		end
	end
	for storey = 0, 2 do
		local base = storey * STOREY
		for dx = -HX, HX do
			for dz = -HZ, HZ do
				local edge = math.abs(dx) == HX or math.abs(dz) == HZ
				-- the floor: dark boards on the ground floor, light ones above, cobble round the edge
				set(dx, base, dz, edge and c.cobble or storey == 0 and c.dark or c.light)
				for dy = base + 1, base + STOREY - 1 do
					if edge then
						-- logs every 6 (x -15, -9 ... 15 along the front and back, z -12, -6 ... 12 along the
						-- sides), a pane between each two
						local front, side = math.abs(dz) == HZ, math.abs(dx) == HX
						local pillar = front and dx % 6 == 3 or side and dz % 6 == 0
						local window = not pillar and (dy == base + 2 or dy == base + 3) and
							(front and dx % 6 == 0 or side and dz % 6 == 3)
						if pillar then
							set(dx, dy, dz, c.log)
						elseif window then
							set(dx, dy, dz, c.pane, c.pane_flat and (math.abs(dz) == HZ and 0 or 1) or nil)
						elseif storey == 0 and dy == base + 1 then
							set(dx, dy, dz, c.cobble)
						else
							set(dx, dy, dz, c.dark)
						end
					end
				end
			end
		end
		-- the halls across (|z| <= 1 and |x| <= 1) and the room walls along them, doorways in the middle of each
		for d = -HX + 1, HX - 1 do
			for dy = base + 1, base + STOREY - 1 do
				for _, wz in ipairs({-2, 2}) do
					local door = (d == -8 or d == 8) and dy <= base + 2
					if math.abs(d) > 1 and not door then
						set(d, dy, wz, c.light)
					end
				end
			end
		end
		for d = -HZ + 1, HZ - 1 do
			for dy = base + 1, base + STOREY - 1 do
				for _, wx in ipairs({-2, 2}) do
					local door = (d == -7 or d == 7) and dy <= base + 2
					if math.abs(d) > 2 and not door then
						set(wx, dy, d, c.light)
					end
				end
			end
		end
		-- torches down the halls
		for _, tx in ipairs({-12, -6, 6, 12}) do
			set(tx, base + 1, 1, c.torch, 1)
		end
	end
	-- the ladder up the east end of the long hall, through both upper floors, and the way in at the front
	local wall = core.dir_to_wallmounted({x = 1, y = 0, z = 0})
	for dy = 1, 2 * STOREY + 1 do
		set(HX - 1, dy, 0, c.ladder, wall)
	end
	for dx = -1, 1 do
		for dy = 1, 3 do
			set(dx, dy, -HZ, c.air)
		end
	end
	-- the roof: rings of dark wood, each one in and one up, slabs on top
	for k = 0, HZ + 1 do
		local rx, rz = HX + 1 - k, HZ + 1 - k
		if rz < 0 then
			break
		end
		for dx = -rx, rx do
			for dz = -rz, rz do
				if math.abs(dx) == rx or math.abs(dz) == rz or rz == 0 then
					set(dx, ROOF + k, dz, rz == 0 and c.slab or c.dark)
				end
			end
		end
	end
	-- the rooms: four a floor (x 3..14 or -14..-3, z 3..11 or -11..-3), each a kind drawn from ROOMS
	local kinds = table.copy(ROOMS)
	for i = #kinds, 2, -1 do
		local j = pr:next(1, i)
		kinds[i], kinds[j] = kinds[j], kinds[i]
	end
	local n = 0
	for storey = 0, 2 do
		local base = storey * STOREY
		for _, q in ipairs({{1, 1}, {-1, 1}, {1, -1}, {-1, -1}}) do
			n = n + 1
			local kind = kinds[n]
			local sx, sz = q[1], q[2]
			local x0, x1 = sx > 0 and 3 or -14, sx > 0 and 14 or -3
			local z0, z1 = sz > 0 and 3 or -11, sz > 0 and 11 or -3
			local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
			local outer = sz * (HZ - 1)
			if kind == "library" then
				for dx = x0, x1 do
					for dy = base + 1, base + 3 do
						set(dx, dy, outer, c.shelf)
					end
				end
				set(math.floor(mx), base + 1, math.floor(mz), c.fence)
				set(math.floor(mx), base + 2, math.floor(mz), c.slab)
			elseif kind == "bedroom" then
				local bx = sx > 0 and x1 - 1 or x0 + 1
				set(bx, base + 1, outer, c.bed_top, sz > 0 and 0 or 2)
				set(bx, base + 1, outer - sz, c.bed_bottom, sz > 0 and 0 or 2)
				set(bx - sx * 2, base + 1, outer, c.chest, sz > 0 and 2 or 0)
				chests[#chests + 1] = {x = x + bx - sx * 2, y = y + base + 1, z = z + outer}
				for dx = x0, x1 do
					for dz = z0, z1 do
						if data[a:index(x + dx, y + base + 1, z + dz)] == c.air and (dx + dz) % 2 == 0 then
							set(dx, base, dz, c.wool_red)
						end
					end
				end
			elseif kind == "storage" then
				for k = 0, 2 do
					local cx = math.floor(mx) - 2 + k * 2
					set(cx, base + 1, outer, c.chest, sz > 0 and 2 or 0)
					chests[#chests + 1] = {x = x + cx, y = y + base + 1, z = z + outer}
				end
			elseif kind == "dining" then
				for dx = x0 + 2, x1 - 2 do
					set(dx, base + 1, math.floor(mz), c.fence)
					set(dx, base + 2, math.floor(mz), c.slab)
				end
			elseif kind == "spell" then
				for dx = x0, x1 do
					for dz = z0, z1 do
						local r = math.sqrt((dx - mx) ^ 2 + (dz - mz) ^ 2)
						if r < 3.5 then
							set(dx, base, dz, r > 2.5 and c.wool_white or c.wool_gray)
						end
					end
				end
				spawns[#spawns + 1] = {EVOKER, {x = x + math.floor(mx), y = y + base + 1, z = z + math.floor(mz)}}
			elseif kind == "guard" then
				for k = -1, 1, 2 do
					spawns[#spawns + 1] = {VINDICATOR, {x = x + math.floor(mx) + k * 2, y = y + base + 1,
						z = z + math.floor(mz)}}
				end
			end
			set(sx > 0 and x0 or x1, base + 1, sz > 0 and z1 or z0, c.torch, 1)
		end
	end
	return chests, spawns
end

-- the building in vm, then its chests filled and its illagers let in
local function place(vm, emin, emax, x, y, z, pr)
	local a = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data, p2 = vm:get_data(), vm:get_param2_data()
	local chests, spawns = build(data, p2, a, x, y, z, pr)
	vm:set_data(data)
	vm:set_param2_data(p2)
	vm:calc_lighting()
	vm:write_to_map()
	for _, pos in ipairs(chests) do
		fill(pos, pr)
	end
	local center = {x = x, y = y, z = z}
	core.after(0, function()
		for _, s in ipairs(spawns) do
			goodluck_illagers.spawn(s[1], s[2], {lifetimer = 20000, _mansion = center})
		end
	end)
	core.log("action", ("[goodluck_illagers] woodland mansion at %s, %d illagers"):format(core.pos_to_string(center),
		#spawns))
	return center
end

local function chunk_index(v)
	return math.floor((v - OFFSET) / CHUNK)
end

core.register_on_generated(function(minp, maxp, blockseed)
	if not structures or (chunk_index(minp.x) + chunk_index(minp.z)) % 2 ~= 1 then
		return
	end
	local pr = PcgRandom(blockseed + 7)
	if pr:next(1, CHANCE) ~= 1 then
		return
	end
	local x, z = minp.x + CHUNK / 2, minp.z + CHUNK / 2
	local heightmap = core.get_mapgen_object("heightmap")
	local function height(px, pz)
		return heightmap and heightmap[(pz - minp.z) * CHUNK + (px - minp.x) + 1]
	end
	local h = height(x, z)
	if not h or h < math.max(2, minp.y) or h > maxp.y - (ROOF + HZ + 3) then
		return
	end
	for _, d in ipairs({{-HX, -HZ}, {-HX, HZ}, {HX, -HZ}, {HX, HZ}}) do
		local hd = height(x + d[1], z + d[2])
		if not hd or math.abs(hd - h) > 6 then
			return
		end
	end
	local biome = core.get_biome_data({x = x, y = h, z = z})
	if not biome or not BIOMES[core.get_biome_name(biome.biome)] then
		return
	end
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	if vm then
		place(vm, emin, emax, x, h + 1, z, pr)
	end
end)

-- a mansion on the ground under pos, for whoever may run /mansion
function goodluck_illagers.build_mansion(pos)
	local p = vector.round(pos)
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(vector.offset(p, -HX - 2, -12, -HZ - 2), vector.offset(p, HX + 2, ROOF + HZ + 4,
		HZ + 2))
	local y = p.y
	for py = p.y + 8, p.y - 10, -1 do
		local def = core.registered_nodes[core.get_node({x = p.x, y = py, z = p.z}).name]
		if def and def.walkable and not def.groups.leaves and not def.groups.tree then
			y = py + 1
			break
		end
	end
	return place(vm, emin, emax, p.x, y, p.z, PcgRandom(math.random(1, 2147483646)))
end

core.register_chatcommand("mansion", {
	description = core.translate("goodluck_illagers", "Build a woodland mansion here"),
	privs = {server = true},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false
		end
		goodluck_illagers.build_mansion(player:get_pos())
		return true
	end,
})
