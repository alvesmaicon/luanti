// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#pragma once

#include "irrlichttypes_bloated.h"
#include "map.h"
#include <ISceneNode.h>
#include <map>
#include <memory>
#include <functional>
#include <unordered_map>

struct MapDrawControl
{
	// Wanted drawing range
	float wanted_range = 0.0f;
	// Overrides limits by drawing everything
	bool range_all = false;
	// Allow rendering out of bounds
	bool allow_noclip = false;
	// show a wire frame for debugging
	bool show_wireframe = false;
};

class Client;
class RenderingEngine;
class MapBlockMesh;

enum CameraMode : int;

namespace scene
{
	class IMeshBuffer;
}

namespace video
{
	class IVideoDriver;
}

struct CachedMeshBuffer {
	std::vector<scene::IMeshBuffer*> buf;
	u8 age = 0;

	void drop();
};

using CachedMeshBuffers = std::unordered_map<std::string, CachedMeshBuffer>;

using ModifyMaterialCallback = std::function<void(video::SMaterial& /* material */, bool /* is_foliage */)>;

/*
	ClientMap

	This is the only map class that is able to render itself on screen.
*/

class ClientMap : public Map, public scene::ISceneNode
{
public:
	ClientMap(
			Client *client,
			RenderingEngine *rendering_engine,
			MapDrawControl &control,
			s32 id
	);

	bool maySaveBlocks() override
	{
		return false;
	}

	void updateCamera(v3f pos, v3f dir, f32 fov, v3s16 offset, video::SColor light_color);

	/*
		Forcefully get a sector from somewhere
	*/
	MapSector * emergeSector(v2s16 p) override;

	/*
		ISceneNode methods
	*/

	virtual void OnRegisterSceneNode() override;

	virtual void render() override;

	virtual const aabb3f &getBoundingBox() const override
	{
		return m_box;
	}

	void getBlocksInViewRange(v3s16 cam_pos_nodes,
		v3s16 *p_blocks_min, v3s16 *p_blocks_max, float range=-1.0f);

	void updateDrawList();
	/// @brief clears m_drawlist and m_keeplist
	void clearDrawList();

	/// @brief Calculate statistics about the map and keep the blocks alive
	void touchMapBlocks();

	/// @brief returns a distance-sorted list of all block mesh positions
	void getBlocksWithMeshes(std::vector<v3s16> &out);

	void updateDrawListShadow(v3f shadow_light_pos, v3f shadow_light_dir, float radius, float length);
	void clearDrawListShadow();

	// Returns true if draw list needs updating before drawing the next frame.
	bool needsUpdateDrawList() { return m_needs_update_drawlist; }

	void renderMap(video::IVideoDriver* driver, s32 pass);

	void renderMapShadows(video::IVideoDriver *driver,
			ModifyMaterialCallback cb, s32 pass, int frame, int total_frames);

	int getBackgroundBrightness(float max_d, u32 daylight_factor,
			int oldvalue, bool *sunlight_seen_result);

	void renderPostFx(CameraMode cam_mode);

	void invalidateMapBlockMesh(MapBlockMesh *mesh);

	// Simplified mesh of the region of 2x2x2 blocks at region_pos (client_lod_distance)
	void setLodMesh(v3s16 region_pos, std::unique_ptr<MapBlockMesh> mesh,
			std::unique_ptr<MapBlockMesh> (&skirts)[6]);
	// The block's data changed: regions that use it need a new simplified mesh
	void markLodDirty(v3s16 blockpos);
	// Whether the mesh at mesh_pos is far enough to be drawn simplified only
	bool skipDetailMesh(v3s16 mesh_pos);

	// For debug printing
	void PrintInfo(std::ostream &out) override;

	const MapDrawControl & getControl() const { return m_control; }
	f32 getWantedRange() const { return m_control.wanted_range; }
	f32 getCameraFov() const { return m_camera_fov; }

