class_name WeaponSpec
extends Resource

@export var weapon_id: StringName
@export var display_name: String
@export var view_scene: PackedScene
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var muzzle_flash_profile: MuzzleFlashProfile = preload("res://resources/weapons/muzzle/rifle.tres")
@export_group("Crosshair")
## Logical UI pixels; rendering may clamp the display without changing ballistic spread.
@export_range(0.1, 100.0, 0.5) var crosshair_min_radius: float = 3.0
@export_range(0.1, 200.0, 0.5) var crosshair_max_radius: float = 48.0
@export_group("Aim Camera")
@export var aim_camera_enabled: bool = false
@export var aim_camera_offset: Vector2 = Vector2(2.4, 1.2)
@export_range(0.05, 2.0, 0.05) var aim_camera_response: float = 0.25
@export_group("Spread and Aim Movement")
## Full cone angle; spread and bloom are sampled before each committed shot.
@export_range(0.0, 90.0, 0.1) var spread_degrees: float = 2.0
@export_range(0.0, 90.0, 0.1) var move_spread_degrees: float = 4.0
@export_range(0.0, 90.0, 0.1) var air_spread_degrees: float = 10.0
@export_range(0.0, 1.0, 0.05) var crouch_spread_multiplier: float = 0.75
@export_range(0.0, 1.0, 0.05) var ads_spread_multiplier: float = 0.55
@export_range(0.0, 30.0, 0.1) var bloom_per_shot_degrees: float = 0.8
@export_range(0.0, 90.0, 0.1) var bloom_limit_degrees: float = 6.0
@export_range(0.0, 2.0, 0.05) var bloom_delay: float = 0.18
## Full-cone degrees recovered per second, after the delay; paused time is excluded.
@export_range(0.1, 90.0, 0.1) var bloom_recovery_degrees: float = 5.0
## Fraction of walking/crouching speed while aiming; sprint cannot bypass it.
@export_range(0.1, 1.0, 0.05) var ads_move_multiplier: float = 0.55
@export_group("Ballistics")
@export_range(0.0, 1000.0, 1.0) var damage: float = 27.0
@export_range(0.01, 5.0, 0.01) var interval: float = 0.14
@export_range(0, 200, 1) var magazine_size: int = 24
@export_range(0, 1000, 1) var reserve_start: int = 144
@export_range(0.0, 10.0, 0.05) var reload_seconds: float = 1.35
@export_range(0, 32, 1) var pellets: int = 1
@export_range(0.0, 2000.0, 1.0) var projectile_speed: float = 40.0
@export_range(0.1, 200.0, 0.1) var reach: float = 56.0


func is_valid() -> bool:
	for value: float in [spread_degrees, move_spread_degrees, air_spread_degrees, bloom_per_shot_degrees, bloom_limit_degrees, bloom_delay]:
		if not is_finite(value) or value < 0.0:
			return false
	return not weapon_id.is_empty() and view_scene != null and is_finite(damage) and damage >= 0.0 \
		and muzzle_flash_profile != null and muzzle_flash_profile.is_valid() \
		and is_finite(crosshair_min_radius) and crosshair_min_radius > 0.0 \
		and is_finite(crosshair_max_radius) and crosshair_max_radius >= crosshair_min_radius \
		and is_finite(interval) and interval > 0.0 and magazine_size >= 0 and reserve_start >= 0 \
		and is_finite(reload_seconds) and reload_seconds > 0.0 and pellets > 0 \
		and is_finite(projectile_speed) and projectile_speed > 0.0 and is_finite(reach) and reach > 0.0 \
		and spread_degrees <= 90.0 and is_finite(bloom_recovery_degrees) and bloom_recovery_degrees > 0.0 \
		and aim_camera_offset.is_finite() and aim_camera_offset.x >= 0.0 and aim_camera_offset.y >= 0.0 \
		and is_finite(aim_camera_response) and aim_camera_response > 0.0 \
		and is_finite(crouch_spread_multiplier) and crouch_spread_multiplier >= 0.0 and crouch_spread_multiplier <= 1.0 \
		and is_finite(ads_spread_multiplier) and ads_spread_multiplier >= 0.0 and ads_spread_multiplier <= 1.0 \
		and is_finite(ads_move_multiplier) and ads_move_multiplier > 0.0 and ads_move_multiplier <= 1.0
