// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2010-2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "camera.h"
#include "client.h"
#include "clientmap.h"     // MapDrawControl
#include "localplayer.h"
#include "player.h"
#include <cmath>
#include "client/renderingengine.h"
#include "client/content_cao.h"
#include "client/texturesource.h"
#include "settings.h"
#include "wieldmesh.h"
#include "hud_element.h"
#include "itemdef.h"
#include "itemgroup.h"
#include "noise.h"         // easeCurve
#include "mtevent.h"
#include "nodedef.h"
#include "util/numeric.h"
#include "constants.h"
#include "fontengine.h"
#include "script/scripting_client.h"
#include "gettext.h"

#include <ICameraSceneNode.h>
#include <IGUIFont.h>
#include <ISceneNode.h>
#include <IVideoDriver.h>
#include <SViewFrustum.h>

static constexpr f32 CAMERA_OFFSET_STEP = 200;

#define WIELDMESH_OFFSET_X 55.0f
#define WIELDMESH_OFFSET_Y -35.0f
#define WIELDMESH_AMPLITUDE_X 7.0f
#define WIELDMESH_AMPLITUDE_Y 10.0f

// The wield scene's vertical FOV: Minecraft's 70 degrees for the hand, as wide as on 16:9 on narrower screens
static f32 wield_fov_y(f32 aspect)
{
	return 2 * std::atan(std::tan(35.0f * core::DEGTORAD) * std::max(1.0f, 16.0f / 9.0f / aspect));
}

static core::matrix4 rotation(f32 x, f32 y, f32 z)
{
	core::matrix4 m;
	m.setRotationDegrees(v3f(x, y, z));
	return m;
}

static core::matrix4 translation(f32 x, f32 y, f32 z)
{
	core::matrix4 m;
	m.setTranslation(v3f(x, y, z));
	return m;
}

static core::matrix4 scaling(f32 k)
{
	core::matrix4 m;
	m.setScale(v3f(k));
	return m;
}

// Minecraft is right-handed, looking down -z; Irrlicht left-handed, looking down +z
static core::matrix4 flip_z(core::matrix4 m)
{
	for (int i = 0; i < 4; i++) {
		m[i * 4 + 2] = -m[i * 4 + 2];
		m[8 + i] = -m[8 + i];
	}
	return m;
}

// An arm of the player's model at its shoulder, turned out by 0.1 radian as Minecraft draws a hand
static core::matrix4 arm_part(bool left)
{
	return translation((left ? 5 : -5) / 16.0f, 2 / 16.0f, 0) *
			rotation(0, 0, (left ? -0.1f : 0.1f) * core::RADTODEG);
}

// Minecraft's empty right arm (renderPlayerArm): p is the swing's progress, equip how far it is lowered
static core::matrix4 player_arm(f32 p, f32 equip)
{
	const f32 s = std::sin(std::sqrt(p) * M_PI), s2 = std::sin(std::sqrt(p) * 2 * M_PI);
	return translation(-0.3f * s + 0.64f, 0.4f * s2 - 0.6f - 0.6f * equip, -0.4f * std::sin(p * M_PI) - 0.72f) *
			rotation(0, 45 + 70 * s, 0) * rotation(0, 0, -20 * std::sin(p * p * M_PI)) *
			translation(-1, 3.6f, 3.5f) * rotation(0, 0, 120) * rotation(200, 0, 0) *
			rotation(0, -135, 0) * translation(5.6f, 0, 0) * arm_part(false);
}

// An arm reaching up to a map held in both hands (renderMapHand)
static core::matrix4 map_hand(bool left)
{
	const f32 f = left ? -1 : 1;
	return rotation(0, 92, 0) * rotation(45, 0, 0) * rotation(0, 0, -41 * f) *
			translation(0.3f * f, -1.1f, 0.45f) * arm_part(left);
}

// A map in both hands lies flat looking ahead and faces the eyes from 49.5 degrees down
static f32 map_tilt(f32 pitch)
{
	const f32 f = rangelim(1 - pitch / 45 + 0.1f, 0.0f, 1.0f);
	return -std::cos(f * M_PI) * 0.5f + 0.5f;
}

// From a map's pixels (128 a side, y down) to the map in hand (renderMap)
static core::matrix4 map_pixels()
{
	return rotation(0, 180, 0) * rotation(0, 0, 180) * scaling(0.38f) * translation(-0.5f, -0.5f, 0) *
			scaling(1 / 128.0f);
}

// The skin of the local player's model, for the arm
static std::string arm_skin(Client *client)
{
	GenericCAO *cao = client->getEnv().getLocalPlayer()->getCAO();
	if (cao && !cao->getProperties().textures.empty())
		return cao->getProperties().textures[0];
	return "character.png";
}

static const char *setting_names[] = {
	"view_bobbing_amount", "fov", "arm_inertia",
	"show_nametag_backgrounds", "offhand_position", "offhand_rotation",
	"offhand_raised_position", "offhand_raised_rotation",
};

Camera::Camera(MapDrawControl &draw_control, Client *client, RenderingEngine *rendering_engine):
	m_draw_control(draw_control),
	m_client(client),
	m_camera_mode(CAMERA_MODE_FIRST),
	m_player_light_color(0xFFFFFFFF)
{
	auto smgr = rendering_engine->get_scene_manager();
	// note: making the camera node a child of the player node
	// would lead to unexpected behavior, so we don't do that.
	m_playernode = smgr->addEmptySceneNode(smgr->getRootSceneNode());
	m_headnode = smgr->addEmptySceneNode(m_playernode);
	m_cameranode = smgr->addCameraSceneNode(smgr->getRootSceneNode());
	m_cameranode->bindTargetAndRotation(true);

	// This needs to be in its own scene manager. It is drawn after
	// all other 3D scene nodes and before the GUI.
	m_wieldmgr = smgr->createNewSceneManager();
	m_wieldmgr->addCameraSceneNode();
	m_wieldnode = new WieldMeshSceneNode(m_wieldmgr, -1);
	m_wieldnode->setItem(ItemStack(), m_client);
	m_wieldnode->drop(); // m_wieldmgr grabbed it
	m_offhand_node = new WieldMeshSceneNode(m_wieldmgr, -1);
	m_offhand_node->setItem(ItemStack(), m_client);
	m_offhand_node->setVisible(false);
	m_offhand_node->drop();
	m_left_arm = new WieldMeshSceneNode(m_wieldmgr, -1);
	m_left_arm->setItem(ItemStack(), m_client);
	m_left_arm->setVisible(false);
	m_left_arm->drop();

	m_nametags.clear();

	readSettings();
	for (auto name : setting_names)
		g_settings->registerChangedCallback(name, settingChangedCallback, this);
}

