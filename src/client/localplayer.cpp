// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "localplayer.h"
#include <cmath>
#include "mtevent.h"
#include "collision.h"
#include "nodedef.h"
#include "settings.h"
#include "environment.h"
#include "map.h"
#include "client.h"
#include "content_cao.h"
#include "hud_element.h"

/*
	PlayerSettings
*/

const static std::string PlayerSettings_names[] = {
	"free_move", "pitch_move", "fast_move", "continuous_forward", "always_fly_fast",
	"aux1_descends", "noclip", "autojump"
};

void PlayerSettings::readGlobalSettings()
{
	free_move = g_settings->getBool("free_move");
	pitch_move = g_settings->getBool("pitch_move");
	fast_move = g_settings->getBool("fast_move");
	continuous_forward = g_settings->getBool("continuous_forward");
	always_fly_fast = g_settings->getBool("always_fly_fast");
	aux1_descends = g_settings->getBool("aux1_descends");
	noclip = g_settings->getBool("noclip");
	autojump = g_settings->getBool("autojump");
}


void PlayerSettings::registerSettingsCallback()
{
	for (auto &name : PlayerSettings_names) {
		g_settings->registerChangedCallback(name,
			&PlayerSettings::settingsChangedCallback, this);
	}
}

void PlayerSettings::deregisterSettingsCallback()
{
	g_settings->deregisterAllChangedCallbacks(this);
}

void PlayerSettings::settingsChangedCallback(const std::string &name, void *data)
{
	((PlayerSettings *)data)->readGlobalSettings();
}

/*
	LocalPlayer
*/

LocalPlayer::LocalPlayer(Client *client, const std::string &name):
	Player(name, client->idef()),
	m_client(client)
{
	m_player_settings.readGlobalSettings();
	m_player_settings.registerSettingsCallback();
}

LocalPlayer::~LocalPlayer()
{
	m_player_settings.deregisterSettingsCallback();
}

static aabb3f getNodeBoundingBox(const std::vector<aabb3f> &nodeboxes)
{
	if (nodeboxes.empty())
		return aabb3f(0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f);

	auto it = nodeboxes.begin();
	aabb3f b_max(it->MinEdge, it->MaxEdge);

	++it;
	for (; it != nodeboxes.end(); ++it)
		b_max.addInternalBox(*it);

	return b_max;
}


bool LocalPlayer::updateSneakNode(Map *map, const v3f &position,
	const v3f &sneak_max)
{
	// Acceptable distance to node center
	// This must be > 0.5 units to get the sneak ladder to work
	// 0.05 prevents sideways teleporting through 1/16 thick walls
	constexpr f32 allowed_range = (0.5f + 0.05f) * BS;
	static const v3s16 dir9_center[9] = {
		v3s16( 0, 0,  0),
		v3s16( 1, 0,  0),
		v3s16(-1, 0,  0),
		v3s16( 0, 0,  1),
		v3s16( 0, 0, -1),
		v3s16( 1, 0,  1),
		v3s16(-1, 0,  1),
		v3s16( 1, 0, -1),
		v3s16(-1, 0, -1)
	};

	const NodeDefManager *nodemgr = m_client->ndef();
	MapNode node;
	bool is_valid_position;
	bool new_sneak_node_exists = m_sneak_node_exists;

	// We want the top of the sneak node to be below the players feet
	f32 position_y_mod = 0.02f * BS;
	if (m_sneak_node_exists)
		position_y_mod = m_sneak_node_bb_top.MaxEdge.Y - position_y_mod;

	// Get position of current standing node
	const v3s16 current_node = floatToInt(position - v3f(0.0f, position_y_mod, 0.0f), BS);

	if (current_node != m_sneak_node) {
		new_sneak_node_exists = false;
	} else {
		node = map->getNode(current_node, &is_valid_position);
		if (!is_valid_position || !nodemgr->get(node).walkable)
			new_sneak_node_exists = false;
	}

	// Keep old sneak node
	if (new_sneak_node_exists)
		return true;

	// Get new sneak node
	m_sneak_ladder_detected = false;
	f32 min_distance_sq = HUGE_VALF;

	for (const auto &d : dir9_center) {
		const v3s16 p = current_node + d;

		node = map->getNode(p, &is_valid_position);
		// The node to be sneaked on has to be walkable
		if (!is_valid_position || !nodemgr->get(node).walkable)
			continue;

		v3f pf = intToFloat(p, BS);
		{
			std::vector<aabb3f> nodeboxes;
			node.getCollisionBoxes(nodemgr, &nodeboxes);
			pf += getNodeBoundingBox(nodeboxes).getCenter();
		}

		const v2f diff(position.X - pf.X, position.Z - pf.Z);
		const f32 distance_sq = diff.getLengthSQ();

		if (distance_sq > min_distance_sq ||
				std::fabs(diff.X) > allowed_range + sneak_max.X ||
				std::fabs(diff.Y) > allowed_range + sneak_max.Z)
			continue;

		// And the node(s) above have to be nonwalkable
		bool ok = true;
		if (!physics_override.sneak_glitch) {
			u16 height =
				ceilf((m_collisionbox.MaxEdge.Y - m_collisionbox.MinEdge.Y) / BS);
			for (u16 y = 1; y <= height; y++) {
				node = map->getNode(p + v3s16(0, y, 0), &is_valid_position);
				if (!is_valid_position || nodemgr->get(node).walkable) {
					ok = false;
					break;
				}
			}
		} else {
			// legacy behavior: check just one node
			node = map->getNode(p + v3s16(0, 1, 0), &is_valid_position);
			ok = is_valid_position && !nodemgr->get(node).walkable;
		}
		if (!ok)
			continue;

		min_distance_sq = distance_sq;
		m_sneak_node = p;
		new_sneak_node_exists = true;
	}

	if (!new_sneak_node_exists)
		return false;

	// Update saved top bounding box of sneak node
	node = map->getNode(m_sneak_node);
	std::vector<aabb3f> nodeboxes;
	node.getCollisionBoxes(nodemgr, &nodeboxes);
	m_sneak_node_bb_top = getNodeBoundingBox(nodeboxes);

	if (physics_override.sneak_glitch) {
		// Detect sneak ladder:
		// Node two meters above sneak node must be solid
		node = map->getNode(m_sneak_node + v3s16(0, 2, 0),
			&is_valid_position);
		if (is_valid_position && nodemgr->get(node).walkable) {
			// Node three meters above: must be non-solid
			node = map->getNode(m_sneak_node + v3s16(0, 3, 0),
				&is_valid_position);
			m_sneak_ladder_detected = is_valid_position &&
				!nodemgr->get(node).walkable;
		}
	}
	return true;
}

// Minecraft's air: each 20 Hz tick 0.08 down, then 98 % of the vertical speed kept, so a fall ends at 3.92 a tick
static const f32 MC_AIR_KEEP = 0.98f;
static const f32 MC_AIR_TERMINAL = 20.0f * 0.08f * MC_AIR_KEEP / (1.0f - MC_AIR_KEEP);

