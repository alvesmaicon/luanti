// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irrlichttypes.h"
#include "irr_v3d.h"
#include "mapnode.h"
#include <vector>

struct MeshMakeData;
struct MeshCollector;
class NodeDefManager;

/*
	Simplified mesh of a region of 2x2x2 mapblocks, for drawing far away:
	each 2x2x2 nodes become one cell, solid when a quarter of them are opaque
	cubes, else liquid when one of them is a liquid.
*/
class LodMeshGenerator
{
public:
	// Nodes per cell edge
	static constexpr s16 CELL = 2;
	// Mapblocks per region edge
	static constexpr s16 REGION = 2;

	LodMeshGenerator(MeshMakeData *data);

	/// @param out 7 collectors: [0] the region, [1 + face] the faces on the
	///     region's side toward solid cells of the neighbour, to draw while the
	///     neighbour shows detail meshes (faces +Y -Y +X -X +Z -Z)
	void generate(std::vector<MeshCollector> &out);

private:
	enum Kind : u8 { AIR, SOLID, LIQUID, UNKNOWN };

	struct Cell {
		Kind kind = UNKNOWN;
		MapNode side; // drawn on the sides and the bottom
		MapNode top; // drawn on the top
	};

	Cell classify(v3s16 cell);
	Cell &at(v3s16 cell);
	u16 faceLight(v3s16 cell, u8 face);
	void drawFace(v3s16 cell, u8 face, const Cell &c, MeshCollector &out);

	MeshMakeData *m_data;
	const NodeDefManager *m_ndef;
	v3s16 m_blockpos_nodes;
	// cells per region edge
	s16 m_cells;
	// with a border of one cell
	std::vector<Cell> m_grid;
};