void Camera::settingChangedCallback(const std::string &name, void *data)
{
	static_cast<Camera *>(data)->readSettings();
}

void Camera::readSettings()
{
	/* TODO: Local caching of settings is not optimal and should at some stage
	 *       be updated to use a global settings object for getting thse values
	 *       (as opposed to the this local caching). This can be addressed in
	 *       a later release.
	 */
	m_cache_view_bobbing_amount = g_settings->getFloat("view_bobbing_amount", 0.0f, 7.9f);
	// 45 degrees is the lowest FOV that doesn't cause the server to treat this
	// as a zoom FOV and load world beyond the set server limits.
	m_cache_fov                 = g_settings->getFloat("fov", 45.0f, 160.0f);
	m_arm_inertia               = g_settings->getBool("arm_inertia");
	m_show_nametag_backgrounds  = g_settings->getBool("show_nametag_backgrounds");
	m_offhand_position[0] = g_settings->getV3F("offhand_position").value_or(v3f(-41, -32, 65));
	m_offhand_rotation[0] = g_settings->getV3F("offhand_rotation").value_or(v3f(0, -25, 0));
	m_offhand_position[1] = g_settings->getV3F("offhand_raised_position").value_or(v3f(-22, -18, 50));
	m_offhand_rotation[1] = g_settings->getV3F("offhand_raised_rotation").value_or(v3f(0, 10, 0));
}

Camera::~Camera()
{
	g_settings->deregisterAllChangedCallbacks(this);
	m_wieldmgr->drop();
}

v3f Camera::getHeadPosition() const
{
	return m_headnode->getAbsolutePosition();
}

void Camera::notifyFovChange()
{
	LocalPlayer *player = m_client->getEnv().getLocalPlayer();
	assert(player);

	PlayerFovSpec spec = player->getFov();

	// Remember old FOV in case a transition is wanted
	f32 m_old_fov_degrees = m_fov_transition_active
		? m_curr_fov_degrees // FOV is overridden with transition
		: m_server_sent_fov
			? m_target_fov_degrees // FOV is overridden without transition
			: m_cache_fov; // FOV is not overridden

	m_server_sent_fov = spec.fov > 0.0f;
	m_target_fov_degrees = m_server_sent_fov
		? spec.is_multiplier
			? m_cache_fov * spec.fov // apply multiplier to client-set FOV
			: spec.fov // absolute override
		: m_cache_fov; // reset to client-set FOV

	m_fov_transition_active = spec.transition_time > 0.0f;
	if (m_fov_transition_active) {
		m_transition_time = spec.transition_time;
		m_fov_diff = m_target_fov_degrees - m_old_fov_degrees;
	}
}

// Returns the fractional part of x
inline f32 my_modf(f32 x)
{
	float dummy;
	return std::modf(x, &dummy);
}

void Camera::step(f32 dtime)
{
	bool was_under_zero = m_wield_change_timer < 0;
	m_wield_change_timer = MYMIN(m_wield_change_timer + dtime, 0.125);

	// swapped by the next update(), which poses it before it is drawn
	if (m_wield_change_timer >= 0 && was_under_zero)
		m_wield_swap = true;

	if (m_view_bobbing_state != 0)
	{
		//f32 offset = dtime * m_view_bobbing_speed * 0.035;
		f32 offset = dtime * m_view_bobbing_speed * 0.030;
		if (m_view_bobbing_state == 2) {
			// Animation is getting turned off
			if (m_view_bobbing_anim < 0.25) {
				m_view_bobbing_anim -= offset;
			} else if (m_view_bobbing_anim > 0.75) {
				m_view_bobbing_anim += offset;
			} else if (m_view_bobbing_anim < 0.5) {
				m_view_bobbing_anim += offset;
				if (m_view_bobbing_anim > 0.5)
					m_view_bobbing_anim = 0.5;
			} else {
				m_view_bobbing_anim -= offset;
				if (m_view_bobbing_anim < 0.5)
					m_view_bobbing_anim = 0.5;
			}

			if (m_view_bobbing_anim <= 0 || m_view_bobbing_anim >= 1 ||
					fabs(m_view_bobbing_anim - 0.5) < 0.01) {
				m_view_bobbing_anim = 0;
				m_view_bobbing_state = 0;
			}
		}
		else {
			float was = m_view_bobbing_anim;
			m_view_bobbing_anim = my_modf(m_view_bobbing_anim + offset);
			bool step = (was == 0 ||
					(was < 0.5f && m_view_bobbing_anim >= 0.5f) ||
					(was > 0.5f && m_view_bobbing_anim <= 0.5f));
			if(step) {
				m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::VIEW_BOBBING_STEP));
			}
		}
	}

	if (m_digging_button != -1) {
		// A swing takes 0.3 s; one that goes on digging snaps back in 0.05 s
		f32 offset = dtime * (m_digging_snap ? 10.0f : 1.0f / 0.3f);
		float m_digging_anim_was = m_digging_anim;
		m_digging_anim += offset;
		if (m_digging_anim >= 1)
		{
			m_digging_anim = 0;
			m_digging_button = -1;
			m_digging_snap = false;
		}
		float lim = 0.15;
		if(m_digging_anim_was < lim && m_digging_anim >= lim)
		{
			if (m_digging_button == 0) {
				m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::CAMERA_PUNCH_LEFT));
			} else if(m_digging_button == 1) {
				m_client->getEventManager()->put(new SimpleTriggerEvent(MtEvent::CAMERA_PUNCH_RIGHT));
			}
		}
	}
}