// A speed of Minecraft's (a tick) as the speed whose path in continuous time goes through
// Minecraft's position at every tick of its air
f32 LocalPlayer::getAirSpeed(f32 per_tick) const
{
	const f32 terminal = MC_AIR_TERMINAL * physics_override.gravity;
	const f32 rate = -std::log(MC_AIR_KEEP) / (1.0f - MC_AIR_KEEP);
	return ((20.0f * per_tick + terminal) * rate - terminal) * BS;
}

// Minecraft's jump, 0.42 a tick
f32 LocalPlayer::getJumpSpeed() const
{
	return physics_override.jump == 0.0f ? 0.0f : getAirSpeed(0.42f * physics_override.jump);
}

// The same air in continuous time, v -> V + (v - V) * 0.98^(20 t): the pull that gives that speed after dtime
f32 LocalPlayer::getAirGravity(f32 dtime) const
{
	if (dtime <= 0.0f)
		return 0.0f;
	const f32 terminal = -MC_AIR_TERMINAL * BS * physics_override.gravity;
	return (m_speed.Y - terminal) * (1.0f - std::pow(MC_AIR_KEEP, 20.0f * dtime)) / dtime;
}

// How far a fall in that air drops before it lands at this speed
f32 LocalPlayer::getFallHeight(f32 speed) const
{
	const f32 terminal = MC_AIR_TERMINAL * std::max(physics_override.gravity, 0.01f);
	const f32 u = std::min(speed / BS, terminal * 0.9999f);
	return (terminal * std::log(terminal / (terminal - u)) - u) / (-20.0f * std::log(MC_AIR_KEEP));
}

static bool is_water(const ContentFeatures &f)
{
	return f.liquid_type != LIQUID_NONE && itemgroup_get(f.groups, "water") > 0;
}

// The water's own height in its node (0 to 1)
static f32 water_own_level(MapNode n, const ContentFeatures &f)
{
	if (f.liquid_type == LIQUID_SOURCE)
		return 1.0f;
	u8 range = rangelim(f.liquid_range, 1, 8);
	u8 level = n.param2 & LIQUID_LEVEL_MASK;
	level = level <= LIQUID_LEVEL_MAX + 1 - range ? 0 : level - (LIQUID_LEVEL_MAX + 1 - range);
	return (level + 0.5f) / range;
}

// As drawn: full under more water
static f32 water_level(Map *map, const NodeDefManager *nodemgr, v3s16 p, MapNode n,
		const ContentFeatures &f)
{
	if (is_water(nodemgr->get(map->getNode(p + v3s16(0, 1, 0)))))
		return 1.0f;
	return water_own_level(n, f);
}

// Where the water runs, as Minecraft's FlowingFluid.getFlow: down the heights to its four sides,
// over an edge to water below, and down a fall along a wall
static v3f water_flow(Map *map, const NodeDefManager *nodemgr, v3s16 p, MapNode n,
		const ContentFeatures &f)
{
	static const v3s16 sides[4] = {v3s16(1, 0, 0), v3s16(-1, 0, 0), v3s16(0, 0, 1), v3s16(0, 0, -1)};
	const f32 own = water_own_level(n, f);
	v3f flow;
	for (const v3s16 &side : sides) {
		const MapNode n2 = map->getNode(p + side);
		const ContentFeatures &f2 = nodemgr->get(n2);
		f32 drop = 0.0f;
		if (is_water(f2)) {
			drop = own - water_own_level(n2, f2);
		} else if (f2.liquid_type == LIQUID_NONE && !f2.walkable) {
			const MapNode n3 = map->getNode(p + side - v3s16(0, 1, 0));
			const ContentFeatures &f3 = nodemgr->get(n3);
			if (is_water(f3))
				drop = own - (water_own_level(n3, f3) - 1.0f);
		}
		flow += v3f(side.X, 0.0f, side.Z) * drop;
	}
	if (f.liquid_type == LIQUID_FLOWING && (n.param2 & LIQUID_FLOW_DOWN_MASK)) {
		for (const v3s16 &side : sides) {
			if (nodemgr->get(map->getNode(p + side)).walkable ||
					nodemgr->get(map->getNode(p + side + v3s16(0, 1, 0))).walkable) {
				if (flow.getLengthSQ() > 0.0f)
					flow.normalize();
				flow.Y -= 6.0f;
				break;
			}
		}
	}
	if (flow.getLengthSQ() > 0.0f)
		flow.normalize();
	return flow;
}

void LocalPlayer::updateWater(Map *map, const NodeDefManager *nodemgr, const v3f &position)
{
	water_depth = 0.0f;
	m_water_current = v3f(0.0f);
	const v3f min = position + m_collisionbox.MinEdge + 0.001f * BS;
	const v3f max = position + m_collisionbox.MaxEdge - 0.001f * BS;
	const v3s16 p0 = floatToInt(min, BS), p1 = floatToInt(max, BS);
	v3f flow;
	u32 count = 0;
	v3s16 p;
	for (p.X = p0.X; p.X <= p1.X; p.X++)
	for (p.Y = p0.Y; p.Y <= p1.Y; p.Y++)
	for (p.Z = p0.Z; p.Z <= p1.Z; p.Z++) {
		const MapNode n = map->getNode(p);
		const ContentFeatures &f = nodemgr->get(n);
		if (!is_water(f))
			continue;
		const f32 top = (p.Y - 0.5f + water_level(map, nodemgr, p, n, f)) * BS;
		if (top < min.Y)
			continue;
		water_depth = std::max(water_depth, (top - min.Y) / BS);
		// Minecraft weakens the flow of water shallower than 0.4 by its depth
		const v3f here = water_flow(map, nodemgr, p, n, f);
		flow += water_depth < 0.4f ? here * water_depth : here;
		count++;
	}
	// The current pushes 0.014 a tick on average, at least 0.0045 on a player at rest
	if (count > 0 && flow.getLengthSQ() > 1e-5f) {
		m_water_current = flow * (0.014f / count);
		if (std::fabs(m_speed.X) < 0.003f * 20.0f * BS && std::fabs(m_speed.Z) < 0.003f * 20.0f * BS &&
				m_water_current.getLength() < 0.0045f)
			m_water_current = m_water_current.normalize() * 0.0045f;
	}
}

