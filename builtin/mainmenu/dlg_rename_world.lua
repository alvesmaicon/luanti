-- Luanti
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- the handheld's Rename, Minecraft's Edit: a world's name is its world.mt's world_name, its folder stays

local function rename_world_formspec(dialogdata)
	local fs = {
		"formspec_version[6]size[11,4]",
		("field[0.5,0.9;10,0.8;te_world_name;%s;%s]"):format(fgettext("World name"),
				core.formspec_escape(dialogdata.name)),
		"field_close_on_enter[te_world_name;false]",
		("button[0.5,2.7;4.9,0.8;dlg_rename_world_confirm;%s]"):format(fgettext("Rename")),
		("button[5.6,2.7;4.9,0.8;dlg_rename_world_cancel;%s]"):format(fgettext("Cancel")),
	}
	if dialogdata.error then
		fs[#fs + 1] = ("label[0.5,2.1;%s]"):format(core.colorize("#FF6060", dialogdata.error))
	end
	return table.concat(fs)
end

local function rename_world_buttonhandler(this, fields)
	if fields.dlg_rename_world_cancel then
		this:delete()
		return true
	end
	if fields.te_world_name then
		this.data.name = fields.te_world_name
	end
	if not (fields.dlg_rename_world_confirm or fields.key_enter) then
		return false
	end
	local name = this.data.name:trim()
	if name == "" or name == this.data.world.name then
		this:delete()
		return true
	elseif menudata.worldlist:uid_exists_raw(name) then
		this.data.error = fgettext("A world named \"$1\" already exists", name)
		return true
	end
	local conf = Settings(this.data.world.path .. DIR_DELIM .. "world.mt")
	conf:set("world_name", name)
	if not conf:write() then
		core.log("error", "Failed to write world config file")
	end
	menudata.worldlist:refresh()
	this:delete()
	return true
end

function create_rename_world_dlg(world)
	local retval = dialog_create("dlg_rename_world", rename_world_formspec, rename_world_buttonhandler, nil)
	retval.data.world = world
	retval.data.name = world.name
	return retval
end