static inline v2f dir(const v2f &pos_dist)
{
	f32 x = pos_dist.X - WIELDMESH_OFFSET_X;
	f32 y = pos_dist.Y - WIELDMESH_OFFSET_Y;

	f32 x_abs = std::fabs(x);
	f32 y_abs = std::fabs(y);

	if (x_abs >= y_abs) {
		y *= (1.0f / x_abs);
		x /= x_abs;
	}

	if (y_abs >= x_abs) {
		x *= (1.0f / y_abs);
		y /= y_abs;
	}

	return v2f(std::fabs(x), std::fabs(y));
}

void Camera::addArmInertia(f32 player_yaw)
{
	m_cam_vel.X = std::fabs(rangelim(m_last_cam_pos.X - player_yaw,
		-100.0f, 100.0f) / 0.016f) * 0.01f;
	m_cam_vel.Y = std::fabs((m_last_cam_pos.Y - m_camera_direction.Y) / 0.016f);
	f32 gap_X = std::fabs(WIELDMESH_OFFSET_X - m_wieldmesh_offset.X);
	f32 gap_Y = std::fabs(WIELDMESH_OFFSET_Y - m_wieldmesh_offset.Y);

	if (m_cam_vel.X > 1.0f || m_cam_vel.Y > 1.0f) {
		/*
		    The arm moves relative to the camera speed,
		    with an acceleration factor.
		*/

		if (m_cam_vel.X > 1.0f) {
			if (m_cam_vel.X > m_cam_vel_old.X)
				m_cam_vel_old.X = m_cam_vel.X;

			f32 acc_X = 0.12f * (m_cam_vel.X - (gap_X * 0.1f));
			m_wieldmesh_offset.X += m_last_cam_pos.X < player_yaw ? acc_X : -acc_X;

			if (m_last_cam_pos.X != player_yaw)
				m_last_cam_pos.X = player_yaw;

			m_wieldmesh_offset.X = rangelim(m_wieldmesh_offset.X,
				WIELDMESH_OFFSET_X - (WIELDMESH_AMPLITUDE_X * 0.5f),
				WIELDMESH_OFFSET_X + (WIELDMESH_AMPLITUDE_X * 0.5f));
		}

		if (m_cam_vel.Y > 1.0f) {
			if (m_cam_vel.Y > m_cam_vel_old.Y)
				m_cam_vel_old.Y = m_cam_vel.Y;

			f32 acc_Y = 0.12f * (m_cam_vel.Y - (gap_Y * 0.1f));
			m_wieldmesh_offset.Y +=
				m_last_cam_pos.Y > m_camera_direction.Y ? acc_Y : -acc_Y;

			if (m_last_cam_pos.Y != m_camera_direction.Y)
				m_last_cam_pos.Y = m_camera_direction.Y;

			m_wieldmesh_offset.Y = rangelim(m_wieldmesh_offset.Y,
				WIELDMESH_OFFSET_Y - (WIELDMESH_AMPLITUDE_Y * 0.5f),
				WIELDMESH_OFFSET_Y + (WIELDMESH_AMPLITUDE_Y * 0.5f));
		}

		m_arm_dir = dir(m_wieldmesh_offset);
	} else {
		/*
		    Now the arm gets back to its default position when the camera stops,
		    following a vector, with a smooth deceleration factor.
		*/

		f32 dec_X = 0.35f * (std::min(15.0f, m_cam_vel_old.X) * (1.0f +
			(1.0f - m_arm_dir.X))) * (gap_X / 20.0f);

		f32 dec_Y = 0.25f * (std::min(15.0f, m_cam_vel_old.Y) * (1.0f +
			(1.0f - m_arm_dir.Y))) * (gap_Y / 15.0f);

		if (gap_X < 0.1f)
			m_cam_vel_old.X = 0.0f;

		m_wieldmesh_offset.X -=
			m_wieldmesh_offset.X > WIELDMESH_OFFSET_X ? dec_X : -dec_X;

		if (gap_Y < 0.1f)
			m_cam_vel_old.Y = 0.0f;

		m_wieldmesh_offset.Y -=
			m_wieldmesh_offset.Y > WIELDMESH_OFFSET_Y ? dec_Y : -dec_Y;
	}
}

void Camera::updateOffset()
{
	v3f cp = m_camera_position / BS;

	// Update offset if too far away from the center of the map
	m_camera_offset = v3s16(
		floorf(cp.X / CAMERA_OFFSET_STEP) * CAMERA_OFFSET_STEP,
		floorf(cp.Y / CAMERA_OFFSET_STEP) * CAMERA_OFFSET_STEP,
		floorf(cp.Z / CAMERA_OFFSET_STEP) * CAMERA_OFFSET_STEP
	);

	// No need to update m_cameranode as that will be done before the next render.
}