void LocalPlayer::move(f32 dtime, Environment *env,
		std::vector<CollisionInfo> *collision_info)
{
	// Node at feet position, update each ClientEnvironment::step()
	if (!collision_info || collision_info->empty())
		m_standing_node = floatToInt(m_position, BS);

	// Temporary option for old move code
	if (!physics_override.new_move) {
		water_move = m_water_air = false;
		old_move(dtime, env, collision_info);
		return;
	}

	Map *map = &env->getMap();
	const NodeDefManager *nodemgr = m_client->ndef();

	v3f position = getPosition();

	// Copy parent position if local player is attached
	if (getParent()) {
		setPosition(m_cao->getPosition());
		m_added_velocity = v3f(0.0f); // ignored
		return;
	}

	PlayerSettings &player_settings = getPlayerSettings();

	// Skip collision detection if noclip mode is used
	bool fly_allowed = m_client->checkLocalPrivilege("fly");
	bool noclip = m_client->checkLocalPrivilege("noclip") && player_settings.noclip;
	bool free_move = player_settings.free_move && fly_allowed;

	if (noclip && free_move) {
		position += m_speed * dtime;
		setPosition(position);

		touching_ground = false;
		m_added_velocity = v3f(0.0f); // ignored
		return;
	}

	m_speed += m_added_velocity;
	m_added_velocity = v3f(0.0f);

	/*
		Collision detection
	*/

	bool is_valid_position;
	MapNode node;
	v3s16 pp;

	// Minecraft's water decides alone for its nodes: in it while any part of the box is
	updateWater(map, nodemgr, position);

	/*
		Check if player is in liquid (the oscillating value)
	*/

	// If in liquid, the threshold of coming out is at higher y
	if (water_depth > 0.0f) {
		in_liquid = true;
		move_resistance = 0;
	} else if (in_liquid)
	{
		pp = floatToInt(position + v3f(0.0f, BS * 0.1f, 0.0f), BS);
		node = map->getNode(pp, &is_valid_position);
		if (is_valid_position) {
			const ContentFeatures &cf = nodemgr->get(node.getContent());
			in_liquid = cf.liquid_move_physics && !is_water(cf);
			move_resistance = cf.move_resistance;
		} else {
			in_liquid = false;
		}
	} else {
		// If not in liquid, the threshold of going in is at lower y

		pp = floatToInt(position + v3f(0.0f, BS * 0.5f, 0.0f), BS);
		node = map->getNode(pp, &is_valid_position);
		if (is_valid_position) {
			const ContentFeatures &cf = nodemgr->get(node.getContent());
			in_liquid = cf.liquid_move_physics && !is_water(cf);
			move_resistance = cf.move_resistance;
		} else {
			in_liquid = false;
		}
	}


	/*
		Check if player is in liquid (the stable value)
	*/
	pp = floatToInt(position + v3f(0.0f), BS);
	node = map->getNode(pp, &is_valid_position);
	if (water_depth > 0.0f) {
		in_liquid_stable = true;
	} else if (is_valid_position) {
		const ContentFeatures &cf = nodemgr->get(node.getContent());
		in_liquid_stable = cf.liquid_move_physics && !is_water(cf);
	} else {
		in_liquid_stable = false;
	}

	/*
		Check if player is climbing
	*/

	pp = floatToInt(position + v3f(0.0f, 0.5f * BS, 0.0f), BS);
	v3s16 pp2 = floatToInt(position + v3f(0.0f, -0.2f * BS, 0.0f), BS);
	node = map->getNode(pp, &is_valid_position);
	bool is_valid_position2;
	MapNode node2 = map->getNode(pp2, &is_valid_position2);

	if (!(is_valid_position && is_valid_position2)) {
		is_climbing = false;
	} else {
		is_climbing = (nodemgr->get(node.getContent()).climbable ||
			nodemgr->get(node2.getContent()).climbable) && !free_move;
	}

	water_move = water_depth > 0.0f && !free_move && !is_climbing;

	// Player object property step height is multiplied by BS in
	// /src/script/common/c_content.cpp and /src/content_sao.cpp
	float player_stepheight = (m_cao == nullptr) ? 0.0f :
		(touching_ground ? m_cao->getStepHeight() : (0.2f * BS));

	// (BS * 0.6f) is the default stepheight while standing on ground
	const float sneak_stepheight = 0.6f * BS;

	v3f accel_f(0, -gravity, 0);
	const v3f initial_position = position;
	const v3f initial_speed = m_speed;


	StepUpMode step_up_mode = StepUpMode::LEGACY;
	if (m_cao != nullptr) {
		step_up_mode = m_cao->getProperties().step_up_mode;
	}

	CollisionMoveResult result = collisionMoveSimple(env, m_client,
		m_collisionbox, player_stepheight, dtime,
		&position, &m_speed, accel_f, m_cao, true, step_up_mode);

	// As in Minecraft, pushing on a wall at the surface lifts the player, at 0.3 a tick in its air,
	// when the box 0.6 higher (and a tick on) has no water and nothing solid
	if (water_move) {
		bool wall = false;
		for (const auto &colinfo : result.collisions)
			wall |= colinfo.type == COLLISION_NODE && colinfo.axis != COLLISION_AXIS_Y;
		if (wall && water_depth <= 0.6f + m_speed.Y / (20.0f * BS) &&
				!collision_check_intersection(env, m_client, m_collisionbox,
				position + v3f(0.0f, 0.6f * BS, 0.0f), m_cao))
			m_speed.Y = getAirSpeed(0.3f);
	}

	bool could_sneak = control.sneak && !free_move && !in_liquid &&
		!is_climbing && physics_override.sneak;

	// Add new collisions to the vector
	if (collision_info && !free_move) {
		v3f diff = intToFloat(m_standing_node, BS) - position;
		f32 distance_sq = diff.getLengthSQ();
		// Force update each ClientEnvironment::step()
		bool is_first = collision_info->empty();

		for (const auto &colinfo : result.collisions) {
			collision_info->push_back(colinfo);

			if (colinfo.type != COLLISION_NODE ||
					colinfo.axis != COLLISION_AXIS_Y ||
					(could_sneak && m_sneak_node_exists))
				continue;

			diff = intToFloat(colinfo.node_p, BS) - position;

			// Find nearest colliding node
			f32 len_sq = diff.getLengthSQ();
			if (is_first || len_sq < distance_sq) {
				m_standing_node = colinfo.node_p;
				distance_sq = len_sq;
				is_first = false;
			}
		}
	}

	/*
		If the player's feet touch the topside of any node
		at the END of clientstep, then this is set to true.

		Player is allowed to jump when this is true.
	*/
	bool touching_ground_was = touching_ground;
	touching_ground = result.touching_ground;
	bool sneak_can_jump = false;

	if (water_move)
		m_water_air = true;
	else if (touching_ground || free_move || is_climbing || in_liquid)
		m_water_air = false;

	// Max. distance (X, Z) over border for sneaking determined by collision box
	// * 0.49 to keep the center just barely on the node
	v3f sneak_max = m_collisionbox.getExtent() * 0.49f;

	if (m_sneak_ladder_detected) {
		// restore legacy behavior (this makes the m_speed.Y hack necessary)
		sneak_max = v3f(0.4f * BS, 0.0f, 0.4f * BS);
	}

	/*
		If sneaking, keep on top of last walked node and don't fall off
	*/
	if (could_sneak && m_sneak_node_exists) {
		const v3f sn_f = intToFloat(m_sneak_node, BS);
		const v3f bmin = sn_f + m_sneak_node_bb_top.MinEdge;
		const v3f bmax = sn_f + m_sneak_node_bb_top.MaxEdge;
		const v3f old_pos = position;
		const v3f old_speed = m_speed;
		f32 y_diff = bmax.Y - position.Y;
		m_standing_node = m_sneak_node;

		if (y_diff < sneak_stepheight) {
			// Only center player when they're on the node
			position.X = rangelim(position.X,
				bmin.X - sneak_max.X, bmax.X + sneak_max.X);
			position.Z = rangelim(position.Z,
				bmin.Z - sneak_max.Z, bmax.Z + sneak_max.Z);

			if (position.X != old_pos.X)
				m_speed.X = 0.0f;
			if (position.Z != old_pos.Z)
				m_speed.Z = 0.0f;
		}

		if (y_diff > 0 && m_speed.Y <= 0.0f) {
			// Move player to the maximal height when falling or when
			// the ledge is climbed on the next step.

			v3f check_pos = position;
			check_pos.Y += y_diff * dtime * 22.0f + BS * 0.01f;
			if (y_diff < sneak_stepheight || (physics_override.sneak_glitch
					&& !collision_check_intersection(env, m_client, m_collisionbox, check_pos, m_cao))) {
				// Smoothen the movement (based on 'position.Y = bmax.Y')
				position.Y = std::min(check_pos.Y, bmax.Y);
				m_speed.Y = 0.0f;
			}
		}

		// Allow jumping on node edges while sneaking
		if ((touching_ground && m_speed.Y == 0.0f) || m_sneak_ladder_detected)
			sneak_can_jump = true;

		if (collision_info &&
				m_speed.Y - old_speed.Y > BS) {
			// Collide with sneak node, report fall damage
			CollisionInfo sn_info;
			sn_info.node_p = m_sneak_node;
			sn_info.old_speed = old_speed;
			sn_info.new_speed = m_speed;
			collision_info->push_back(sn_info);
		}
	}

	/*
		Find the next sneak node if necessary
	*/
	bool new_sneak_node_exists = false;

	if (could_sneak)
		new_sneak_node_exists = updateSneakNode(map, position, sneak_max);

	/*
		Set new position but keep sneak node set
	*/
	setPosition(position);
	m_sneak_node_exists = new_sneak_node_exists;

	/*
		Report collisions
	*/

	if (!result.standing_on_object && !touching_ground_was && touching_ground) {
		m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::PLAYER_REGAIN_GROUND));

		// Set camera impact value to be used for view bobbing
		camera_impact = getSpeed().Y * -1;
	}

	/*
		Check properties of the node on which the player is standing
	*/
	const ContentFeatures &f = nodemgr->get(map->getNode(m_standing_node));
	const ContentFeatures &f1 = nodemgr->get(map->getNode(m_standing_node + v3s16(0, 1, 0)));

	// We can jump from a bouncy node we collided with this clientstep,
	// even if we are not "touching" it at the end of clientstep.
	int standing_node_bouncy = 0;
	if (result.collides && m_speed.Y > 0.0f) {
		// must use result.collisions here because sometimes collision_info
		// is passed in prepopulated with a problematic floor.
		for (const auto &colinfo : result.collisions) {
			if (colinfo.axis == COLLISION_AXIS_Y) {
				// we cannot rely on m_standing_node because "sneak stuff"
				standing_node_bouncy = itemgroup_get(nodemgr->get(map->getNode(colinfo.node_p)).groups, "bouncy");
				if (standing_node_bouncy != 0)
					break;
			}
		}
	}

	// Determine if jumping is possible
	m_disable_jump = itemgroup_get(f.groups, "disable_jump") ||
		itemgroup_get(f1.groups, "disable_jump");
	m_can_jump = ((touching_ground && !is_climbing) || sneak_can_jump || standing_node_bouncy != 0)
			&& !m_disable_jump;
	m_disable_descend = itemgroup_get(f.groups, "disable_descend") ||
		itemgroup_get(f1.groups, "disable_descend");

	// Jump/Sneak key pressed while bouncing from a bouncy block
	float jumpspeed = getJumpSpeed();
	if (m_can_jump && (control.jump || control.sneak) && standing_node_bouncy > 0) {
		// controllable (>0) bouncy block
		if (!control.jump) {
			// sneak pressed, but not jump
			// Subjective testing indicates 1/3 bounce decrease works well.
			jumpspeed = -m_speed.Y / 3.0f;
		} else {
			// jump pressed
			// Reduce boost when speed already is high
			jumpspeed = jumpspeed / (1.0f + (m_speed.Y * 2.8f / jumpspeed));
		}
		m_speed.Y += jumpspeed;
		setSpeed(m_speed);
		m_can_jump = false;
	} else if(m_speed.Y > jumpspeed && standing_node_bouncy < 0) {
		// uncontrollable bouncy is limited to normal jump height.
		m_can_jump = false;
	}

	// Prevent sliding on the ground when jump speed is 0
	m_can_jump = m_can_jump && jumpspeed != 0.0f;

	// Autojump
	handleAutojump(dtime, env, result, initial_position, initial_speed);
}

