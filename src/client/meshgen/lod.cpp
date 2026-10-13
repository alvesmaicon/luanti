// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "lod.h"
#include "collector.h"
#include "client/mapblock_mesh.h"
#include "client/mesh.h"
#include "client/node_visuals.h"
#include "client/tile.h"
#include "light.h"
#include "nodedef.h"
#include "util/numeric.h"
#include <algorithm>
#include <cassert>

static const v3s16 face_dirs[6] = {
	v3s16(0, 1, 0), v3s16(0, -1, 0), v3s16(1, 0, 0),
	v3s16(-1, 0, 0), v3s16(0, 0, 1), v3s16(0, 0, -1),
};

static constexpr u16 quad_indices[] = {0, 1, 2, 2, 3, 0};

// Most common content among the nodes, ties going to the first
static MapNode most_common(const MapNode *nodes, u8 count)
{
	u8 best = 0, best_count = 0;
	for (u8 i = 0; i < count; i++) {
		u8 n = 0;
		for (u8 j = 0; j < count; j++)
			n += nodes[j].getContent() == nodes[i].getContent();
		if (n > best_count) {
			best = i;
			best_count = n;
		}
	}
	return nodes[best];
}

// Corners in the order of setupCuboidVertices() (content_mapblock.cpp); su, sv: texture repeats
static void setup_face(video::S3DVertex *v, u8 face, v3f a, v3f b, f32 su, f32 sv,
		TileRotation rotation)
{
	switch (face) {
	case 0: // top
		v[0].Pos.set(a.X, b.Y, b.Z); v[1].Pos.set(b.X, b.Y, b.Z);
		v[2].Pos.set(b.X, b.Y, a.Z); v[3].Pos.set(a.X, b.Y, a.Z);
		break;
	case 1: // bottom
		v[0].Pos.set(a.X, a.Y, a.Z); v[1].Pos.set(b.X, a.Y, a.Z);
		v[2].Pos.set(b.X, a.Y, b.Z); v[3].Pos.set(a.X, a.Y, b.Z);
		break;
	case 2: // right
		v[0].Pos.set(b.X, b.Y, a.Z); v[1].Pos.set(b.X, b.Y, b.Z);
		v[2].Pos.set(b.X, a.Y, b.Z); v[3].Pos.set(b.X, a.Y, a.Z);
		break;
	case 3: // left
		v[0].Pos.set(a.X, b.Y, b.Z); v[1].Pos.set(a.X, b.Y, a.Z);
		v[2].Pos.set(a.X, a.Y, a.Z); v[3].Pos.set(a.X, a.Y, b.Z);
		break;
	case 4: // back
		v[0].Pos.set(b.X, b.Y, b.Z); v[1].Pos.set(a.X, b.Y, b.Z);
		v[2].Pos.set(a.X, a.Y, b.Z); v[3].Pos.set(b.X, a.Y, b.Z);
		break;
	default: // front
		v[0].Pos.set(a.X, b.Y, a.Z); v[1].Pos.set(b.X, b.Y, a.Z);
		v[2].Pos.set(b.X, a.Y, a.Z); v[3].Pos.set(a.X, a.Y, a.Z);
		break;
	}
	const v2f uv[4] = {{0, 0}, {su, 0}, {su, sv}, {0, sv}};
	for (int i = 0; i < 4; i++) {
		const f32 x = uv[i].X, y = uv[i].Y;
		switch (rotation) {
		case TileRotation::None:
			v[i].TCoords.set(x, y);
			break;
		case TileRotation::R90:
			v[i].TCoords.set(sv - y, x);
			break;
		case TileRotation::R180:
			v[i].TCoords.set(su - x, sv - y);
			break;
		case TileRotation::R270:
			v[i].TCoords.set(y, su - x);
			break;
		}
	}
}

LodMeshGenerator::LodMeshGenerator(MeshMakeData *data) :
	m_data(data),
	m_ndef(data->m_nodedef),
	m_blockpos_nodes(data->m_blockpos * MAP_BLOCKSIZE),
	m_cells(data->m_side_length / CELL)
{
}

LodMeshGenerator::Cell &LodMeshGenerator::at(v3s16 c)
{
	const s32 n = m_cells + 2;
	return m_grid[((c.Z + 1) * n + c.Y + 1) * n + c.X + 1];
}