void Camera::update(LocalPlayer* player, f32 frametime, f32 tool_reload_ratio)
{
	// Get player position
	// Smooth the movement when walking up stairs
	v3f old_player_position = m_playernode->getPosition();
	v3f player_position = player->getPosition();

	f32 yaw = player->getYaw();
	f32 pitch = player->getPitch();

	// This is worse than `LocalPlayer::getPosition()` but
	// mods expect the player head to be at the parent's position
	// plus eye height.
	if (player->getParent())
		player_position = player->getParent()->getPosition();

	// Smooth the camera movement after the player instantly moves upward due to stepheight.
	// The smoothing usually continues until the camera position reaches the player position.
	float player_stepheight = player->getCAO() ? player->getCAO()->getStepHeight() : HUGE_VALF;
	float upward_movement = player_position.Y - old_player_position.Y;
	if (upward_movement < 0.01f || upward_movement > player_stepheight) {
		m_stepheight_smooth_active = false;
	} else if (player->touching_ground) {
		m_stepheight_smooth_active = true;
	}
	if (m_stepheight_smooth_active) {
		f32 oldy = old_player_position.Y;
		f32 newy = player_position.Y;
		f32 t = std::exp(-23 * frametime);
		player_position.Y = oldy * t + newy * (1-t);
	}

	// Set player node transformation
	m_playernode->setPosition(player_position);
	m_playernode->setRotation(v3f(0, -1 * yaw, 0));
	m_playernode->updateAbsolutePosition();

	// Get camera tilt timer (hurt animation)
	float cameratilt = fabs(fabs(player->hurt_tilt_timer-0.75)-0.75);

	// Calculate and translate the head SceneNode offsets
	{
		v3f eye_offset = player->getEyeOffset();
		switch(m_camera_mode) {
		case CAMERA_MODE_ANY:
		case CameraMode_END:
			assert(false);
			break;
		case CAMERA_MODE_FIRST:
			eye_offset += player->eye_offset_first;
			break;
		case CAMERA_MODE_THIRD:
			eye_offset += player->eye_offset_third;
			break;
		case CAMERA_MODE_THIRD_FRONT:
			eye_offset.X += player->eye_offset_third_front.X;
			eye_offset.Y += player->eye_offset_third_front.Y;
			eye_offset.Z -= player->eye_offset_third_front.Z;
			break;
		}

		// Set head node transformation
		eye_offset.Y += cameratilt * -player->hurt_tilt_strength;
		m_headnode->setPosition(eye_offset);
		m_headnode->setRotation(v3f(pitch, 0,
			cameratilt * player->hurt_tilt_strength));
		m_headnode->updateAbsolutePosition();
	}


	// Compute relative camera position and target
	v3f rel_cam_pos = v3f(0,0,0);
	v3f rel_cam_target = v3f(0,0,1);
	v3f rel_cam_up = v3f(0,1,0);

	if (m_cache_view_bobbing_amount != 0.0f && m_view_bobbing_anim != 0.0f &&
		m_camera_mode < CAMERA_MODE_THIRD) {
		f32 bobfrac = my_modf(m_view_bobbing_anim * 2);
		f32 bobdir = (m_view_bobbing_anim < 0.5) ? 1.0 : -1.0;

		f32 bobknob = 1.2;
		f32 bobtmp = std::sin(std::pow(bobfrac, bobknob) * M_PI);

		v3f bobvec = v3f(
			0.3 * bobdir * std::sin(bobfrac * M_PI),
			-0.28 * bobtmp * bobtmp,
			0.);

		rel_cam_pos += bobvec * m_cache_view_bobbing_amount;
		rel_cam_target += bobvec * m_cache_view_bobbing_amount;
		rel_cam_up.rotateXYBy(-0.03 * bobdir * bobtmp * M_PI * m_cache_view_bobbing_amount);
	}

	// Compute absolute camera position and target
	m_headnode->getAbsoluteTransformation().transformVect(m_camera_position, rel_cam_pos);
	m_camera_direction = m_headnode->getAbsoluteTransformation()
			.rotateAndScaleVect(rel_cam_target - rel_cam_pos);

	v3f abs_cam_up = m_headnode->getAbsoluteTransformation()
			.rotateAndScaleVect(rel_cam_up);

	// Reposition the camera for third person view
	if (m_camera_mode > CAMERA_MODE_FIRST)
	{
		v3f my_cp = m_camera_position;

		if (m_camera_mode == CAMERA_MODE_THIRD_FRONT)
			m_camera_direction *= -1;

		my_cp.Y += 2;

		// Calculate new position
		bool abort = false;
		for (int i = BS; i <= BS * 2.75; i++) {
			my_cp.X = m_camera_position.X + m_camera_direction.X * -i;
			my_cp.Z = m_camera_position.Z + m_camera_direction.Z * -i;
			if (i > 12)
				my_cp.Y = m_camera_position.Y + (m_camera_direction.Y * -i);

			// Prevent camera positioned inside nodes
			const NodeDefManager *nodemgr = m_client->ndef();
			MapNode n = m_client->getEnv().getClientMap()
				.getNode(floatToInt(my_cp, BS));

			const ContentFeatures& features = nodemgr->get(n);
			if (features.walkable) {
				my_cp.X += m_camera_direction.X*-1*-BS/2;
				my_cp.Z += m_camera_direction.Z*-1*-BS/2;
				my_cp.Y += m_camera_direction.Y*-1*-BS/2;
				abort = true;
				break;
			}
		}

		// If node blocks camera position don't move y to height
		if (abort && my_cp.Y > player_position.Y+BS*2)
			my_cp.Y = player_position.Y+BS*2;

		// update the camera position in third-person mode to render blocks behind player
		// and correctly apply liquid post FX.
		m_camera_position = my_cp;
	}

	// Set camera node transformation
	m_cameranode->setPosition(m_camera_position - intToFloat(m_camera_offset, BS));
	m_cameranode->setUpVector(abs_cam_up);
	m_cameranode->updateAbsolutePosition();
	// *100 helps in large map coordinates
	m_cameranode->setTarget(m_camera_position - intToFloat(m_camera_offset, BS)
		+ 100 * m_camera_direction);

	/*
	 * Apply server-sent FOV, instantaneous or smooth transition.
	 * If not, check for zoom and set to zoom FOV.
	 * Otherwise, default to m_cache_fov.
	 */
	if (m_fov_transition_active) {
		// Smooth FOV transition
		// Dynamically calculate FOV delta based on frametimes
		f32 delta = (frametime / m_transition_time) * m_fov_diff;
		m_curr_fov_degrees += delta;

		// Mark transition as complete if target FOV has been reached
		if ((m_fov_diff > 0.0f && m_curr_fov_degrees >= m_target_fov_degrees) ||
				(m_fov_diff < 0.0f && m_curr_fov_degrees <= m_target_fov_degrees)) {
			m_fov_transition_active = false;
			m_curr_fov_degrees = m_target_fov_degrees;
		}
	} else if (m_server_sent_fov) {
		// Instantaneous FOV change
		m_curr_fov_degrees = m_target_fov_degrees;
	} else if (player->getPlayerControl().zoom && player->getZoomFOV() > 0.001f) {
		// Player requests zoom, apply zoom FOV
		m_curr_fov_degrees = player->getZoomFOV();
	} else {
		// Set to client's selected FOV
		m_curr_fov_degrees = m_cache_fov;
	}
	m_curr_fov_degrees = rangelim(m_curr_fov_degrees, 1.0f, 160.0f);

	// FOV and aspect ratio
	const v2u32 &window_size = RenderingEngine::getWindowSize();
	m_aspect = (f32) window_size.X / (f32) window_size.Y;
	m_fov_y = m_curr_fov_degrees * M_PI / 180.0;
	// Increase vertical FOV on lower aspect ratios (<16:10)
	m_fov_y *= core::clamp(sqrt(16./10. / m_aspect), 1.0, 1.4);
	m_fov_x = 2 * atan(m_aspect * tan(0.5 * m_fov_y));
	m_cameranode->setAspectRatio(m_aspect);
	m_cameranode->setFOV(m_fov_y);

	// Make new matrices and frustum
	m_cameranode->updateMatrices();

	if (m_arm_inertia)
		addArmInertia(yaw);

	if (m_wield_swap) {
		m_wield_swap = false;
		updateWieldedTool();
	}

	// The wielded item or the empty arm as Minecraft draws them in first person
	// (ItemInHandRenderer, and the item models' firstperson_righthand display), in blocks of
	// 75 units for a node mesh (30 units at Minecraft's scale 0.4) and 40 / 0.68 otherwise (an
	// extruded image is 40 units at 0.68); the punch reload lowers the arm by up to 0.6 block,
	// a map by 1.2
	const bool node = m_wieldnode->isNodeMesh();
	const f32 block = node ? 75.0f : 40.0f / 0.68f;
	const f32 step = 8.0f * frametime;
	m_wield_height += rangelim(std::pow(tool_reload_ratio, 3.0f) - m_wield_height, -step, step);
	const f32 equip = 1.0f - m_wield_height, lower = 0.6f * equip;
	const f32 p = m_digging_button != -1 ? m_digging_anim : 0.0f;
	const f32 s = std::sin(std::sqrt(p) * M_PI), s2 = std::sin(std::sqrt(p) * 2 * M_PI);
	const f32 sp = std::sin(p * M_PI), spp = std::sin(p * p * M_PI);
	const bool two_hands = m_offhand_name.empty();
	core::matrix4 m, left, map;
	if (m_wield_map && two_hands) {
		// both arms hold it up, lower and flatter the higher the player looks (renderTwoHandedMap)
		const f32 tilt = map_tilt(pitch);
		const core::matrix4 hold = translation(0, 0.1f * sp, -0.4f * s) *
				translation(0, 0.04f - 1.2f * equip - 0.5f * tilt, -0.72f) * rotation(-85 * tilt, 0, 0);
		m = hold * rotation(0, 90, 0) * map_hand(false);
		left = hold * rotation(0, 90, 0) * map_hand(true);
		map = hold * rotation(20 * s, 0, 0) * scaling(2) * map_pixels();
	} else if (m_wield_map) {
		// small at the right, the left hand holding something else (renderOneHandedMap)
		const core::matrix4 side = translation(0.125f, -0.125f, 0);
		m = side * rotation(0, 0, 10) * player_arm(p, equip);
		map = side * translation(0.51f, -0.08f - 1.2f * equip, -0.75f) *
				translation(-0.5f * s, 0.4f * s2 - 0.3f * s, -0.3f * sp) *
				rotation(-45 * s, 0, 0) * rotation(0, -30 * s, 0) * map_pixels();
	} else if (m_wieldnode->isArm()) {
		m = player_arm(p, equip);
	} else {
		m = translation(-0.4f * s, 0.2f * s2, -0.2f * sp) *
				translation(0.56f, -0.52f - lower, -0.72f) *
				rotation(0, 45 - 20 * spp, 0) * rotation(0, 0, -20 * s) * rotation(-80 * s, 0, 0) *
				rotation(0, -45, 0);
		if (node)
			m = m * rotation(0, 45, 0);
		else
			m = m * translation(1.13f / 16, 3.2f / 16, 1.13f / 16) * rotation(0, -90, 0) * rotation(0, 0, 25);
	}
	m = flip_z(m);
	v3f shift(m_wieldmesh_offset.X - WIELDMESH_OFFSET_X, m_wieldmesh_offset.Y - WIELDMESH_OFFSET_Y, 0);
	shift.Y += std::abs(m_wield_change_timer)*320 - 40;
	if (m_digging_button == -1) {
		f32 bobfrac = my_modf(m_view_bobbing_anim);
		shift.X -= std::sin(bobfrac*M_PI*2.0) * 3.0;
		shift.Y += std::sin(my_modf(bobfrac*2.0)*M_PI) * 3.0;
	}
	// an item is a pixel thick in Minecraft, a tenth of its size in the extruded mesh
	m_wieldnode->setScale(v3f(1, 1, node || m_wieldnode->isArm() ? 1 : 0.625f));
	m_wieldnode->setPosition(m.getTranslation() * block + shift);
	m_wieldnode->setRotation(m.getRotationDegrees());
	m_left_arm->setVisible(m_wield_map && two_hands);
	if (m_wield_map) {
		left = flip_z(left);
		m_left_arm->setPosition(left.getTranslation() * block + shift);
		m_left_arm->setRotation(left.getRotationDegrees());
		m_map_matrix = translation(shift.X, shift.Y, shift.Z) * scaling(block) * flip_z(map);
		updateMapImages(player);
	}

	if (m_wieldnode->isArm() && arm_skin(m_client) != m_arm_skin)
		updateWieldedTool();
	m_player_light_color = player->light_color;
	m_wieldnode->setLightColorAndAnimation(m_player_light_color,
			m_client->getAnimationTime());
	m_left_arm->setLightColorAndAnimation(m_player_light_color, m_client->getAnimationTime());
	updateOffhand(player, frametime);

	// Set render distance
	updateViewingRange();

	// If the player is walking, swimming, or climbing,
	// view bobbing is enabled and free_move is off,
	// start (or continue) the view bobbing animation.
	const v3f &speed = player->getSpeed();
	const bool movement_XZ = std::hypot(speed.X, speed.Z) > BS;
	const bool movement_Y = std::abs(speed.Y) > BS;

	const bool walking = movement_XZ && player->touching_ground;
	const bool swimming = (movement_XZ || player->swimming_vertical) && player->in_liquid;
	const bool climbing = movement_Y && player->is_climbing;
	const bool flying = g_settings->getBool("free_move")
		&& m_client->checkLocalPrivilege("fly");
	if ((walking || swimming || climbing) && !flying) {
		// Start animation
		m_view_bobbing_state = 1;
		m_view_bobbing_speed = MYMIN(speed.getLength(), 70);
	} else if (m_view_bobbing_state == 1) {
		// Stop animation
		m_view_bobbing_state = 2;
		m_view_bobbing_speed = 60;
	}
}

