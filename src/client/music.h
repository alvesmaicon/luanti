// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Maicon Alves

#pragma once

#include <memory>
#include <set>
#include <string>
#include <vector>
#include "irrlichttypes.h"

class ISoundManager;

// Plays the tracks of <path_user>/music/<set>/*.ogg as Minecraft plays its music: one at a time, straight from the
// file, 10 to 20 minutes apart in a game and 1 to 30 s apart on the menu, at music_volume; a track cut short by the
// end of its sound manager is followed by the next within half a second, as Minecraft's menu music replaces the
// game's. The set is "menu", "game", "creative" (which also plays "game") or "water".
class MusicPlayer
{
public:
	MusicPlayer(ISoundManager *sound) : m_sound(sound) {}
	~MusicPlayer();
	void step(f32 dtime, const std::string &set);

private:
	void play(f32 gain);

	ISoundManager *m_sound;
	std::string m_set;
	std::vector<std::string> m_files;
	std::set<std::string> m_loaded;
	bool m_playing = false;
	f32 m_left = 0.0f; // of the track, in seconds
};