LodMeshGenerator::Cell LodMeshGenerator::classify(v3s16 c)
{
	const v3s16 base = m_blockpos_nodes + c * CELL;
	MapNode solid[CELL * CELL * CELL], liquid[CELL * CELL * CELL];
	u8 n_solid = 0, n_liquid = 0, n_ignore = 0, n_upper = 0;
	// Upper layer first, so that ties go to it
	for (s16 y = CELL - 1; y >= 0; y--) {
		for (s16 z = 0; z < CELL; z++)
		for (s16 x = 0; x < CELL; x++) {
			MapNode n = m_data->m_vmanip.getNodeNoExNoEmerge(base + v3s16(x, y, z));
			const content_t id = n.getContent();
			if (id == CONTENT_IGNORE) {
				n_ignore++;
				continue;
			}
			if (id == CONTENT_AIR)
				continue;
			const ContentFeatures &f = m_ndef->get(n);
			if (NDT_solidness[f.drawtype] == 2) {
				solid[n_solid++] = n;
			} else if (f.isLiquid()) {
				if (f.liquid_alternative_source_id != CONTENT_IGNORE)
					n.setContent(f.liquid_alternative_source_id);
				n.param2 = 0;
				liquid[n_liquid++] = n;
			}
		}
		if (y == CELL - 1)
			n_upper = n_solid;
	}

	Cell cell;
	if (n_ignore == CELL * CELL * CELL)
		return cell;
	if (4 * n_solid >= CELL * CELL * CELL) {
		cell.kind = SOLID;
		cell.side = most_common(solid, n_solid);
		cell.top = most_common(solid, n_upper ? n_upper : n_solid);
	} else if (n_liquid) {
		cell.kind = LIQUID;
		cell.side = cell.top = most_common(liquid, n_liquid);
		cell.opaque = m_ndef->get(cell.side).alpha == ALPHAMODE_OPAQUE;
	} else {
		cell.kind = AIR;
	}
	return cell;
}

u16 LodMeshGenerator::faceLight(v3s16 c, u8 face)
{
	v3s16 dir = face_dirs[face];
	const v3s16 base = m_blockpos_nodes + c * CELL;
	// The nodes just across the face
	v3s16 from = base, to = base + v3s16(CELL - 1);
	for (u32 i = 0; i < 3; i++) {
		if (dir[i] > 0)
			from[i] = to[i] = from[i] + CELL;
		else if (dir[i] < 0)
			from[i] = to[i] = from[i] - 1;
	}
	u8 day = 0, night = 0;
	v3s16 p;
	for (p.Z = from.Z; p.Z <= to.Z; p.Z++)
	for (p.Y = from.Y; p.Y <= to.Y; p.Y++)
	for (p.X = from.X; p.X <= to.X; p.X++) {
		const MapNode n = m_data->m_vmanip.getNodeNoExNoEmerge(p);
		if (n.getContent() == CONTENT_IGNORE)
			continue;
		const ContentLightingFlags f = m_ndef->getLightingFlags(n);
		day = std::max(day, n.getLight(LIGHTBANK_DAY, f));
		night = std::max(night, n.getLight(LIGHTBANK_NIGHT, f));
	}
	// Nothing known or lit across (unloaded, or the solid side of a skirt): assume daylight
	if (day == 0 && night == 0)
		day = LIGHT_SUN;
	return decode_light(day) | (decode_light(night) << 8);
}

static bool is_tileable(const TileSpec &tile)
{
	constexpr u8 both = MATERIAL_FLAG_TILEABLE_HORIZONTAL | MATERIAL_FLAG_TILEABLE_VERTICAL;
	return (tile.layers[0].material_flags & both) == both;
}

void LodMeshGenerator::drawQuad(u8 face, v3s16 c0, v3s16 c1, s16 w, s16 h, const Face &f,
		MeshCollector &out)
{
	const ContentFeatures &cf = m_ndef->get(f.node);
	TileSpec tile;
	getNodeTile(f.node, c0 * CELL, face_dirs[face], m_data, tile);
	if (f.kind == SOLID) {
		for (auto &layer : tile.layers)
			layer.material_flags |= MATERIAL_FLAG_BACKFACE_CULLING;
	}

	const v3f normal = v3f::from(face_dirs[face]);
	video::SColor color = encode_light(f.light, cf.light_source);
	if (!cf.light_source)
		applyFacesShading(color, normal);

	const v3f min = intToFloat(c0 * CELL, BS) - v3f(0.5f * BS);
	const v3f max = intToFloat((c1 + v3s16(1)) * CELL, BS) - v3f(0.5f * BS);
	// Textures repeat once per node where they tile, else stretch
	const bool tileable = is_tileable(tile);
	const f32 su = tileable ? w * CELL : 1;
	const f32 sv = tileable ? h * CELL : 1;

	video::S3DVertex v[4];
	setup_face(v, face, min, max, su, sv, tile.rotation);
	for (auto &vertex : v) {
		vertex.Normal = normal;
		vertex.Color = color;
	}
	out.append(tile, v, 4, quad_indices, 6);
}