void LocalPlayer::move(f32 dtime, Environment *env)
{
	move(dtime, env, nullptr);
}

void LocalPlayer::applyControl(float dtime, Environment *env)
{
	// Clear stuff
	swimming_vertical = false;
	swimming_pitch = false;

	setPitch(control.pitch);
	setYaw(control.yaw);

	// Minecraft counts the wait between jumps only while jump is held
	m_jump_delay = control.jump ? m_jump_delay - dtime : 0.0f;

	// Nullify speed and don't run positioning code if the player is attached
	if (getParent()) {
		setSpeed(v3f(0.0f));
		return;
	}

	if (water_move) {
		applyWaterControl(dtime, env);
		return;
	}
	if (m_water_air && !touching_ground) {
		applyWaterAirControl(dtime);
		return;
	}

	PlayerSettings &player_settings = getPlayerSettings();

	// All vectors are relative to the player's yaw,
	// (and pitch if pitch move mode enabled),
	// and will be rotated at the end
	v3f speedH, speedV; // Horizontal (X, Z) and Vertical (Y)

	bool fly_allowed = m_client->checkLocalPrivilege("fly");
	bool fast_allowed = m_client->checkLocalPrivilege("fast");

	bool free_move = fly_allowed && player_settings.free_move;
	bool fast_move = fast_allowed && player_settings.fast_move;
	bool pitch_move = (free_move || in_liquid) && player_settings.pitch_move;
	// When aux1_descends is enabled the fast key is used to go down, so fast isn't possible
	bool fast_climb = fast_move && control.aux1 && !player_settings.aux1_descends;
	bool always_fly_fast = player_settings.always_fly_fast;

	// Whether superspeed mode is used or not
	bool superspeed = false;

	const f32 speed_walk = movement_speed_walk * physics_override.speed_walk;
	const f32 speed_fast = movement_speed_fast * physics_override.speed_fast;

	if (always_fly_fast && free_move && fast_move)
		superspeed = true;

	// Old descend control
	if (player_settings.aux1_descends) {
		// If free movement and fast movement, always move fast
		if (free_move && fast_move)
			superspeed = true;

		// Auxiliary button 1 (E)
		if (control.aux1) {
			if (free_move) {
				// In free movement mode, aux1 descends
				if (fast_move)
					speedV.Y = -speed_fast;
				else
					speedV.Y = -speed_walk;
			} else if ((in_liquid || in_liquid_stable) && !m_disable_descend) {
				speedV.Y = -speed_walk;
				swimming_vertical = true;
			} else if (is_climbing && !m_disable_descend) {
				speedV.Y = -movement_speed_climb * physics_override.speed_climb;
			} else {
				// If not free movement but fast is allowed, aux1 is
				// "Turbo button"
				if (fast_move)
					superspeed = true;
			}
		}
	} else {
		// New minecraft-like descend control

		// Auxiliary button 1 (E)
		if (control.aux1) {
			if (!is_climbing) {
				// aux1 is "Turbo button"
				if (fast_move)
					superspeed = true;
			}
		}

		if (control.sneak && !control.jump) {
			// Descend player in freemove mode, liquids and climbable nodes by sneak key, only if jump key is released
			if (free_move) {
				// In free movement mode, sneak descends
				if (fast_move && (control.aux1 || always_fly_fast))
					speedV.Y = -speed_fast;
				else
					speedV.Y = -speed_walk;
			} else if ((in_liquid || in_liquid_stable) && !m_disable_descend) {
				if (fast_climb)
					speedV.Y = -speed_fast;
				else
					speedV.Y = -speed_walk;
				swimming_vertical = true;
			} else if (is_climbing && !m_disable_descend) {
				if (fast_climb)
					speedV.Y = -speed_fast;
				else
					speedV.Y = -movement_speed_climb * physics_override.speed_climb;
			}
		}
	}

	speedH = v3f(std::sin(control.movement_direction), 0.0f,
			std::cos(control.movement_direction));

	if (m_autojump) {
		// release autojump after a given time
		m_autojump_time -= dtime;
		if (m_autojump_time <= 0.0f)
			m_autojump = false;
	}

	if (control.jump) {
		if (free_move) {
			if (!control.sneak) {
				// Don't fly up if sneak key is pressed
				if (player_settings.aux1_descends || always_fly_fast) {
					if (fast_move)
						speedV.Y = speed_fast;
					else
						speedV.Y = speed_walk;
				} else {
					if (fast_move && control.aux1)
						speedV.Y = speed_fast;
					else
						speedV.Y = speed_walk;
				}
			}
		} else if (m_can_jump) {
			/*
				NOTE: The d value in move() affects jump height by
				raising the height at which the jump speed is kept
				at its starting value
			*/
			v3f speedJ = getSpeed();
			if (speedJ.Y >= -0.5f * BS && m_jump_delay <= 0.0f) {
				speedJ.Y = std::max(getJumpSpeed(), speedJ.Y);
				setSpeed(speedJ);
				m_jump_delay = 0.5f;
				m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::PLAYER_JUMP));
			}
		} else if (in_liquid && !m_disable_jump && !control.sneak) {
			if (fast_climb)
				speedV.Y = speed_fast;
			else
				speedV.Y = speed_walk;
			swimming_vertical = true;
		} else if (is_climbing && !m_disable_jump && !control.sneak) {
			if (fast_climb)
				speedV.Y = speed_fast;
			else
				speedV.Y = movement_speed_climb * physics_override.speed_climb;
		}
	}

	// The speed of the player (Y is ignored)
	if (superspeed || (is_climbing && fast_climb) ||
			((in_liquid || in_liquid_stable) && fast_climb))
		speedH = speedH.normalize() * speed_fast;
	else if (control.sneak && !free_move && !in_liquid && !in_liquid_stable)
		speedH = speedH.normalize() * movement_speed_crouch * physics_override.speed_crouch;
	else
		speedH = speedH.normalize() * speed_walk;

	speedH *= control.movement_speed; /* Apply analog input */

	// Acceleration increase
	f32 incH = 0.0f; // Horizontal (X, Z)
	f32 incV = 0.0f; // Vertical (Y)
	if ((!touching_ground && !free_move && !is_climbing && !in_liquid) ||
			(!free_move && m_can_jump && control.jump)) {
		// Jumping and falling
		if (superspeed || (fast_move && control.aux1))
			incH = movement_acceleration_fast * physics_override.acceleration_fast * BS * dtime;
		else
			incH = movement_acceleration_air * physics_override.acceleration_air * BS * dtime;
		incV = 0.0f; // No vertical acceleration in air
	} else if (superspeed || (is_climbing && fast_climb) ||
			((in_liquid || in_liquid_stable) && fast_climb)) {
		incH = incV = movement_acceleration_fast * physics_override.acceleration_fast * BS * dtime;
	} else {
		incH = incV = movement_acceleration_default * physics_override.acceleration_default * BS * dtime;
	}

	float slip_factor = 1.0f;
	if (!free_move && !in_liquid && !in_liquid_stable)
		slip_factor = getSlipFactor(env, speedH);

	// Don't sink when swimming in pitch mode
	if (pitch_move && in_liquid) {
		v3f controlSpeed = speedH + speedV;
		if (controlSpeed.getLength() > 0.01f)
			swimming_pitch = true;
	}

	// Accelerate to target speed with maximum increment
	accelerate((speedH + speedV) * physics_override.speed,
		incH * physics_override.speed * slip_factor, incV * physics_override.speed,
		pitch_move);
}

