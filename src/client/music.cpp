// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Maicon Alves

#include "music.h"
#include <algorithm>
#include "config.h"
#include "sound.h"
#include "sound_spec.h"
#include "filesys.h"
#include "porting.h"
#include "settings.h"
#include "util/numeric.h"
#include "util/string.h"
#include "log.h"
#if USE_SOUND
#include <vorbis/vorbisfile.h>
#endif

// Minecraft's MusicManager: 100 ticks to the first track, then a random pause after each; the delay outlives the
// menu and the games, and a situation with a shorter longest pause cuts it down
static f32 g_music_delay = 5.0f;
static std::string g_music_last;

static std::vector<std::string> tracks(const std::string &set)
{
	std::vector<std::string> out;
	auto add = [&](const std::string &sub) {
		std::string dir = porting::path_user + DIR_DELIM "music" DIR_DELIM + sub;
		for (const auto &node : fs::GetDirListing(dir))
			if (!node.dir && str_ends_with(node.name, std::string(".ogg")))
				out.push_back(dir + DIR_DELIM + node.name);
	};
	add(set);
	if (set == "creative")
		add("game");
	return out;
}

static f32 duration(const std::string &path)
{
#if USE_SOUND
	OggVorbis_File vf;
	if (ov_fopen(path.c_str(), &vf) == 0) {
		f32 seconds = ov_time_total(&vf, -1);
		ov_clear(&vf);
		if (seconds > 0.0f)
			return seconds;
	}
#endif
	return 180.0f;
}

MusicPlayer::~MusicPlayer()
{
	if (m_playing)
		g_music_delay = myrand_range(0.0f, 0.5f);
}

void MusicPlayer::step(f32 dtime, const std::string &set)
{
	const bool menu = set == "menu";
	const f32 min_delay = menu ? 1.0f : 600.0f, max_delay = menu ? 30.0f : 1200.0f;
	if (set != m_set) {
		m_set = set;
		m_files = tracks(set);
	}
	if (m_playing) {
		m_left -= dtime;
		if (m_left > 0.0f)
			return;
		m_playing = false;
		g_music_delay = myrand_range(min_delay, max_delay);
	}
	g_music_delay = std::min(g_music_delay, max_delay) - dtime;
	if (g_music_delay > 0.0f || m_files.empty())
		return;
	f32 gain = g_settings->getFloat("music_volume");
	if (gain <= 0.0f) {
		g_music_delay = 10.0f;
		return;
	}
	play(gain);
}

void MusicPlayer::play(f32 gain)
{
	std::string path = m_files[myrand_range(0, (int)m_files.size() - 1)];
	if (path == g_music_last && m_files.size() > 1)
		path = m_files[(myrand_range(0, (int)m_files.size() - 2) + 1 +
				(&*std::find(m_files.begin(), m_files.end(), path) - &m_files[0])) % m_files.size()];
	if (m_loaded.insert(path).second) {
		if (!m_sound->loadSoundFile(path, path)) {
			m_loaded.erase(path);
			g_music_delay = 10.0f;
			return;
		}
		m_sound->addSoundToGroup(path, path);
	}
	SoundSpec spec(path, gain);
	spec.use_local_fallback = false;
	m_sound->playSound(m_sound->allocateId(1), spec);
	m_left = duration(path);
	infostream << "MusicPlayer: " << path << " (" << m_left << " s)" << std::endl;
	m_playing = true;
	g_music_last = path;
}
