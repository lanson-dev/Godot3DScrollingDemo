@tool
class_name BreachWeaponView
extends Node3D
const FLASH_ANIMATION: AnimationLibrary = preload("res://resources/weapons/muzzle/animation.tres")

@export var muzzle: Marker3D
@export var support_grip: Marker3D
@export var feedback: AnimationPlayer
@export var muzzle_flash_profile: MuzzleFlashProfile:
	set(value):
		if muzzle_flash_profile != null and muzzle_flash_profile.changed.is_connected(_refresh_flash):
			muzzle_flash_profile.changed.disconnect(_refresh_flash)
		muzzle_flash_profile = value
		if value != null:
			value.changed.connect(_refresh_flash)
		if is_node_ready():
			_refresh_flash()


func _ready() -> void:
	_refresh_flash()


func apply_flash_profile(profile: MuzzleFlashProfile) -> void:
	muzzle_flash_profile = profile


func _refresh_flash() -> void:
	if not is_node_ready() or muzzle_flash_profile == null or not muzzle_flash_profile.is_valid():
		return
	var flash := muzzle.get_node_or_null("Flash") as Node3D
	if flash == null or not feedback.has_animation("fire"):
		return
	# Retarget the saved normalized tracks into a private library, never the shared template.
	var library := FLASH_ANIMATION.duplicate(true) as AnimationLibrary
	for animation_name: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(animation_name)
		if animation_name == &"fire":
			animation.length *= muzzle_flash_profile.duration
		for track: int in animation.get_track_count():
			var property: StringName = animation.track_get_path(track).get_subname(0)
			for key: int in animation.track_get_key_count(track):
				var value: Variant = animation.track_get_key_value(track, key)
				if property == &"light_energy":
					value = float(value) * muzzle_flash_profile.light_energy
				elif property == &"scale":
					value = (value as Vector3) * muzzle_flash_profile.flame_scale
				animation.track_set_key_value(track, key, value)
				if animation_name == &"fire":
					animation.track_set_key_time(track, key, animation.track_get_key_time(track, key) * muzzle_flash_profile.duration)
	feedback.stop()
	feedback.remove_animation_library(&"")
	feedback.add_animation_library(&"", library)
	(flash.get_node("Light") as OmniLight3D).omni_range = muzzle_flash_profile.light_range
	reset_feedback()


func is_valid() -> bool:
	return muzzle != null and support_grip != null and feedback != null


func play_fire() -> void:
	feedback.play("fire")
	feedback.advance(0.0)


func play_swing(duration: float) -> void:
	feedback.play("swing", -1.0, 0.35 / duration)


func reset_feedback() -> void:
	feedback.play("RESET")
	feedback.advance(0.0)