v3s16 LocalPlayer::getStandingNodePos()
{
	if (m_sneak_node_exists)
		return m_sneak_node;

	return m_standing_node;
}

v3s16 LocalPlayer::getFootstepNodePos()
{
	v3f feet_pos = getPosition() + v3f(0.0f, m_collisionbox.MinEdge.Y, 0.0f);

	// Emit swimming sound if the player is in liquid
	if (in_liquid_stable)
		return floatToInt(feet_pos, BS);

	// BS * 0.05 below the player's feet ensures a 1/16th height
	// nodebox is detected instead of the node below it.
	if (touching_ground)
		return floatToInt(feet_pos - v3f(0.0f, BS * 0.05f, 0.0f), BS);

	// A larger distance below is necessary for a footstep sound
	// when landing after a jump or fall. BS * 0.5 ensures water
	// sounds when swimming in 1 node deep water.
	return floatToInt(feet_pos - v3f(0.0f, BS * 0.5f, 0.0f), BS);
}

v3s16 LocalPlayer::getLightPosition() const
{
	return floatToInt(m_position + v3f(0.0f, BS * 1.5f, 0.0f), BS);
}

v3f LocalPlayer::getEyeOffset() const
{
	return v3f(0.0f, BS * m_eye_height, 0.0f);
}

ClientActiveObject *LocalPlayer::getParent() const
{
	return m_cao ? m_cao->getParent() : nullptr;
}

bool LocalPlayer::isDead() const
{
	FATAL_ERROR_IF(!getCAO(), "LocalPlayer's CAO isn't initialized");
	return !getCAO()->isImmortal() && hp == 0;
}

