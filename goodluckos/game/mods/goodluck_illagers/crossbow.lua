-- Minecraft's crossbow (CrossbowItem): L1 held 1.25 s loads it with an arrow from the inventory (creative needs
-- none), walking as slow as a drawn bow; let go sooner and it stays empty with the arrow kept. Loaded, it holds the
-- arrow until L1 shoots it at 3.15 a tick (63 nodes a second, the bow's 3 at full draw) for 7 (Minecraft's ceil of
-- 3.15 times 2). 465 uses; made of sticks, string and iron (an iron ingot where Minecraft has a tripwire hook)
local S = goodluck_illagers.S
local N = "goodluck_illagers:"
local CROSSBOW, LOADED = N .. "crossbow", N .. "crossbow_loaded"
local PULLS = {N .. "crossbow_pulling_0", N .. "crossbow_pulling_1", N .. "crossbow_pulling_2"}
local ARROW = "x_bows:arrow_wood"
local CHARGE, USES, POWER = 1.25, 465, 63
local SLOW = (tonumber(core.settings:get("movement_speed_crouch")) or 1.35) /
	(tonumber(core.settings:get("movement_speed_walk")) or 4)
local sprint = core.get_modpath("goodluck_sprint") and goodluck_sprint
local bows = core.global_exists("XBows")
local charging = {}

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local function node_first(itemstack, user, pointed)
	local node = pointed and pointed.type == "node" and core.get_node(pointed.under)
	local def = node and core.registered_nodes[node.name]
	if def and def.on_rightclick and not user:get_player_control().sneak then
		return def.on_rightclick(pointed.under, node, user, itemstack, pointed) or itemstack
	end
end

local function slow(player, on)
	if sprint then
		sprint.stop(player, on, "crossbow")
	end
	goodluck_physics.set(player, "goodluck_illagers_crossbow", on and {speed = SLOW} or nil)
end

local function start(itemstack, user, pointed)
	local done = node_first(itemstack, user, pointed)
	if done then
		return done
	end
	if not user or not user:is_player() or not bows or
			not (creative(user) or user:get_inventory():contains_item("main", ARROW)) then
		return itemstack
	end
	charging[user:get_player_name()] = {t = 0, index = user:get_wield_index()}
	slow(user, true)
	itemstack:set_name(PULLS[1])
	return itemstack
end

-- the arrow leaves where the eyes are, as the bow's, at full power and 1 more damage than the bow's full draw
local function shoot(itemstack, user, pointed)
	local done = node_first(itemstack, user, pointed)
	if done then
		return done
	end
	if not user or not user:is_player() or not bows then
		return itemstack
	end
	local arrow = XBows.registered_arrows[ARROW]
	local data = {_arrow_name = ARROW, _bow_name = CROSSBOW, _user_name = user:get_player_name(),
		_player_look_dir = user:get_look_dir(), _is_critical_hit = false, _is_creative = creative(user),
		_tool_capabilities = arrow.custom.tool_capabilities, _tflp = 10, _add_damage = 1, _x_enchanting = {}}
	core.add_entity(vector.offset(user:get_pos(), 0, 1.5, 0), arrow.custom.projectile_entity, core.serialize(data))
	core.sound_play("goodluck_illagers_crossbow_shoot", {pos = user:get_pos(), gain = 0.5, max_hear_distance = 16},
		true)
	itemstack:set_name(CROSSBOW)
	if not creative(user) then
		itemstack:add_wear_by_uses(USES)
	end
	return itemstack
end

local keep = function(itemstack) return itemstack end
local function register(name, image, def)
	core.register_tool(name, {
		description = S("Crossbow") .. "\n" .. S("Hold L1 to load it, L1 again to shoot"),
		short_description = S("Crossbow"),
		inventory_image = image,
		wield_scale = {x = 1, y = 1, z = 1},
		groups = {crossbow = 1, crossbow_pulling = def.pulling, not_in_creative_inventory = def.hidden},
		on_place = def.use or keep,
		on_secondary_use = def.use or keep,
		-- a pulled or loaded crossbow drops as itself, empty
		drop = CROSSBOW,
	})
end
register(CROSSBOW, "goodluck_illagers_crossbow.png", {use = start})
for i, name in ipairs(PULLS) do
	register(name, "goodluck_illagers_crossbow_pulling_" .. (i - 1) .. ".png", {pulling = 1, hidden = 1})
end
register(LOADED, "goodluck_illagers_crossbow_arrow.png", {use = shoot, hidden = 1})

if bows then
	XBows.registered_bows[CROSSBOW] = {custom = {name = CROSSBOW, strength = POWER, uses = USES,
		sound_hit = "x_bows_arrow_hit"}}
end

core.register_craft({
	output = CROSSBOW,
	recipe = {
		{"group:stick", "default:steel_ingot", "group:stick"},
		{"farming:string", "default:steel_ingot", "farming:string"},
		{"", "group:stick", ""},
	},
})

local function stop(player, name)
	charging[name] = nil
	slow(player, false)
end

-- an arrow from the inventory, or none needed in creative
local function take_arrow(player)
	return creative(player) or player:get_inventory():remove_item("main", ARROW):get_count() == 1
end

-- the pull shows as Minecraft's item model does: pulling_0 under 0.58 of the load, pulling_1 under 1, then pulling_2
core.register_globalstep(function(dtime)
	for name, c in pairs(charging) do
		local player = core.get_player_by_name(name)
		if not player then
			charging[name] = nil
		else
			local stack = player:get_wielded_item()
			if player:get_wield_index() ~= c.index or core.get_item_group(stack:get_name(), "crossbow_pulling") == 0 then
				-- another slot taken: the crossbow left in this one goes back to empty
				local inv = player:get_inventory()
				local left = inv:get_stack("main", c.index)
				if core.get_item_group(left:get_name(), "crossbow_pulling") > 0 then
					left:set_name(CROSSBOW)
					inv:set_stack("main", c.index, left)
				end
				stop(player, name)
			elseif player:get_player_control().place and player:get_hp() > 0 then
				local before = c.t
				c.t = c.t + dtime
				local f = c.t / CHARGE
				if before < 0.2 * CHARGE and f >= 0.2 then
					core.sound_play("goodluck_illagers_crossbow_loading_start", {pos = player:get_pos(), gain = 0.4,
						max_hear_distance = 16}, true)
				end
				local want = PULLS[f < 0.58 and 1 or f < 1 and 2 or 3]
				if stack:get_name() ~= want then
					stack:set_name(want)
					player:set_wielded_item(stack)
				end
			else
				if c.t >= CHARGE and take_arrow(player) then
					stack:set_name(LOADED)
					core.sound_play("goodluck_illagers_crossbow_loading_end", {pos = player:get_pos(), gain = 0.4,
						max_hear_distance = 16}, true)
				else
					stack:set_name(CROSSBOW)
				end
				player:set_wielded_item(stack)
				stop(player, name)
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	charging[player:get_player_name()] = nil
end)

-- a crossbow still pulled when the game was left comes back empty
core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	for i, stack in ipairs(inv:get_list("main") or {}) do
		if core.get_item_group(stack:get_name(), "crossbow_pulling") > 0 then
			stack:set_name(CROSSBOW)
			inv:set_stack("main", i, stack)
		end
	end
end)