void Camera::updateViewingRange()
{
	f32 viewing_range = g_settings->getFloat("viewing_range");

	m_cameranode->setNearValue(0.1f * BS);

	m_draw_control.wanted_range = std::fmin(adjustDist(viewing_range, getFovMax()), 6000);
	if (m_draw_control.range_all) {
		m_cameranode->setFarValue(100000.0);
		return;
	}
	m_cameranode->setFarValue(std::fmax(2000, m_draw_control.wanted_range) * BS);
}

void Camera::setDigging(s32 button)
{
	// If placing, do not desynchronize the animation and placement sound.
	if (button == 1) {
		m_digging_button = button;
		m_digging_anim = 0.0f;
	} else if (m_digging_button == -1) {
		// Any other action.
		m_digging_button = button;
	} else if (m_digging_button == 0 && m_digging_anim >= 0.5f) {
		m_digging_snap = true;
	}
}

void Camera::wield(const ItemStack &item, bool animate, bool arm)
{
	if (item.name != m_wield_item_next.name ||
			item.metadata != m_wield_item_next.metadata || arm != m_wield_arm_next) {
		m_wield_item_next = item;
		m_wield_arm_next = arm;
		m_wield_map_next = !arm &&
				itemgroup_get(item.getDefinition(m_client->idef()).groups, "held_map") > 0;

		if (!animate) {
			updateWieldedTool();
			return;
		}

		if (m_wield_change_timer > 0)
			m_wield_change_timer = -m_wield_change_timer;
		else if (m_wield_change_timer == 0)
			m_wield_change_timer = -0.001;
	}
}