	void onSettingChanged(std::string_view name, bool all);

protected:
	// use drop() instead
	virtual ~ClientMap();

	void reportMetrics(u64 save_time_us, u32 saved_blocks, u32 all_blocks) override;
	bool isOccluder(const MapNode &n) const override;
private:
	bool isMeshOccluded(MapBlock *mesh_block, u16 mesh_size, v3s16 cam_pos_nodes);

	bool useLoopsCuller() const;
	struct LodRegion
	{
		std::unique_ptr<MapBlockMesh> mesh;
		// faces on each side toward solid cells, drawn while that neighbour shows detail
		std::unique_ptr<MapBlockMesh> skirts[6];
		bool has_mesh = false;
		bool dirty = false;
		bool queued = false;
		// drawn from the simplified mesh in the current draw list
		bool lod = false;
		u32 drawlist_id = 0;
		u64 queued_ms = 0;
		u64 used_ms = 0;
		// when it came close enough to show detail again
		u64 near_ms = 0;
	};

	// Distance from the camera to a region's center, in BS
	f32 lodDistance(v3s16 region_pos) const;
	// Whether a region at distance d is drawn from its simplified mesh
	bool useLod(v3s16 region_pos, f32 d, u64 now_ms);
	bool detailMeshesMade(v3s16 region_pos);
	void dropLodMeshes(LodRegion &region);
	void dropDetailMesh(MapBlock *block);

	// update the vertex order in transparent mesh buffers
	void updateTransparentMeshBuffers();

	// Orders blocks by distance to the camera
	class MapBlockComparer
	{
	public:
		MapBlockComparer(const v3s16 &camera_block) : m_camera_block(camera_block) {}

		bool operator() (const v3s16 &left, const v3s16 &right) const
		{
			auto distance_left = left.getDistanceFromSQ(m_camera_block);
			auto distance_right = right.getDistanceFromSQ(m_camera_block);
			return distance_left > distance_right || (distance_left == distance_right && left > right);
		}

	private:
		v3s16 m_camera_block;
	};

	Client *m_client;
	RenderingEngine *m_rendering_engine;

	aabb3f m_box = aabb3f(-BS * 1000000, -BS * 1000000, -BS * 1000000,
		BS * 1000000, BS * 1000000, BS * 1000000);

	MapDrawControl &m_control;

	v3f m_camera_position = v3f(0,0,0);
	v3f m_camera_direction = v3f(0,0,1);
	f32 m_camera_fov = M_PI;
	v3s16 m_camera_offset;
	video::SColor m_camera_light_color = video::SColor(0xFFFFFFFF);
	bool m_needs_update_transparent_meshes = true;

	std::map<v3s16, MapBlock*, MapBlockComparer> m_drawlist;
	// List of additional blocks to keep (relevant with mesh_chunk > 1, since
	// not all blocks contain a mesh)
	std::vector<MapBlock*> m_keeplist;
	std::map<v3s16, MapBlock*> m_drawlist_shadow;
	bool m_needs_update_drawlist;
	std::unordered_map<v3s16, LodRegion> m_lod_regions;
	// regions drawn from their simplified mesh, with the skirts to draw (bits +Y -Y +X -X +Z -Z)
	std::vector<std::pair<v3s16, u8>> m_lod_drawlist;
	u32 m_drawlist_id = 0;
	u64 m_lod_expire_ms = 0;
	CachedMeshBuffers m_dynamic_buffers;

	bool m_cache_trilinear_filter;
	bool m_cache_bilinear_filter;
	bool m_cache_anistropic_filter;
	bool m_cache_transparency_sorting_group_by_buffers;
	u16 m_cache_transparency_sorting_distance;

	bool m_loops_occlusion_culler;
	bool m_enable_raytraced_culling;
	bool m_cache_unload_out_of_view;
	f32 m_cache_lod_distance;
	f32 m_cache_unload_timeout;
};
