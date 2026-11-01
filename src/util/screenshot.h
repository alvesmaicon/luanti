// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include <string>

namespace video {
	class IVideoDriver;
}

/**
 * Take a screenshot and save it to disk
 * @param driver Video driver to use for the screenshot
 * @param filename_out Output parameter that receives the path to the saved screenshot
 * @return true if the screenshot was saved successfully, false otherwise
 */
bool takeScreenshot(video::IVideoDriver *driver, std::string &filename_out);

/**
 * Save the middle square of what is drawn on the screen so far, scaled down as Minecraft's world icons, for the
 * handheld's world list
 * @param driver Video driver to use for the screenshot
 * @param path The PNG to write
 * @return true if the icon was saved
 */
bool takeWorldIcon(video::IVideoDriver *driver, const std::string &path);