void Camera::drawWieldedTool(core::matrix4* translation)
{
	// Clear Z buffer so that the wielded tool stays in front of world geometry
	m_wieldmgr->getVideoDriver()->clearBuffers(video::ECBF_DEPTH);

	// Draw the wielded node (in a separate scene manager)
	scene::ICameraSceneNode* cam = m_wieldmgr->getActiveCamera();
	cam->setAspectRatio(m_cameranode->getAspectRatio());
	cam->setFOV(wield_fov_y(m_cameranode->getAspectRatio()));
	// the arms holding a map come as near as Minecraft's 0.05 block
	cam->setNearValue(m_wield_map ? 3 : 10);
	cam->setFarValue(1000);
	if (translation != NULL)
	{
		core::matrix4 startMatrix = cam->getAbsoluteTransformation();
		core::vector3df focusPoint = (cam->getTarget()
				- cam->getAbsolutePosition()).setLength(1)
				+ cam->getAbsolutePosition();

		core::vector3df camera_pos =
				(startMatrix * *translation).getTranslation();
		cam->setPosition(camera_pos);
		cam->updateAbsolutePosition();
		cam->setTarget(focusPoint);
	}
	m_wieldmgr->drawAll();
	if (m_wield_map)
		drawHeldMap();
}

bool Camera::handsShown() const
{
	const LocalPlayer *player = m_client->getEnv().getLocalPlayer();
	return m_camera_mode == CAMERA_MODE_FIRST && (player->hud_flags & HUD_FLAG_WIELDITEM_VISIBLE);
}