// 3D acceleration
void LocalPlayer::accelerate(const v3f &target_speed, const f32 max_increase_H,
	const f32 max_increase_V, const bool use_pitch)
{
	const f32 yaw = getYaw();
	const f32 pitch = getPitch();
	v3f flat_speed = m_speed;
	// Rotate speed vector by -yaw and -pitch to make it relative to the player's yaw and pitch
	flat_speed.rotateXZBy(-yaw);
	if (use_pitch)
		flat_speed.rotateYZBy(-pitch);

	v3f d_wanted = target_speed - flat_speed;
	v3f d;

	// Then compare the horizontal and vertical components with the wanted speed
	if (max_increase_H > 0.0f) {
		v3f d_wanted_H = d_wanted * v3f(1.0f, 0.0f, 1.0f);
		if (d_wanted_H.getLength() > max_increase_H)
			d += d_wanted_H.normalize() * max_increase_H;
		else
			d += d_wanted_H;
	}

	if (max_increase_V > 0.0f) {
		f32 d_wanted_V = d_wanted.Y;
		if (d_wanted_V > max_increase_V)
			d.Y += max_increase_V;
		else if (d_wanted_V < -max_increase_V)
			d.Y -= max_increase_V;
		else
			d.Y += d_wanted_V;
	}

	// Finally rotate it again
	if (use_pitch)
		d.rotateYZBy(pitch);
	d.rotateXZBy(yaw);

	m_speed += d;
}

// Minecraft's water: each 20 Hz tick adds a push, then keeps a part of the speed.
// Done here as the same approach in continuous time, so any frame rate moves alike.
void LocalPlayer::applyWaterControl(float dtime, Environment *env)
{
	const bool swim = physics_override.swim;
	const f32 ticks = 20.0f * dtime;
	swimming_vertical = false;

	// Speed overrides only slow down in water (an item in use), as in Minecraft
	f32 input = control.movement_speed * std::min(physics_override.speed, 1.0f);
	if (control.sneak && !swim)
		input *= 0.3f;

	// v = (v + 0.02 * 0.98 * input + current) * keep: the speed goes to 20 * push / (1 - keep)
	const f32 keep_h = swim ? 0.9f : 0.8f;
	v3f target(std::sin(control.movement_direction), 0.0f, std::cos(control.movement_direction));
	target *= 0.0196f * input;
	target.rotateXZBy(getYaw());
	target += v3f(m_water_current.X, 0.0f, m_water_current.Z);
	target *= 20.0f / (1.0f - keep_h) * BS;
	const f32 left_h = std::pow(keep_h, ticks);
	m_speed.X = target.X + (m_speed.X - target.X) * left_h;
	m_speed.Z = target.Z + (m_speed.Z - target.Z) * left_h;

	// v = (v + steer * (look - v) + push) * 0.8 - sink
	f32 push = m_water_current.Y;
	if (control.jump && !m_disable_jump && (!touching_ground || water_depth > 0.4f)) {
		push += 0.04f;
		swimming_vertical = true;
	} else if (control.jump && m_can_jump && m_jump_delay <= 0.0f) {
		m_speed.Y = getJumpSpeed();
		m_jump_delay = 0.5f;
		m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::PLAYER_JUMP));
	}
	if (control.sneak && !m_disable_descend) {
		push -= 0.04f;
		swimming_vertical = true;
	}
	f32 steer = 0.0f, look = 0.0f;
	if (swim) {
		look = -std::sin(getPitch() * core::DEGTORAD);
		const MapNode n = env->getMap().getNode(floatToInt(m_position + v3f(0.0f, 0.9f * BS, 0.0f), BS));
		if (look <= 0.0f || control.jump || is_water(m_client->ndef()->get(n)))
			steer = look < -0.2f ? 0.085f : 0.06f;
		swimming_vertical = true;
	}
	const f32 sink = swim ? 0.0f : 0.005f;
	const f32 keep_v = 0.8f * (1.0f - steer);
	const f32 after = (0.8f * (steer * look + push) - sink) / (1.0f - keep_v);
	const f32 target_v = (after + sink) / 0.8f * 20.0f * BS;
	m_speed.Y = target_v + (m_speed.Y - target_v) * std::pow(keep_v, ticks);
}

// Airborne out of the water (bobbing at the surface): Minecraft's air, v = (v + 0.02 * input) * 0.91
void LocalPlayer::applyWaterAirControl(float dtime)
{
	const f32 input = control.movement_speed * std::min(physics_override.speed, 1.0f);
	v3f target(std::sin(control.movement_direction), 0.0f, std::cos(control.movement_direction));
	target *= 20.0f * 0.0196f * input / (1.0f - 0.91f) * BS;
	target.rotateXZBy(getYaw());
	const f32 left = std::pow(0.91f, 20.0f * dtime);
	m_speed.X = target.X + (m_speed.X - target.X) * left;
	m_speed.Z = target.Z + (m_speed.Z - target.Z) * left;
}

