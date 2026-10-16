// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024 cx384

#pragma once

#include <IGUIFont.h>
#include <IVideoDriver.h>
#include "irrlichttypes.h"
#include "irr_v3d.h"

struct ItemStack;
class Client;

enum ItemRotationKind
{
	IT_ROT_SELECTED,
	IT_ROT_HOVERED,
	IT_ROT_DRAGGED,
	IT_ROT_OTHER,
	IT_ROT_NONE, // Must be last, also serves as number
};

// Item meshes share the depth buffer instead of clearing it each: call at the start of a frame's 2D drawing, and after
// anything else in the GUI used the depth buffer (a 3D scene), so that the next mesh clears it once
void drawItemStackDepthReset();

void drawItemStack(video::IVideoDriver *driver,
		gui::IGUIFont *font,
		const ItemStack &item,
		const core::rect<s32> &rect,
		const core::rect<s32> *clip,
		Client *client,
		ItemRotationKind rotation_kind);

void drawItemStack(
		video::IVideoDriver *driver,
		gui::IGUIFont *font,
		const ItemStack &item,
		const core::rect<s32> &rect,
		const core::rect<s32> *clip,
		Client *client,
		ItemRotationKind rotation_kind,
		const v3s16 &angle,
		const v3s16 &rotation_speed);