// The HUD images named "held_map" laid out as the HUD would draw them, together as big as
// Minecraft's map with its border (142 of its 128 pixels); none keeps the last ones
void Camera::updateMapImages(LocalPlayer *player)
{
	std::vector<const HudElement *> elems;
	for (auto const &e : player->hud.getElements()) {
		if (e && e->type == HUD_ELEM_IMAGE && e->name == "held_map")
			elems.push_back(e.get());
	}
	if (elems.empty())
		return;
	std::stable_sort(elems.begin(), elems.end(), [] (const HudElement *l, const HudElement *r) {
		return l->z_index < r->z_index;
	});
	ITextureSource *tsrc = m_client->getTextureSource();
	const v2u32 screen = m_wieldmgr->getVideoDriver()->getScreenSize();
	m_map_images.clear();
	core::rectf box;
	for (const HudElement *e : elems) {
		video::ITexture *texture = tsrc->getTexture(e->text);
		if (!texture)
			continue;
		const core::dimension2du img = texture->getOriginalSize();
		v2f size(img.Width * e->scale.X, img.Height * e->scale.Y);
		if (e->scale.X < 0)
			size.X = screen.X * e->scale.X * -0.01f;
		if (e->scale.Y < 0)
			size.Y = screen.Y * e->scale.Y * -0.01f;
		const v2f at = v2f(e->pos.X * screen.X, e->pos.Y * screen.Y) + e->offset +
				v2f((e->align.X - 1) * size.X / 2, (e->align.Y - 1) * size.Y / 2);
		const core::rectf rect(at.X, at.Y, at.X + size.X, at.Y + size.Y);
		if (m_map_images.empty())
			box = rect;
		box.addInternalPoint(rect.UpperLeftCorner);
		box.addInternalPoint(rect.LowerRightCorner);
		m_map_images.push_back({texture, rect});
	}
	const f32 side = std::max(box.getWidth(), box.getHeight());
	if (side <= 0) {
		m_map_images.clear();
		return;
	}
	const v2f centre = box.getCenter(), middle(64, 64);
	for (MapImage &i : m_map_images) {
		i.rect = core::rectf(middle + (i.rect.UpperLeftCorner - centre) * 142 / side,
				middle + (i.rect.LowerRightCorner - centre) * 142 / side);
	}
}

void Camera::drawHeldMap()
{
	video::IVideoDriver *driver = m_wieldmgr->getVideoDriver();
	video::SMaterial material;
	material.MaterialType = video::EMT_TRANSPARENT_ALPHA_CHANNEL;
	material.ZWriteEnable = video::EZW_OFF;
	material.BackfaceCulling = false;
	material.forEachTexture([] (auto &tex) {
		tex.MinFilter = video::ETMINF_NEAREST_MIPMAP_NEAREST;
		tex.MagFilter = video::ETMAGF_NEAREST;
	});
	// lit as the arms; drawn in order without writing depth, each over the last
	const video::SColor c(255, m_player_light_color.getRed(), m_player_light_color.getGreen(),
			m_player_light_color.getBlue());
	const u16 indices[] = {0, 1, 2, 2, 3, 0};
	driver->setTransform(video::ETS_WORLD, m_map_matrix);
	for (const MapImage &i : m_map_images) {
		const v2f a = i.rect.UpperLeftCorner, b = i.rect.LowerRightCorner;
		video::S3DVertex vertices[] = {
			video::S3DVertex(a.X, a.Y, 0, 0, 0, 1, c, 0, 0),
			video::S3DVertex(b.X, a.Y, 0, 0, 0, 1, c, 1, 0),
			video::S3DVertex(b.X, b.Y, 0, 0, 0, 1, c, 1, 1),
			video::S3DVertex(a.X, b.Y, 0, 0, 0, 1, c, 0, 1),
		};
		material.setTexture(0, i.texture);
		driver->setMaterial(material);
		driver->drawIndexedTriangleList(vertices, 4, indices, 2);
	}
}

void Camera::toggleCameraMode()
{
	if (m_camera_mode == CAMERA_MODE_FIRST)
		m_camera_mode = CAMERA_MODE_THIRD;
	else if (m_camera_mode == CAMERA_MODE_THIRD)
		m_camera_mode = CAMERA_MODE_THIRD_FRONT;
	else
		m_camera_mode = CAMERA_MODE_FIRST;
}

void Camera::drawNametags()
{
	core::matrix4 trans = m_cameranode->getProjectionMatrix();
	trans *= m_cameranode->getViewMatrix();

	// This isn't the actual size, just a placeholder so we can easily apply
	// the user's font size preference...
	const u32 default_font_size = 16;
	// ...by multiplying this in.
	const f32 font_size_mult = g_fontengine->getFontSize(FM_Unspecified) / (float)default_font_size;

	// Minimum distance until z-scaled nametags actually become smaller
	const f32 minimum_d = 3.0f * BS;
	// Smoothing constant: larger = slower size falloff with distance
	const f32 smoothing_k = 4.0f * BS;

	video::IVideoDriver *driver = RenderingEngine::get_video_driver();
	v2u32 screensize = driver->getScreenSize();

	// Note: hidden nametags (e.g. GenericCAO) are removed from the array
	for (const Nametag *nametag : m_nametags) {
		v3f pos = nametag->parent_node->getAbsolutePosition() + nametag->pos * BS;
		f32 transformed_pos[4] = { pos.X, pos.Y, pos.Z, 1.0f };
		trans.multiplyWith1x4Matrix(transformed_pos);
		if (transformed_pos[3] <= 0) // negative Z means behind camera
			continue;
		f32 zDiv = transformed_pos[3] == 0.0f ? 1.0f : (1.0f / transformed_pos[3]);

		u32 font_size = 0;
		if (nametag->scale_z) {
			// Higher default since nametag should be reasonably visible
			// even at distance.
			u32 base_size = nametag->textsize.value_or(default_font_size * 3.2f);
			f32 adjusted_d = std::max(transformed_pos[3] - minimum_d, 0.0f);
			// Normalized for base_size * BS
			f32 scale = (smoothing_k / (adjusted_d + smoothing_k)) / BS;
			font_size = myround(font_size_mult *
				rangelim(base_size * BS * scale, 0, base_size));
		} else {
			font_size = myround(font_size_mult * nametag->textsize.value_or(default_font_size));
		}
		if (font_size <= 1)
			continue;
		// TODO: This is quite primitive. It would be better to let the GPU handle
		// scaling (draw to RTT first?).
		{
			// Because the current approach puts a high load on the font engine
			// we quantize the font size and set an arbitrary maximum...
			font_size = MYMIN(font_size, 256);
			if (font_size > 128)
				font_size &= ~(1|2|4);
			else if (font_size > 64)
				font_size &= ~(1|2);
			else if (font_size > 32)
				font_size &= ~1;
		}
		auto *font = g_fontengine->getFont(font_size);
		assert(font);

		const auto wtext = utf8_to_wide(nametag->text);
		// Measure dimensions with escapes removed
		core::dimension2du textsize = font->getDimension(unescape_translate(wtext).c_str());
		v2s32 screen_pos;
		screen_pos.X = screensize.X *
			(0.5f + transformed_pos[0] * zDiv * 0.5f) - textsize.Width / 2;
		screen_pos.Y = screensize.Y *
			(0.5f - transformed_pos[1] * zDiv * 0.5f) - textsize.Height / 2;
		core::rect<s32> size(0, 0, textsize.Width, textsize.Height);

		auto bgcolor = nametag->getBgColor(m_show_nametag_backgrounds);
		if (bgcolor.getAlpha() != 0) {
			core::rect<s32> bg_size(-2, 0, textsize.Width + 2, textsize.Height);
			driver->draw2DRectangle(bgcolor, bg_size + screen_pos);
		}

		// but draw text with escapes
		font->draw(translate_string(wtext).c_str(),
			size + screen_pos, nametag->textcolor);
	}
}