// Temporary option for old move code
void LocalPlayer::old_move(f32 dtime, Environment *env,
	std::vector<CollisionInfo> *collision_info)
{
	Map *map = &env->getMap();
	const NodeDefManager *nodemgr = m_client->ndef();

	v3f position = getPosition();

	// Copy parent position if local player is attached
	if (getParent()) {
		setPosition(m_cao->getPosition());
		m_sneak_node_exists = false;
		m_added_velocity = v3f(0.0f);
		return;
	}

	PlayerSettings &player_settings = getPlayerSettings();

	// Skip collision detection if noclip mode is used
	bool fly_allowed = m_client->checkLocalPrivilege("fly");
	bool noclip = m_client->checkLocalPrivilege("noclip") && player_settings.noclip;
	bool free_move = noclip && fly_allowed && player_settings.free_move;
	if (free_move) {
		position += m_speed * dtime;
		setPosition(position);

		touching_ground = false;
		m_sneak_node_exists = false;
		m_added_velocity = v3f(0.0f);
		return;
	}

	m_speed += m_added_velocity;
	m_added_velocity = v3f(0.0f);

	// Apply gravity (note: this is broken, but kept since this is *old* move code)
	m_speed.Y -= gravity * dtime;

	/*
		Collision detection
	*/
	bool is_valid_position;
	MapNode node;
	v3s16 pp;

	/*
		Check if player is in liquid (the oscillating value)
	*/
	if (in_liquid) {
		// If in liquid, the threshold of coming out is at higher y
		pp = floatToInt(position + v3f(0.0f, BS * 0.1f, 0.0f), BS);
		node = map->getNode(pp, &is_valid_position);
		if (is_valid_position) {
			const ContentFeatures &cf = nodemgr->get(node.getContent());
			in_liquid = cf.liquid_move_physics;
			move_resistance = cf.move_resistance;
		} else {
			in_liquid = false;
		}
	} else {
		// If not in liquid, the threshold of going in is at lower y
		pp = floatToInt(position + v3f(0.0f, BS * 0.5f, 0.0f), BS);
		node = map->getNode(pp, &is_valid_position);
		if (is_valid_position) {
			const ContentFeatures &cf = nodemgr->get(node.getContent());
			in_liquid = cf.liquid_move_physics;
			move_resistance = cf.move_resistance;
		} else {
			in_liquid = false;
		}
	}

	/*
		Check if player is in liquid (the stable value)
	*/
	pp = floatToInt(position + v3f(0.0f), BS);
	node = map->getNode(pp, &is_valid_position);
	if (is_valid_position)
		in_liquid_stable = nodemgr->get(node.getContent()).liquid_move_physics;
	else
		in_liquid_stable = false;

	/*
		Check if player is climbing
	*/
	pp = floatToInt(position + v3f(0.0f, 0.5f * BS, 0.0f), BS);
	v3s16 pp2 = floatToInt(position + v3f(0.0f, -0.2f * BS, 0.0f), BS);
	node = map->getNode(pp, &is_valid_position);
	bool is_valid_position2;
	MapNode node2 = map->getNode(pp2, &is_valid_position2);

	if (!(is_valid_position && is_valid_position2))
		is_climbing = false;
	else
		is_climbing = (nodemgr->get(node.getContent()).climbable ||
			nodemgr->get(node2.getContent()).climbable) && !free_move;

	// Maximum distance over border for sneaking
	f32 sneak_max = BS * 0.4f;

	/*
		If sneaking, keep in range from the last walked node and don't
		fall off from it
	*/
	if (control.sneak && m_sneak_node_exists &&
			!(fly_allowed && player_settings.free_move) && !in_liquid &&
			physics_override.sneak) {
		f32 maxd = 0.5f * BS + sneak_max;
		v3f lwn_f = intToFloat(m_sneak_node, BS);
		position.X = rangelim(position.X, lwn_f.X - maxd, lwn_f.X + maxd);
		position.Z = rangelim(position.Z, lwn_f.Z - maxd, lwn_f.Z + maxd);

		if (!is_climbing) {
			// Move up if necessary
			f32 new_y = (lwn_f.Y - 0.5f * BS) + m_sneak_node_bb_ymax;
			if (position.Y < new_y)
				position.Y = new_y;
			/*
				Collision seems broken, since player is sinking when
				sneaking over the edges of current sneaking_node.
				TODO (when fixed): Set Y-speed only to 0 when position.Y < new_y.
			*/
			if (m_speed.Y < 0.0f)
				m_speed.Y = 0.0f;
		}
	}

	// TODO: This shouldn't be hardcoded but decided by the server
	float player_stepheight = touching_ground ? (BS * 0.6f) : (BS * 0.2f);

	v3f accel_f;
	const v3f initial_position = position;
	const v3f initial_speed = m_speed;

	StepUpMode step_up_mode = StepUpMode::LEGACY;
	if (m_cao != nullptr) {
		step_up_mode = m_cao->getProperties().step_up_mode;
	}

	CollisionMoveResult result = collisionMoveSimple(env, m_client,
		m_collisionbox, player_stepheight, dtime,
		&position, &m_speed, accel_f, m_cao, true, step_up_mode);

	// Position was slightly changed; update standing node pos
	if (touching_ground)
		m_standing_node = floatToInt(m_position - v3f(0.0f, 0.1f * BS, 0.0f), BS);
	else
		m_standing_node = floatToInt(m_position, BS);

	/*
		If the player's feet touch the topside of any node
		at the END of clientstep, then this is set to true.

		Player is allowed to jump when this is true.
	*/
	bool touching_ground_was = touching_ground;
	touching_ground = result.touching_ground;

	//bool standing_on_unloaded = result.standing_on_unloaded;

	/*
		Check the nodes under the player to see from which node the
		player is sneaking from, if any. If the node from under
		the player has been removed, the player falls.
	*/
	f32 position_y_mod = 0.05f * BS;
	if (m_sneak_node_bb_ymax > 0.0f)
		position_y_mod = m_sneak_node_bb_ymax - position_y_mod;
	v3s16 current_node = floatToInt(position - v3f(0.0f, position_y_mod, 0.0f), BS);
	if (m_sneak_node_exists &&
			nodemgr->get(map->getNode(m_old_node_below)).name == "air" &&
			m_old_node_below_type != "air") {
		// Old node appears to have been removed; that is,
		// it wasn't air before but now it is
		m_need_to_get_new_sneak_node = false;
		m_sneak_node_exists = false;
	} else if (nodemgr->get(map->getNode(current_node)).name != "air") {
		// We are on something, so make sure to recalculate the sneak
		// node.
		m_need_to_get_new_sneak_node = true;
	}

	if (m_need_to_get_new_sneak_node && physics_override.sneak) {
		m_sneak_node_bb_ymax = 0.0f;
		v3s16 pos_i_bottom = floatToInt(position - v3f(0.0f, position_y_mod, 0.0f), BS);
		v2f player_p2df(position.X, position.Z);
		f32 min_distance_f = 100000.0f * BS;
		// If already seeking from some node, compare to it.
		v3s16 new_sneak_node = m_sneak_node;
		for (s16 x= -1; x <= 1; x++)
		for (s16 z= -1; z <= 1; z++) {
			v3s16 p = pos_i_bottom + v3s16(x, 0, z);
			v3f pf = intToFloat(p, BS);
			v2f node_p2df(pf.X, pf.Z);
			f32 distance_f = player_p2df.getDistanceFrom(node_p2df);
			f32 max_axis_distance_f = MYMAX(
				std::fabs(player_p2df.X - node_p2df.X),
				std::fabs(player_p2df.Y - node_p2df.Y));

			if (distance_f > min_distance_f ||
					max_axis_distance_f > 0.5f * BS + sneak_max + 0.1f * BS)
				continue;

			// The node to be sneaked on has to be walkable
			node = map->getNode(p, &is_valid_position);
			if (!is_valid_position || !nodemgr->get(node).walkable)
				continue;
			// And the node above it has to be nonwalkable
			node = map->getNode(p + v3s16(0, 1, 0), &is_valid_position);
			if (!is_valid_position || nodemgr->get(node).walkable)
				continue;
			// If not 'sneak_glitch' the node 2 nodes above it has to be nonwalkable
			if (!physics_override.sneak_glitch) {
				node = map->getNode(p + v3s16(0, 2, 0), &is_valid_position);
				if (!is_valid_position || nodemgr->get(node).walkable)
					continue;
			}

			min_distance_f = distance_f;
			new_sneak_node = p;
		}

		bool sneak_node_found = (min_distance_f < 100000.0f * BS * 0.9f);

		m_sneak_node = new_sneak_node;
		m_sneak_node_exists = sneak_node_found;

		if (sneak_node_found) {
			f32 cb_max = 0.0f;
			MapNode n = map->getNode(m_sneak_node);
			std::vector<aabb3f> nodeboxes;
			n.getCollisionBoxes(nodemgr, &nodeboxes);
			for (const auto &box : nodeboxes) {
				if (box.MaxEdge.Y > cb_max)
					cb_max = box.MaxEdge.Y;
			}
			m_sneak_node_bb_ymax = cb_max;
		}

		/*
			If sneaking, the player's collision box can be in air, so
			this has to be set explicitly
		*/
		if (sneak_node_found && control.sneak)
			touching_ground = true;
	}

	/*
		Set new position but keep sneak node set
	*/
	bool sneak_node_exists = m_sneak_node_exists;
	setPosition(position);
	m_sneak_node_exists = sneak_node_exists;

	/*
		Report collisions
	*/
	// Don't report if flying
	if (collision_info && !(player_settings.free_move && fly_allowed)) {
		for (const auto &info : result.collisions) {
			collision_info->push_back(info);
		}
	}

	if (!result.standing_on_object && !touching_ground_was && touching_ground) {
		m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::PLAYER_REGAIN_GROUND));
		// Set camera impact value to be used for view bobbing
		camera_impact = getSpeed().Y * -1.0f;
	}

	/*
		Update the node last under the player
	*/
	m_old_node_below = floatToInt(position - v3f(0.0f, BS / 2.0f, 0.0f), BS);
	m_old_node_below_type = nodemgr->get(map->getNode(m_old_node_below)).name;

	/*
		Check properties of the node on which the player is standing
	*/
	const ContentFeatures &f = nodemgr->get(map->getNode(getStandingNodePos()));

	// We can jump from a bouncy node we collided with this clientstep,
	// even if we are not "touching" it at the end of clientstep.
	int standing_node_bouncy = 0;
	if (result.collides && m_speed.Y > 0.0f) {
		// must use result.collisions here because sometimes collision_info
		// is passed in prepopulated with a problematic floor.
		for (const auto &colinfo : result.collisions) {
			if (colinfo.axis == COLLISION_AXIS_Y) {
				// we cannot rely on m_standing_node because "sneak stuff"
				standing_node_bouncy = itemgroup_get(nodemgr->get(map->getNode(colinfo.node_p)).groups, "bouncy");
				if (standing_node_bouncy != 0)
					break;
			}
		}
	}

	// Determine if jumping is possible
	m_disable_jump = itemgroup_get(f.groups, "disable_jump");
	m_can_jump = (touching_ground || standing_node_bouncy != 0) && !m_disable_jump;
	m_disable_descend = itemgroup_get(f.groups, "disable_descend");

	// Jump/Sneak key pressed while bouncing from a bouncy block
	float jumpspeed = movement_speed_jump * physics_override.jump;
	if (m_can_jump && (control.jump || control.sneak) && standing_node_bouncy > 0) {
		// controllable (>0) bouncy block
		if (!control.jump) {
			// sneak pressed, but not jump
			// Subjective testing indicates 1/3 bounce decrease works well.
			jumpspeed = -m_speed.Y / 3.0f;
		} else {
			// jump pressed
			// Reduce boost when speed already is high
			jumpspeed = jumpspeed / (1.0f + (m_speed.Y * 2.8f / jumpspeed));
		}
		m_speed.Y += jumpspeed;
		setSpeed(m_speed);
		m_can_jump = false;
	} else if(m_speed.Y > jumpspeed && standing_node_bouncy < 0) {
		// uncontrollable bouncy is limited to normal jump height.
		m_can_jump = false;
	}

	// Autojump
	handleAutojump(dtime, env, result, initial_position, initial_speed);
}