void LodMeshGenerator::generate(std::vector<MeshCollector> &out)
{
	assert(out.size() == 7);
	const s32 n = m_cells + 2;
	m_grid.resize(n * n * n);

	v3s16 c;
	for (c.Z = -1; c.Z <= m_cells; c.Z++)
	for (c.Y = -1; c.Y <= m_cells; c.Y++)
	for (c.X = -1; c.X <= m_cells; c.X++)
		at(c) = classify(c);

	// The faces to draw, per direction and cell
	const s32 volume = m_cells * m_cells * m_cells;
	std::vector<Face> faces(6 * volume);
	const auto face_at = [&] (u8 face, v3s16 c) -> Face & {
		return faces[face * volume + (c.Z * m_cells + c.Y) * m_cells + c.X];
	};
	for (c.Z = 0; c.Z < m_cells; c.Z++)
	for (c.Y = 0; c.Y < m_cells; c.Y++)
	for (c.X = 0; c.X < m_cells; c.X++) {
		const Cell &cell = at(c);
		if (cell.kind != SOLID && cell.kind != LIQUID)
			continue;
		for (u8 face = 0; face < 6; face++) {
			const v3s16 c2 = c + face_dirs[face];
			const Cell &other = at(c2);
			u8 dst = 0;
			if (cell.kind == SOLID) {
				if (other.kind == LIQUID && other.opaque)
					continue;
				if (other.kind == SOLID) {
					const bool inside = c2.X >= 0 && c2.X < m_cells && c2.Y >= 0 &&
							c2.Y < m_cells && c2.Z >= 0 && c2.Z < m_cells;
					if (inside)
						continue;
					dst = 1 + face;
				}
			} else if (other.kind == SOLID || (other.kind == LIQUID &&
					other.side.getContent() == cell.side.getContent())) {
				continue;
			}
			Face &f = face_at(face, c);
			f.dst = dst;
			f.kind = cell.kind;
			f.node = face == 0 ? cell.top : cell.side;
			f.light = faceLight(c, face);
		}
	}

	// Equal faces next to each other become one quad; axes: normal, u, v of setup_face()
	static const u8 axes[6][3] = {
		{1, 0, 2}, {1, 0, 2}, {0, 2, 1}, {0, 2, 1}, {2, 0, 1}, {2, 0, 1},
	};
	std::vector<bool> done(m_cells * m_cells);
	for (u8 face = 0; face < 6; face++) {
		const u8 an = axes[face][0], au = axes[face][1], av = axes[face][2];
		const auto face_uv = [&] (s16 s, s16 u, s16 v) -> Face & {
			v3s16 p;
			p[an] = s;
			p[au] = u;
			p[av] = v;
			return face_at(face, p);
		};
		for (s16 s = 0; s < m_cells; s++) {
			std::fill(done.begin(), done.end(), false);
			for (s16 v = 0; v < m_cells; v++)
			for (s16 u = 0; u < m_cells; u++) {
				const Face &f = face_uv(s, u, v);
				if (done[v * m_cells + u] || f.dst == Face::NONE)
					continue;
				TileSpec tile;
				getNodeTile(f.node, v3s16(0), face_dirs[face], m_data, tile);
				s16 w = 1, h = 1;
				if (is_tileable(tile)) {
					while (u + w < m_cells && !done[v * m_cells + u + w] &&
							face_uv(s, u + w, v) == f)
						w++;
					for (; v + h < m_cells; h++) {
						bool same = true;
						for (s16 i = 0; i < w && same; i++)
							same = !done[(v + h) * m_cells + u + i] &&
									face_uv(s, u + i, v + h) == f;
						if (!same)
							break;
					}
				}
				for (s16 j = 0; j < h; j++)
				for (s16 i = 0; i < w; i++)
					done[(v + j) * m_cells + u + i] = true;

				v3s16 c0, c1;
				c0[an] = c1[an] = s;
				c0[au] = u;
				c0[av] = v;
				c1[au] = u + w - 1;
				c1[av] = v + h - 1;
				drawQuad(face, c0, c1, w, h, f, out[f.dst]);
			}
		}
	}
}