Nametag *Camera::addNametag(const Nametag &params)
{
	assert(params.parent_node);
	auto *nametag = new Nametag(params);
	m_nametags.push_back(nametag);
	return nametag;
}

void Camera::removeNametag(Nametag *nametag)
{
	auto it = std::find(m_nametags.begin(), m_nametags.end(), nametag);
	assert(it != m_nametags.end());
	m_nametags.erase(it);
	delete nametag;
}

std::array<core::plane3d<f32>, 4> Camera::getFrustumCullPlanes() const
{
	using scene::SViewFrustum;
	const auto &frustum_planes = m_cameranode->getViewFrustum()->planes;
	return {
		frustum_planes[SViewFrustum::VF_LEFT_PLANE],
		frustum_planes[SViewFrustum::VF_RIGHT_PLANE],
		frustum_planes[SViewFrustum::VF_BOTTOM_PLANE],
		frustum_planes[SViewFrustum::VF_TOP_PLANE],
	};
}

void Camera::updateOffhand(LocalPlayer *player, f32 frametime)
{
	const InventoryList *list = player->inventory.getList("offhand");
	const ItemStack item = list && list->getSize() > 0 ? list->getItem(0) : ItemStack();
	if (item.name != m_offhand_name) {
		m_offhand_name = item.name;
		m_offhand_node->setItem(item, m_client);
		m_offhand_equip = 0.0f;
	}
	m_offhand_node->setVisible(!item.empty());
	if (item.empty())
		return;

	// The server sets the meta field "raised"; it goes up and down in 0.2 s
	const f32 target = item.metadata.getString("raised") == "1" ? 1.0f : 0.0f;
	const f32 step = frametime / 0.2f;
	m_offhand_raise = target > m_offhand_raise ? std::min(target, m_offhand_raise + step)
			: std::max(target, m_offhand_raise - step);
	m_offhand_equip = std::min(1.0f, m_offhand_equip + frametime / 0.25f);

	const f32 t = easeCurve(m_offhand_raise);
	v3f pos = m_offhand_position[0] + (m_offhand_position[1] - m_offhand_position[0]) * t;
	core::quaternion q;
	q.slerp(core::quaternion(m_offhand_rotation[0] * core::DEGTORAD),
			core::quaternion(m_offhand_rotation[1] * core::DEGTORAD), t);
	v3f rot;
	q.toEuler(rot);
	rot *= core::RADTODEG;

	// rises into view when it changes, and sways and bobs as the right hand, mirrored
	pos.Y -= (1.0f - easeCurve(m_offhand_equip)) * 40.0f;
	pos.X -= m_wieldmesh_offset.X - WIELDMESH_OFFSET_X;
	pos.Y += m_wieldmesh_offset.Y - WIELDMESH_OFFSET_Y;
	if (m_digging_button == -1) {
		f32 bobfrac = my_modf(m_view_bobbing_anim);
		pos.X += std::sin(bobfrac * M_PI * 2.0) * 3.0;
		pos.Y += std::sin(my_modf(bobfrac * 2.0) * M_PI) * 3.0;
	}
	// its poses were set under a fixed 72 degree FOV: as near as keeps it the same on screen
	pos.Z *= std::tan(36.0f * core::DEGTORAD) / std::tan(wield_fov_y(m_aspect) / 2);
	m_offhand_node->setPosition(pos);
	m_offhand_node->setRotation(rot);
	m_offhand_node->setLightColorAndAnimation(m_player_light_color, m_client->getAnimationTime());
}

void Camera::updateWieldedTool()
{
	// An empty hand is Minecraft's arm with the player's skin, and a map is held by the arms
	m_wield_map = m_wield_map_next;
	// the same map again shows what it showed until the server's images come
	if (m_wield_map && (m_wield_item_next.name != m_map_item.name ||
			m_wield_item_next.metadata != m_map_item.metadata)) {
		m_map_images.clear();
		m_map_item = m_wield_item_next;
	}
	if (m_wield_arm_next || m_wield_map) {
		m_arm_skin = arm_skin(m_client);
		video::ITexture *skin = m_client->getTextureSource()->getTexture(m_arm_skin);
		m_wieldnode->setArm(skin, m_client->getShaderSource());
		if (m_wield_map)
			m_left_arm->setArm(skin, m_client->getShaderSource(), true);
	} else {
		m_wieldnode->setItem(m_wield_item_next, m_client);
	}
	m_wieldnode->setLightColorAndAnimation(m_player_light_color, m_client->getAnimationTime());
}