float LocalPlayer::getSlipFactor(Environment *env, const v3f &speedH)
{
	// Slip on slippery nodes
	const NodeDefManager *nodemgr = env->getGameDef()->ndef();
	Map *map = &env->getMap();
	const ContentFeatures &f = nodemgr->get(map->getNode(getStandingNodePos()));
	int slippery = 0;
	if (f.walkable)
		slippery = itemgroup_get(f.groups, "slippery");

	if (slippery >= 1) {
		if (speedH == v3f(0.0f))
			slippery *= 2;

		return core::clamp(1.0f / (slippery + 1), 0.001f, 1.0f);
	}
	return 1.0f;
}

void LocalPlayer::handleAutojump(f32 dtime, Environment *env,
	const CollisionMoveResult &result, v3f initial_position, v3f initial_speed)
{
	PlayerSettings &player_settings = getPlayerSettings();
	if (!player_settings.autojump)
		return;

	if (m_autojump)
		return;

	bool could_autojump =
		m_can_jump && !control.jump && !control.sneak && control.isMoving();

	if (!could_autojump)
		return;

	bool horizontal_collision = false;
	for (const auto &colinfo : result.collisions) {
		if (colinfo.type == COLLISION_NODE && colinfo.axis != COLLISION_AXIS_Y) {
			horizontal_collision = true;
			break; // one is enough
		}
	}

	// must be running against something to trigger autojumping
	if (!horizontal_collision)
		return;

	// check for nodes above
	v3f headpos_min = m_position + m_collisionbox.MinEdge * 0.99f;
	v3f headpos_max = m_position + m_collisionbox.MaxEdge * 0.99f;
	headpos_min.Y = headpos_max.Y; // top face of collision box
	v3s16 ceilpos_min = floatToInt(headpos_min, BS) + v3s16(0, 1, 0);
	v3s16 ceilpos_max = floatToInt(headpos_max, BS) + v3s16(0, 1, 0);
	const NodeDefManager *ndef = env->getGameDef()->ndef();
	bool is_position_valid;
	for (s16 z = ceilpos_min.Z; z <= ceilpos_max.Z; ++z) {
		for (s16 x = ceilpos_min.X; x <= ceilpos_max.X; ++x) {
			MapNode n = env->getMap().getNode(v3s16(x, ceilpos_max.Y, z), &is_position_valid);

			if (!is_position_valid)
				break;  // won't collide with the void outside
			if (n.getContent() == CONTENT_IGNORE)
				return; // players collide with ignore blocks -> same as walkable
			const ContentFeatures &f = ndef->get(n);
			if (f.walkable)
				return; // would bump head, don't jump
		}
	}

	float jumpspeed = getJumpSpeed();
	float peak_dtime = jumpspeed / gravity; // at the peak of the jump v = gt <=> t = v / g
	float jump_height = (jumpspeed - 0.5f * gravity * peak_dtime) * peak_dtime; // s = vt - 1/2 gt^2
	v3f jump_pos = initial_position + v3f(0.0f, jump_height, 0.0f);
	v3f jump_speed = initial_speed;

	StepUpMode step_up_mode = StepUpMode::LEGACY;
	if (m_cao != nullptr) {
		step_up_mode = m_cao->getProperties().step_up_mode;
	}

	// try at peak of jump, zero step height
	CollisionMoveResult jump_result = collisionMoveSimple(env, m_client,
		m_collisionbox, 0.0f, dtime, &jump_pos, &jump_speed, v3f(0.0f), m_cao, true,
		step_up_mode);

	// see if we can get a little bit farther horizontally if we had
	// jumped
	v3f run_delta = m_position - initial_position;
	run_delta.Y = 0.0f;
	v3f jump_delta = jump_pos - initial_position;
	jump_delta.Y = 0.0f;
	if (jump_delta.getLengthSQ() > run_delta.getLengthSQ() * 1.01f) {
		m_autojump = true;
		m_autojump_time = 0.1f;
	}
}
