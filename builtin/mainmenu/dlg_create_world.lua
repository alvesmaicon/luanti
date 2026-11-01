-- Luanti
-- Copyright (C) 2014 sapier
-- SPDX-License-Identifier: LGPL-2.1-or-later

local function table_to_flags(ftable)
	-- Convert e.g. { jungles = true, caves = false } to "jungles,nocaves"
	local str = {}
	for flag, is_set in pairs(ftable) do
		str[#str + 1] = is_set and flag or ("no" .. flag)
	end
	return table.concat(str, ",")
end

-- Same as check_flag but returns a string
local function strflag(flags, flag)
	return (flags[flag] == true) and "true" or "false"
end

local cb_caverns = { "caverns", fgettext("Caverns"),
	fgettext("Very large caverns deep in the underground") }

local flag_checkboxes = {
	v5 = {
		cb_caverns,
	},
	v7 = {
		cb_caverns,
		{ "ridges", fgettext("Rivers"), fgettext("Sea level rivers") },
		{ "mountains", fgettext("Mountains") },
		{ "floatlands", fgettext("Floatlands (experimental)"),
		fgettext("Floating landmasses in the sky") },
	},
	carpathian = {
		cb_caverns,
		{ "rivers", fgettext("Rivers"), fgettext("Sea level rivers") },
	},
	valleys = {
		{ "altitude_chill", fgettext("Altitude chill"),
		fgettext("Reduces heat with altitude") },
		{ "altitude_dry", fgettext("Altitude dry"),
		fgettext("Reduces humidity with altitude") },
		{ "humid_rivers", fgettext("Humid rivers"),
		fgettext("Increases humidity around rivers") },
		{ "vary_river_depth", fgettext("Vary river depth"),
		fgettext("Low humidity and high heat causes shallow or dry rivers") },
	},
	flat = {
		cb_caverns,
		{ "hills", fgettext("Hills") },
		{ "lakes", fgettext("Lakes") },
	},
	fractal = {
		{ "terrain", fgettext("Additional terrain"),
		fgettext("Generate non-fractal terrain: Oceans and underground") },
	},
	v6 = {
		{ "trees", fgettext("Trees and jungle grass") },
		{ "flat", fgettext("Flat terrain") },
		{ "mudflow", fgettext("Mud flow"), fgettext("Terrain surface erosion") },
		{ "temples", fgettext("Desert temples"),
		fgettext("Different dungeon variant generated in desert biomes (only if dungeons enabled)") },
		-- Biome settings are in mgv6_biomes below
	},
}

local mgv6_biomes = {
	{
		fgettext("Temperate, Desert, Jungle, Tundra, Taiga"),
		{jungles = true, snowbiomes = true}
	},
	{
		fgettext("Temperate, Desert, Jungle"),
		{jungles = true, snowbiomes = false}
	},
	{
		fgettext("Temperate, Desert"),
		{jungles = false, snowbiomes = false}
	},
}

-- The handheld's dialog, as Minecraft's: a Game, a World and a More tab over Create and Cancel, and the world type's
-- options on a page of their own. Its choices go to world.mt, and the rules that other mods read as settings go there
-- as "setting.<name>" too (builtin/game/world_settings.lua)
local WORLD_TYPES = {
	{"default", fgettext_ne("Default"), "v7"},
	{"flat", fgettext_ne("Superflat"), "flat"},
	{"large_biomes", fgettext_ne("Large biomes"), "v7"},
	{"amplified", fgettext_ne("Amplified"), "v7"},
	{"single_biome", fgettext_ne("Single biome"), "v7"},
	{"valleys", fgettext_ne("Valleys"), "valleys"},
	{"carpathian", fgettext_ne("Carpathian"), "carpathian"},
}
-- Minecraft's Large Biomes are four times as wide; Amplified has its seas as Default, and higher hills and more and
-- higher mountains over them
local TYPE_SETTINGS = {
	large_biomes = {
		mg_biome_np_heat = "50, 50, (4000, 4000, 4000), 5349, 3, 0.5, 2.0",
		mg_biome_np_humidity = "50, 50, (4000, 4000, 4000), 842, 3, 0.5, 2.0",
	},
	amplified = {
		mgv7_np_terrain_base = "12, 100, (600, 600, 600), 82341, 5, 0.6, 2.0",
		mgv7_np_terrain_alt = "8, 40, (600, 600, 600), 5934, 5, 0.6, 2.0",
		mgv7_np_mount_height = "384, 150, (1000, 1000, 1000), 72449, 3, 0.6, 2.0",
		mgv7_np_mountain = "-0.5, 1, (250, 350, 250), 5333, 5, 0.63, 2.0",
	},
}
-- Minetest Game's biomes and their heat and humidity, which their shores, oceans and underground share: a Single Biome
-- world has those everywhere, so that it is always the nearest
local BIOMES = {
	{"grassland", fgettext_ne("Grassland"), 50, 35},
	{"deciduous_forest", fgettext_ne("Deciduous forest"), 60, 68},
	{"coniferous_forest", fgettext_ne("Coniferous forest"), 45, 70},
	{"taiga", fgettext_ne("Taiga"), 25, 70},
	{"snowy_grassland", fgettext_ne("Snowy grassland"), 20, 35},
	{"tundra", fgettext_ne("Tundra"), 0, 40},
	{"icesheet", fgettext_ne("Ice sheet"), 0, 73},
	{"desert", fgettext_ne("Desert"), 92, 16},
	{"sandstone_desert", fgettext_ne("Sandstone desert"), 60, 0},
	{"cold_desert", fgettext_ne("Cold desert"), 40, 0},
	{"savanna", fgettext_ne("Savanna"), 89, 42},
	{"rainforest", fgettext_ne("Rainforest"), 86, 65},
}
-- each level's settings for the mods: Easy halves the monsters' health and damage, Hard adds half
local DIFFICULTIES = {
	{"peaceful", fgettext_ne("Peaceful"), {only_peaceful_mobs = "true"}},
	{"easy", fgettext_ne("Easy"), {mob_difficulty = "0.5"}},
	{"normal", fgettext_ne("Normal"), {}},
	{"hard", fgettext_ne("Hard"), {mob_difficulty = "1.5"}},
}
-- Minecraft's game rules: the setting a rule sets when it isn't as by default (none: the game's mods read it)
local RULES = {
	{"keep_inventory", fgettext_ne("Keep inventory after death"), false, "bones_mode", "keep"},
	{"daylight_cycle", fgettext_ne("Daylight cycle"), true, "time_speed", "0"},
	{"mob_spawning", fgettext_ne("Mobs spawn"), true, "mobs_spawn", "false"},
	{"fire_spread", fgettext_ne("Fire spreads"), true, "enable_fire", "false"},
	{"mob_griefing", fgettext_ne("Mobs change blocks"), true, "mobs_griefing", "false"},
	{"natural_regeneration", fgettext_ne("Natural regeneration"), true},
}

local function find(list, key)
	for i, entry in ipairs(list) do
		if entry[1] == key then
			return i, entry
		end
	end
	return 1, list[1]
end

-- a label on the left and a switch on the right, the whole row its button: "On" and "Off" didn't fit in every
-- language
local function switch_row(y, name, label, value, x, w)
	x, w = x or 3.75, w or 8
	local sx = x + w - 1.3
	return ("label[%g,%g;%s]box[%g,%g;1.3,0.62;%s]box[%g,%g;1.2,0.52;%s]box[%g,%g;0.42,0.42;%s]"):format(x, y + 0.4,
			label, sx, y + 0.09, value and "#6CC46CFF" or "#808080FF", sx + 0.05, y + 0.14,
			value and "#3A873AFF" or "#1E1E1EFF", value and sx + 0.78 or sx + 0.1, y + 0.19,
			value and "#FFFFFFFF" or "#9A9A9AFF") ..
			("style[%s;border=false]button[%g,%g;%g,0.8;%s;]"):format(name, x, y, w, name)
end

-- the switches in two columns, under the single biome's button
local function handheld_customize(data)
	local _, wtype = find(WORLD_TYPES, data.world_type)
	local mg = wtype[3]
	local fs = {
		("label[1,0.5;%s]"):format(fgettext("Customize: $1", wtype[2])),
	}
	local y = 1
	if data.world_type == "single_biome" then
		local _, biome = find(BIOMES, data.biome)
		fs[#fs + 1] = ("button[1,%g;6.5,0.8;btn_biome;%s]"):format(y, fgettext("Biome: $1", biome[2]))
		y = y + 1
	end
	local switches = {
		{"flag_main_caves", fgettext("Caves"), data.flags.main.caves},
		{"flag_main_decorations", fgettext("Decorations"), data.flags.main.decorations},
		{"flag_main_dungeons", fgettext("Dungeons"), data.flags.main.dungeons},
	}
	for _, tab in ipairs(flag_checkboxes[mg] or {}) do
		switches[#switches + 1] = {"flag_" .. mg .. "_" .. tab[1]:gsub("_", "-"), tab[2], data.flags[mg][tab[1]]}
	end
	local rows = math.ceil(#switches / 2)
	for i, sw in ipairs(switches) do
		local col, row = math.floor((i - 1) / rows), (i - 1) % rows
		fs[#fs + 1] = switch_row(y + row * 0.85, sw[1], sw[2], sw[3], 1 + col * 7.5, 6.5)
	end
	fs[#fs + 1] = "button[5,6.1;5.5,0.8;btn_customize_done;" .. fgettext("Done") .. "]"
	return table.concat(fs)
end

local function handheld_formspec(data)
	-- the tabs on the page's top edge, as the main menu's
	local fs = {"formspec_version[6]size[15.5,7.1]"}
	if data.page == "customize" then
		return table.concat(fs) .. handheld_customize(data)
	end
	fs[#fs + 1] = ("tabheader[0,0;15.5,0.85;dlg_tab;%s,%s,%s;%d;true;false]"):format(fgettext("Game"),
			fgettext("World"), fgettext("More"), data.tab)
	if data.tab == 1 then
		local _, difficulty = find(DIFFICULTIES, data.difficulty)
		fs[#fs + 1] = ("field[3.75,0.9;8,0.8;te_world_name;%s;%s]"):format(fgettext("World name"),
				core.formspec_escape(data.worldname))
		fs[#fs + 1] = ("button[3.75,2.1;8,0.8;btn_game_mode;%s]"):format(fgettext("Game mode: $1",
				fgettext_ne(data.creative and "Creative" or "Survival")))
		fs[#fs + 1] = ("button[3.75,3.1;8,0.8;btn_difficulty;%s]"):format(fgettext("Difficulty: $1", difficulty[2]))
		fs[#fs + 1] = switch_row(4.1, "btn_mode_change", fgettext("Allow changing the game mode"), data.mode_change)
	elseif data.tab == 2 then
		local _, wtype = find(WORLD_TYPES, data.world_type)
		fs[#fs + 1] = ("button[3.75,0.5;5,0.8;btn_world_type;%s]"):format(fgettext("World type: $1", wtype[2]))
		fs[#fs + 1] = "button[8.85,0.5;2.9,0.8;btn_customize;" .. fgettext("Customize") .. "]"
		fs[#fs + 1] = ("field[3.75,2.1;8,0.8;te_seed;%s;%s]"):format(fgettext("Seed for the world generator"),
				core.formspec_escape(data.seed))
		fs[#fs + 1] = "label[3.75,3.15;" .. fgettext("Leave blank for a random seed") .. "]"
		fs[#fs + 1] = switch_row(3.6, "btn_structures", fgettext("Generate structures"), data.structures)
		fs[#fs + 1] = switch_row(4.45, "btn_bonus_chest", fgettext("Bonus chest"), data.bonus_chest)
	else
		for i, rule in ipairs(RULES) do
			fs[#fs + 1] = switch_row(0.3 + (i - 1) * 0.85, "btn_rule_" .. rule[1], core.formspec_escape(rule[2]),
					data.rules[rule[1]])
		end
	end
	fs[#fs + 1] = "button[1.75,6.1;5.75,0.8;world_create_confirm;" .. fgettext("Create new world") .. "]"
	fs[#fs + 1] = "button[8,6.1;5.75,0.8;world_create_cancel;" .. fgettext("Cancel") .. "]"
	return table.concat(fs)
end

-- the next entry of a list, after the last the first
local function next_of(list, key)
	local i = find(list, key)
	return list[i % #list + 1][1]
end

-- all but Create, which the name and seed of a tab not shown don't reach
local function handheld_fields(this, fields)
	local data = this.data
	data.worldname = fields.te_world_name or data.worldname
	data.seed = fields.te_seed or data.seed
	if fields.world_create_cancel then
		this:delete()
		return true
	elseif fields.btn_game_mode then
		data.creative = not data.creative
		return true
	elseif fields.dlg_tab then
		data.tab = tonumber(fields.dlg_tab) or 1
		return true
	elseif fields.btn_difficulty then
		data.difficulty = next_of(DIFFICULTIES, data.difficulty)
		return true
	elseif fields.btn_mode_change then
		data.mode_change = not data.mode_change
		return true
	elseif fields.btn_world_type then
		data.world_type = next_of(WORLD_TYPES, data.world_type)
		return true
	elseif fields.btn_customize then
		data.page = "customize"
		return true
	elseif fields.btn_customize_done then
		data.page = nil
		return true
	elseif fields.btn_biome then
		data.biome = next_of(BIOMES, data.biome)
		return true
	elseif fields.btn_structures then
		data.structures = not data.structures
		return true
	elseif fields.btn_bonus_chest then
		data.bonus_chest = not data.bonus_chest
		return true
	end
	for _, rule in ipairs(RULES) do
		if fields["btn_rule_" .. rule[1]] then
			data.rules[rule[1]] = not data.rules[rule[1]]
			return true
		end
	end
	for key in pairs(fields) do
		-- a switch of the Customize page: flag_<group>_<flag with dashes>
		local group, flag = key:match("^flag_([^_]+)_(.+)$")
		if group and data.flags[group] then
			flag = flag:gsub("-", "_")
			data.flags[group][flag] = not data.flags[group][flag]
			return true
		end
	end
	return false
end

-- what the handheld's choices add to the world's creation: the mapgen settings, and world.mt's lines
local function handheld_settings(data, settings)
	local _, wtype = find(WORLD_TYPES, data.world_type)
	settings.mg_name = wtype[3]
	for key, value in pairs(TYPE_SETTINGS[data.world_type] or {}) do
		settings[key] = value
	end
	if data.world_type == "single_biome" then
		local _, biome = find(BIOMES, data.biome)
		settings.mg_biome_np_heat = ("%d, 0, (1000, 1000, 1000), 5349, 1, 0.5, 2.0"):format(biome[3])
		settings.mg_biome_np_humidity = ("%d, 0, (1000, 1000, 1000), 842, 1, 0.5, 2.0"):format(biome[4])
		settings.mg_biome_np_heat_blend = "0, 0, (8, 8, 8), 13, 1, 1.0, 2.0"
		settings.mg_biome_np_humidity_blend = "0, 0, (8, 8, 8), 90003, 1, 1.0, 2.0"
	end
	settings.mg_flags = table_to_flags(data.flags.main)
	settings["mg" .. wtype[3] .. "_spflags"] = table_to_flags(data.flags[wtype[3]])
end

local function handheld_world_mt(data, conf)
	-- on top of the world list, which shows the latest played first
	conf:set("last_played", tostring(os.time()))
	conf:set("world_type", data.world_type)
	if data.world_type == "single_biome" then
		conf:set("single_biome", data.biome)
	end
	conf:set_bool("generate_structures", data.structures)
	conf:set("difficulty", data.difficulty)
	local _, difficulty = find(DIFFICULTIES, data.difficulty)
	for name, value in pairs(difficulty[3]) do
		conf:set("setting." .. name, value)
	end
	for _, rule in ipairs(RULES) do
		local on = data.rules[rule[1]]
		conf:set_bool(rule[1], on)
		if rule[4] and on ~= rule[3] then
			conf:set("setting." .. rule[4], rule[5])
		end
	end
end

-- meta: the world's map_meta.txt, whose flags the Customize page shows
local function handheld_from_world(data, conf, meta)
	for group, ftable in pairs(data.flags) do
		local key = group == "main" and "mg_flags" or "mg" .. group .. "_spflags"
		for flag in (meta:get(key) or ""):gmatch("[^,%s]+") do
			local off = flag:match("^no(.+)$")
			if off and ftable[off] ~= nil then
				ftable[off] = false
			elseif ftable[flag] ~= nil then
				ftable[flag] = true
			end
		end
	end
	data.world_type = conf:get("world_type") or data.world_type
	data.biome = conf:get("single_biome") or data.biome
	data.structures = conf:get_bool("generate_structures", data.structures)
	data.difficulty = conf:get("difficulty") or data.difficulty
	for _, rule in ipairs(RULES) do
		data.rules[rule[1]] = conf:get_bool(rule[1], rule[3])
	end
end

local function create_world_formspec(dialogdata)

	local current_mg = dialogdata.mg
	local mapgens = core.get_mapgen_names()

	local flags = dialogdata.flags

	local game = pkgmgr.find_by_gameid(core.settings:get("menu_last_game"))
	if game == nil then
		-- should never happen but just pick the first game
		game = pkgmgr.games[1]
		core.settings:set("menu_last_game", game.id)
	end

	local disallowed_mapgen_settings = {}
	if game ~= nil then
		local gameconfig = Settings(game.path.."/game.conf")

		current_mg = current_mg or gameconfig:get("default_mapgen") or core.settings:get("mg_name")

		local allowed_mapgens = (gameconfig:get("allowed_mapgens") or ""):split()
		for key, value in pairs(allowed_mapgens) do
			allowed_mapgens[key] = value:trim()
		end

		local disallowed_mapgens = (gameconfig:get("disallowed_mapgens") or ""):split()
		for key, value in pairs(disallowed_mapgens) do
			disallowed_mapgens[key] = value:trim()
		end

		if #allowed_mapgens > 0 then
			for i = #mapgens, 1, -1 do
				if table.indexof(allowed_mapgens, mapgens[i]) == -1 then
					table.remove(mapgens, i)
				end
			end
		end

		if #disallowed_mapgens > 0 then
			for i = #mapgens, 1, -1 do
				if table.indexof(disallowed_mapgens, mapgens[i]) > 0 then
					table.remove(mapgens, i)
				end
			end
		end

		local ds = (gameconfig:get("disallowed_mapgen_settings") or ""):split()
		for _, value in pairs(ds) do
			disallowed_mapgen_settings[value:trim()] = true
		end
	end

	local mglist = ""
	local selindex
	do -- build the list of mapgens
		local i = 1
		local first_mg
		for k, v in pairs(mapgens) do
			if not first_mg then
				first_mg = v
			end
			if current_mg == v then
				selindex = i
			end
			i = i + 1
			mglist = mglist .. core.formspec_escape(v) .. ","
		end
		if not selindex then
			selindex = 1
			current_mg = first_mg
		end
		mglist = mglist:sub(1, -2)
	end

	-- one button that shows the mode and switches it, as in Minecraft
	local game_mode = function(x, y, w)
		return ("button[%g,%g;%g,0.5;btn_game_mode;%s]"):format(x, y, w,
				fgettext("Game mode: $1", fgettext_ne(dialogdata.creative and "Creative" or "Survival"))) ..
			("checkbox[%g,%g;cb_mode_change;%s;%s]"):format(x, y + 0.7,
				fgettext("Allow changing the game mode"), tostring(dialogdata.mode_change)) ..
			("checkbox[%g,%g;cb_bonus_chest;%s;%s]"):format(x, y + 1.25,
				fgettext("Bonus chest"), tostring(dialogdata.bonus_chest))
	end

	if core.settings:get_bool("menu_handheld") then
		return handheld_formspec(dialogdata)
	end

	-- The logic of the flag element IDs is as follows:
	-- "flag_main_foo-bar-baz" controls dialogdata.flags["main"]["foo_bar_baz"]
	-- see the buttonhandler for the implementation of this

	local mg_main_flags = function(mapgen, y)
		if mapgen == "singlenode" then
			return "", y
		end
		if disallowed_mapgen_settings["mg_flags"] then
			return "", y
		end

		local form = "checkbox[0," .. y .. ";flag_main_caves;" ..
			fgettext("Caves") .. ";"..strflag(flags.main, "caves").."]"
		y = y + 0.5

		form = form .. "checkbox[0,"..y..";flag_main_dungeons;" ..
			fgettext("Dungeons") .. ";"..strflag(flags.main, "dungeons").."]"
		y = y + 0.5

		-- TRANSLATORS: Map generator decorations (used for structures, trees, plants, and more)
		local d_name = fgettext("Decorations")
		local d_tt
		if mapgen == "v6" then
			d_tt = fgettext("Structures appearing on the terrain (no effect on trees and jungle grass created by v6)")
		else
			d_tt = fgettext("Structures appearing on the terrain, typically trees and plants")
		end
		form = form .. "checkbox[0,"..y..";flag_main_decorations;" ..
			d_name .. ";" ..
			strflag(flags.main, "decorations").."]" ..
			"tooltip[flag_mg_decorations;" ..
			d_tt ..
			"]"
		y = y + 0.5

		form = form .. "tooltip[flag_main_caves;" ..
		fgettext("Network of tunnels and caves")
		.. "]"
		return form, y
	end

	local mg_specific_flags = function(mapgen, y)
		if not flag_checkboxes[mapgen] then
			return "", y
		end
		if disallowed_mapgen_settings["mg"..mapgen.."_spflags"] then
			return "", y
		end
		local form = ""
		for _, tab in pairs(flag_checkboxes[mapgen]) do
			local id = "flag_"..mapgen.."_"..tab[1]:gsub("_", "-")
			form = form .. ("checkbox[0,%f;%s;%s;%s]"):
				format(y, id, tab[2], strflag(flags[mapgen], tab[1]))

			if tab[3] then
				form = form .. "tooltip["..id..";"..tab[3].."]"
			end
			y = y + 0.5
		end

		if mapgen ~= "v6" then
			-- No special treatment
			return form, y
		end
		-- Special treatment for v6 (add biome widgets)

		-- Biome type (jungles, snowbiomes)
		local biometype
		if flags.v6.snowbiomes == true then
			biometype = 1
		elseif flags.v6.jungles == true  then
			biometype = 2
		else
			biometype = 3
		end
		y = y + 0.3

		form = form .. "label[0,"..(y+0.1)..";" .. fgettext("Biomes") .. "]"
		y = y + 0.6

		form = form .. "dropdown[0,"..y..";6.3;mgv6_biomes;"
		for b=1, #mgv6_biomes do
			form = form .. mgv6_biomes[b][1]
			if b < #mgv6_biomes then
				form = form .. ","
			end
		end
		form = form .. ";" .. biometype.. "]"

		-- biomeblend
		y = y + 0.55
		form = form .. "checkbox[0,"..y..";flag_v6_biomeblend;" ..
			-- TRANSLATORS: Smooth transition between biomes
			fgettext("Biome blending") .. ";"..strflag(flags.v6, "biomeblend").."]" ..
			"tooltip[flag_v6_biomeblend;" ..
			fgettext("Smooth transition between biomes") .. "]"

		return form, y
	end

	local y_start = 0.0
	local y = y_start
	local str_flags, str_spflags
	local label_flags, label_spflags = "", ""
	y = y + 0.3
	str_flags, y = mg_main_flags(current_mg, y)
	if str_flags ~= "" then
		label_flags = "label[0,"..y_start..";" .. fgettext("Mapgen flags") .. "]"
		y_start = y + 0.4
	else
		y_start = 0.0
	end
	y = y_start + 0.3
	str_spflags = mg_specific_flags(current_mg, y)
	if str_spflags ~= "" then
		label_spflags = "label[0,"..y_start..";" .. fgettext("Mapgen-specific flags") .. "]"
	end

	local retval =
		"size[12.25,7.4,true]" ..

		-- Left side
		"container[0,0]"..
		"field[0.3,0.6;6,0.5;te_world_name;" ..
		fgettext("World name") ..
		";" .. core.formspec_escape(dialogdata.worldname) .. "]" ..
		"set_focus[te_world_name;false]"

	if not disallowed_mapgen_settings["seed"] then

		retval = retval .. "field[0.3,1.7;6,0.5;te_seed;" ..
				-- TRANSLATORS: Value for randomness
				fgettext("Seed") ..
				";".. core.formspec_escape(dialogdata.seed) .. "]"

	end

	retval = retval ..
		"label[0,2;" .. fgettext("Mapgen") .. "]"..
		"dropdown[0,2.5;6.3;dd_mapgen;" .. mglist .. ";" .. selindex .. "]" ..
		game_mode(0, 3.4, 6)

	-- Warning when making a devtest world
	if game.id == "devtest" then
		retval = retval ..
			"container[0,5]" ..
			"box[0,0;5.8,1.7;#ff8800]" ..
			"textarea[0.4,0.1;6,1.8;;;"..
			fgettext("Development Test is meant for developers.") .. "]" ..
			"button[1,1;4,0.5;world_create_open_cdb;" .. fgettext("Install another game") .. "]" ..
			"container_end[]"
	end

	retval = retval ..
		"container_end[]" ..

		-- Right side
		"container[6.2,0]"..
		label_flags .. str_flags ..
		label_spflags .. str_spflags ..
		"container_end[]"..

		-- Menu buttons
		"container[0,6.9]"..
		"button[3.25,0;3,0.5;world_create_cancel;" .. fgettext("Cancel") .. "]" ..
		"button[6.25,0;3,0.5;world_create_confirm;" .. fgettext("Create") .. "]" ..
		"container_end[]"

	return retval

end

local function create_world_buttonhandler(this, fields)

	local handheld = core.settings:get_bool("menu_handheld")
	if handheld and not (fields["world_create_confirm"] or fields["key_enter"]) then
		return handheld_fields(this, fields)
	end

	if fields["world_create_open_cdb"] then
		local dlg = create_contentdb_dlg("game")
		dlg:set_parent(this.parent)
		this:delete()
		this.parent:hide()
		dlg:show()
		return true
	end

	if fields["world_create_confirm"] or
		fields["key_enter"] then

		if fields["key_enter"] then
			-- HACK: This timestamp prevents double-triggering when pressing Enter on an input box
			-- and releasing it on a button[] or textlist[] due to instant formspec updates.
			this.parent.dlg_create_world_closed_at = core.get_us_time()
		end

		-- the handheld's tabs may not show the name or the seed
		local worldname = fields["te_world_name"] or this.data.worldname or ""
		local game, _ = pkgmgr.find_by_gameid(core.settings:get("menu_last_game"))

		local message
		if game == nil then
			message = fgettext_ne("No game selected")
		end

		if message == nil then
			-- For unnamed worlds use the generated name 'world<number>',
			-- where the number increments: it is set to 1 larger than the largest
			-- generated name number found.
			if worldname == "" then
				local worldnum_max = 0
				for _, world in ipairs(menudata.worldlist:get_list()) do
					if world.name:match("^world%d+$") then
						local worldnum = tonumber(world.name:sub(6))
						worldnum_max = math.max(worldnum_max, worldnum)
					end
				end
				worldname = "world" .. worldnum_max + 1
			end

			if menudata.worldlist:uid_exists_raw(worldname) then
				message = fgettext_ne("A world named \"$1\" already exists", worldname)
			end
		end

		if message == nil then
			this.data.seed = fields["te_seed"] or this.data.seed or ""
			this.data.mg = fields["dd_mapgen"] or this.data.mg

			-- actual names as used by engine
			local settings = {
				fixed_map_seed = this.data.seed,
				mg_name = this.data.mg,
				mg_flags = table_to_flags(this.data.flags.main),
				mgv5_spflags = table_to_flags(this.data.flags.v5),
				mgv6_spflags = table_to_flags(this.data.flags.v6),
				mgv7_spflags = table_to_flags(this.data.flags.v7),
				mgfractal_spflags = table_to_flags(this.data.flags.fractal),
				mgcarpathian_spflags = table_to_flags(this.data.flags.carpathian),
				mgvalleys_spflags = table_to_flags(this.data.flags.valleys),
				mgflat_spflags = table_to_flags(this.data.flags.flat),
			}
			if handheld then
				handheld_settings(this.data, settings)
			end
			-- the engine writes both to world.mt: Creative without damage, Survival with it
			core.settings:set_bool("creative_mode", this.data.creative)
			core.settings:set_bool("enable_damage", not this.data.creative)
			message = core.create_world(worldname, game.id, settings)
		end

		if message == nil then
			core.settings:set("menu_last_game", game.id)
			menudata.worldlist:set_filtercriteria(game.id)
			menudata.worldlist:refresh()
			local index = menudata.worldlist:raw_index_by_uid(worldname)
			core.settings:set("mainmenu_last_selected_world", index)
			-- for the game's mods (goodluckOS's minetest_game switches the mode from the inventory)
			local world = menudata.worldlist:get_raw_element(index)
			local conf = Settings(world.path .. DIR_DELIM .. "world.mt")
			conf:set_bool("allow_mode_change", this.data.mode_change)
			-- as Minecraft's: a chest of things to start with by the spawn
			conf:set_bool("bonus_chest", this.data.bonus_chest)
			if handheld then
				handheld_world_mt(this.data, conf)
			end
			conf:write()
			if handheld then
				menudata.worldlist:refresh()
			end
		end

		gamedata.errormessage = message
		this:delete()
		return true
	end

	this.data.worldname = fields["te_world_name"] or ""
	this.data.seed = fields["te_seed"] or ""

	if fields["btn_game_mode"] then
		this.data.creative = not this.data.creative
		return true
	end

	if fields["cb_mode_change"] then
		this.data.mode_change = core.is_yes(fields["cb_mode_change"])
		return true
	end

	if fields["cb_bonus_chest"] then
		this.data.bonus_chest = core.is_yes(fields["cb_bonus_chest"])
		return true
	end

	if fields["games"] then
		local gameindex = core.get_textlist_index("games")
		core.settings:set("menu_last_game", pkgmgr.games[gameindex].id)
		return true
	end

	for k,v in pairs(fields) do
		local split = string.split(k, "_", nil, 3)
		if split and split[1] == "flag" then
			-- We replaced the underscore of flag names with a dash.
			local flag = string.gsub(split[3], "-", "_")
			local ftable = this.data.flags[split[2]]
			assert(ftable)
			ftable[flag] = v == "true"
			return true
		end
	end

	if fields["world_create_cancel"] then
		this:delete()
		return true
	end

	if fields["mgv6_biomes"] then
		local entry = core.formspec_escape(fields["mgv6_biomes"])
		for b=1, #mgv6_biomes do
			if entry == mgv6_biomes[b][1] then
				local ftable = this.data.flags.v6
				ftable.jungles = mgv6_biomes[b][2].jungles
				ftable.snowbiomes = mgv6_biomes[b][2].snowbiomes
				return true
			end
		end
	end

	if fields["dd_mapgen"] then
		this.data.mg = fields["dd_mapgen"]
		return true
	end

	return false
end


-- from_world: Minecraft's Re-create, the new world starts with that world's seed and choices
-- the world's game mode, difficulty and type, as the handheld's world list shows them
function world_summary(conf)
	local parts = {conf:get_bool("creative_mode") and fgettext_ne("Creative") or fgettext_ne("Survival")}
	if conf:get("difficulty") then
		local _, difficulty = find(DIFFICULTIES, conf:get("difficulty"))
		parts[#parts + 1] = difficulty[2]
	end
	if (conf:get("world_type") or "default") ~= "default" then
		local _, wtype = find(WORLD_TYPES, conf:get("world_type"))
		parts[#parts + 1] = wtype[2]
	end
	return table.concat(parts, ", ")
end

function create_create_world_dlg(from_world)
	local retval = dialog_create("sp_create_world",
					create_world_formspec,
					create_world_buttonhandler,
					nil)
	retval.data = {
		worldname = "",
		creative = false,
		mode_change = false,
		bonus_chest = false,
		-- the handheld's tab, its Customize page and its choices
		tab = 1,
		world_type = "default",
		biome = "grassland",
		difficulty = "normal",
		structures = true,
		rules = {},
		-- settings the world is created with:
		seed = core.settings:get("fixed_map_seed") or "",
		flags = {
			main = core.settings:get_flags("mg_flags"),
			v5 = core.settings:get_flags("mgv5_spflags"),
			v6 = core.settings:get_flags("mgv6_spflags"),
			v7 = core.settings:get_flags("mgv7_spflags"),
			fractal = core.settings:get_flags("mgfractal_spflags"),
			carpathian = core.settings:get_flags("mgcarpathian_spflags"),
			valleys = core.settings:get_flags("mgvalleys_spflags"),
			flat = core.settings:get_flags("mgflat_spflags"),
		}
	}

	for _, rule in ipairs(RULES) do
		retval.data.rules[rule[1]] = rule[3]
	end

	if from_world then
		local conf = Settings(from_world.path .. DIR_DELIM .. "world.mt")
		local meta = Settings(from_world.path .. DIR_DELIM .. "map_meta.txt")
		retval.data.seed = meta:get("seed") or ""
		retval.data.creative = conf:get_bool("creative_mode", false)
		retval.data.mode_change = conf:get_bool("allow_mode_change", false)
		retval.data.bonus_chest = conf:get_bool("bonus_chest", false)
		handheld_from_world(retval.data, conf, meta)
	end

	return retval
end
