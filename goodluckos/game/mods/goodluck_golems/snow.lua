-- Snowballs as in Minecraft: snow gives them (a snow block 4, a layer 1, to a shovel), 4 make a snow block again and
-- 3 blocks make 6 layers; L1 throws one (1.5 a tick, 0.03 of gravity, 0.99 of its speed kept a tick, as the ender
-- pearl), and the snow golem throws them at monsters. One hurts only a blaze (3), but pushes what it hits a little and
-- makes it go after whoever threw it
local G = "goodluck_golems:"
local TICK = 0.05
local BLAZE = "goodluck_nether:blaze"

local function puff(pos)
	core.add_particlespawner({amount = 8, time = 0.05, pos = {min = vector.offset(pos, -0.1, -0.1, -0.1),
		max = vector.offset(pos, 0.1, 0.1, 0.1)}, vel = {min = vector.new(-1.5, 0, -1.5), max = vector.new(1.5, 2, 1.5)},
		acc = vector.new(0, -9.81, 0), exptime = {min = 0.3, max = 0.6}, size = {min = 0.8, max = 1.5},
		texture = "default_snowball.png"})
end

-- a tick at a time, a ray from where it was to where it goes; its thrower is out of reach for 2 ticks
core.register_entity(G .. "thrown_snowball", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "sprite",
		visual_size = {x = 0.25, y = 0.25}, textures = {"default_snowball.png"}},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		while self._t >= TICK do
			self._t = self._t - TICK
			self._ticks = (self._ticks or 0) + 1
			local pos = self.object:get_pos()
			local to = vector.add(pos, self._v)
			for hit in core.raycast(pos, to, true, false) do
				local obj = hit.type == "object" and hit.ref
				local ent = obj and obj:get_luaentity()
				if obj and obj ~= self.object and (obj:is_player() or ent and ent._cmi_is_mob) and
						(obj ~= self._owner or self._ticks > 2) then
					return self:hit(hit.intersection_point, obj)
				elseif hit.type == "node" and
						(core.registered_nodes[core.get_node(hit.under).name] or {}).walkable ~= false then
					return self:hit(hit.intersection_point)
				end
			end
			if (core.registered_nodes[core.get_node(to).name] or {}).liquidtype ~= "none" then
				self._v = vector.multiply(self._v, 0.8)
			else
				self._v = vector.multiply(self._v, 0.99)
			end
			self._v.y = self._v.y - 0.03
			self.object:set_pos(to)
			if self._ticks > 600 or core.get_node(to).name == "ignore" then
				self.object:remove()
				return
			end
		end
	end,
	hit = function(self, at, obj)
		self.object:remove()
		puff(at)
		if not obj then
			return
		end
		local ent = obj:get_luaentity()
		local by = self._owner and self._owner:is_valid() and self._owner or self.object
		obj:punch(by, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = ent and ent.name == BLAZE and 3 or 0,
			knockback = 1}}, vector.normalize(self._v))
	end,
})

-- one thrown from pos along dir, speed nodes a tick, with Minecraft's spread (a triangle of 0.0172275 a point)
function goodluck_golems.throw(pos, dir, speed, spread, owner)
	local obj = core.add_entity(pos, G .. "thrown_snowball")
	local ent = obj and obj:get_luaentity()
	if not ent then
		return
	end
	local d = vector.normalize(dir)
	local k = 0.0172275 * spread
	d = vector.offset(d, (math.random() - math.random()) * k, (math.random() - math.random()) * k,
		(math.random() - math.random()) * k)
	ent._v, ent._owner = vector.multiply(d, speed), owner
end

local function throw(itemstack, user, pointed_thing)
	-- what a block does with L1 (a chest, a door) first, unless sneaking
	if pointed_thing and pointed_thing.type == "node" then
		local node = core.get_node(pointed_thing.under)
		local def = core.registered_nodes[node.name]
		if def and def.on_rightclick and not user:get_player_control().sneak then
			return def.on_rightclick(pointed_thing.under, node, user, itemstack, pointed_thing)
		end
	end
	local eye = vector.offset(user:get_pos(), 0, user:get_properties().eye_height - 0.1, 0)
	goodluck_golems.throw(eye, user:get_look_dir(), 1.5, 1, user)
	core.sound_play("goodluck_golems_throw", {pos = eye, max_hear_distance = 16,
		pitch = 1 / (math.random() * 0.4 + 0.8)}, true)
	if not core.is_creative_enabled(user:get_player_name()) then
		itemstack:take_item()
	end
	return itemstack
end

core.register_craftitem(G .. "snowball", {
	description = core.translate("goodluck_golems", "Snowball"),
	inventory_image = "default_snowball.png",
	stack_max = 16,
	on_place = throw,
	on_secondary_use = throw,
})

core.override_item("default:snowblock", {drop = G .. "snowball 4"})
-- the layer looks like itself in the inventory: the snowball is its own item now
core.override_item("default:snow", {drop = G .. "snowball", inventory_image = "", wield_image = ""})
core.clear_craft({output = "default:snowblock"})
core.clear_craft({output = "default:snow"})
core.register_craft({
	output = "default:snowblock",
	recipe = {{G .. "snowball", G .. "snowball"}, {G .. "snowball", G .. "snowball"}},
})
core.register_craft({
	output = "default:snow 6",
	recipe = {{"default:snowblock", "default:snowblock", "default:snowblock"}},
})
