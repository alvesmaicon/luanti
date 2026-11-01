-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- The rules a world was made with (the handheld menu writes world.mt's "setting.<name> = <value>") hold for its session
-- from before the mods load, as most read their settings then; the user's own come back when the server shuts down.
-- Only these settings: a world from elsewhere can't change any other
local RULES = {
	bones_mode = true, enable_fire = true, mob_difficulty = true, mobs_griefing = true, mobs_spawn = true,
	only_peaceful_mobs = true, time_speed = true,
}

local conf = Settings(core.get_worldpath() .. DIR_DELIM .. "world.mt")
local saved = {}
for _, key in ipairs(conf:get_names()) do
	local name = key:match("^setting%.(.+)$")
	if name and RULES[name] then
		saved[name] = core.settings:has(name) and core.settings:get(name) or false
		core.settings:set(name, conf:get(key))
	end
end

if next(saved) then
	core.register_on_shutdown(function()
		for name, value in pairs(saved) do
			if value then
				core.settings:set(name, value)
			else
				core.settings:remove(name)
			end
		end
	end)
end
