@tool
extends Node3D

signal aim_updated

@export var actor: BreachActor
@export var combat_library: AnimationLibrary
@export var crouch_library: AnimationLibrary
@export_range(1.0, 30.0, 0.5) var turn_speed: float = 14.0
## Distance covered by one full left/right gait cycle; tune against foot contact.
@export_range(0.2, 8.0, 0.05) var walk_cycle_distance: float = 2.18
@export_range(0.2, 10.0, 0.05) var run_cycle_distance: float = 1.76
@export_range(0.2, 3.0, 0.05) var crouch_cycle_distance: float = 0.77864027
@export_range(0.25, 3.0, 0.05) var animation_speed: float = 1.0
## Downward speed at which the airborne pose has fully prepared its feet to land.
@export_range(0.5, 12.0, 0.5) var descent_pose_speed: float = 4.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animator: AnimationPlayer = $Model/AnimationPlayer
@onready var playback: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/Locomotion/playback")
@onready var hand: BoneAttachment3D = $Model/Survivor/CharacterArmature/Skeleton3D/Hand
@onready var aim_modifier: SkeletonModifier3D = $Model/Survivor/CharacterArmature/Skeleton3D/Aim
@onready var foot_placement: SkeletonModifier3D = $Model/Survivor/CharacterArmature/Skeleton3D/FootPlacement
@onready var slope_posture: SkeletonModifier3D = $Model/Survivor/CharacterArmature/Skeleton3D/SlopePosture

var _walk_duration: float
var _run_duration: float
var _weapon: WeaponSpec = preload("res://resources/weapons/rifle.tres")
var _slot: int = 0
var _views: Array[BreachWeaponView] = []
var _action_remaining: float = 0.0
var _dead: bool = false
var _body_scale: float = 1.0


func _ready() -> void:
	_body_scale = scale.x
	foot_placement.actor = actor
	slope_posture.actor = actor
	for weapon: Node3D in hand.get_children():
		if weapon is BreachWeaponView:
			weapon.scale /= _body_scale
			_views.append(weapon)
	aim_modifier.get_skeleton().skeleton_updated.connect(aim_updated.emit)
	if combat_library != null and not animator.has_animation_library("combat"):
		animator.add_animation_library("combat", combat_library)
	if crouch_library != null and not animator.has_animation_library("crouch"):
		animator.add_animation_library("crouch", crouch_library)
	_walk_duration = animator.get_animation("Walk").length
	_run_duration = animator.get_animation("Run").length
	playback.start("Grounded")
	set_weapon(_weapon)
	if actor != null and not Engine.is_editor_hint():
		actor.jumped.connect(_on_jumped)
		actor.landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _dead:
		return
	_action_remaining = maxf(0.0, _action_remaining - delta)
	aim_modifier.free_arm = _action_remaining > 0.0
	if actor == null:
		return
	var target_yaw: float = actor.facing * PI / 2.0
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	var speed: float = actor.get_real_velocity().length() if actor.has_ground_support() else absf(actor.velocity.x)
	var walking: float = clampf(speed / actor.walk_speed, 0.0, 1.0)
	var running: float = clampf((speed - actor.walk_speed) / maxf(actor.sprint_speed - actor.walk_speed, 0.1), 0.0, 1.0)
	animation_tree.set("parameters/Locomotion/Grounded/Motion/blend_position", walking + running)
	animation_tree.set("parameters/ShotMotion/blend_position", walking + running)
	var walk_rate: float = speed * _walk_duration / (walk_cycle_distance * _body_scale)
	var run_rate: float = speed * _run_duration / (run_cycle_distance * _body_scale)
	var gait_rate: float = lerpf(walk_rate, run_rate, running)
	if actor.velocity.x * actor.facing < 0.0:
		gait_rate = -gait_rate
	animation_tree.set("parameters/Locomotion/Grounded/Pace/scale", lerpf(1.0, gait_rate, walking) * animation_speed)
	var crouch_motion: float = speed if actor.has_ground_support() else 0.0
	animation_tree.set("parameters/Locomotion/Crouch/Motion/blend_position", clampf(crouch_motion / actor.crouch_speed, 0.0, 1.0))
	var crouch_rate: float = crouch_motion / (crouch_cycle_distance * _body_scale)
	animation_tree.set("parameters/Locomotion/Crouch/Pace/scale", crouch_rate * signf(actor.velocity.x * actor.facing) * animation_speed)
	var descent_pose: float = 1.0 if actor.has_ground_support() or actor.jump_count == 0 else clampf(-actor.velocity.y / descent_pose_speed, 0.0, 1.0)
	animation_tree.set("parameters/Locomotion/Air/blend_position", descent_pose)
	# Only a fall without a jump needs this fallback; do not replace a queued Jump.
	if not actor.crouching and not actor.has_ground_support() and actor.jump_count == 0 and actor.velocity.y <= 0.0 \
			and playback.get_current_node() in [&"Grounded", &"Land"]:
		playback.travel("Air")


func set_crouching(enabled: bool) -> void:
	if not _dead:
		playback.travel("Crouch" if enabled else ("Grounded" if actor.has_ground_support() else "Air"))


func is_crouch_ready() -> bool:
	return playback.get_current_node() == &"Crouch" and playback.get_fading_from_node() == &""


func _on_jumped(_is_air_jump: bool) -> void:
	if not _dead and not actor.crouching:
		playback.travel("Jump")


func _on_landed(_impact_speed: float) -> void:
	if not _dead and not actor.crouching:
		playback.travel("Land")


func mount_weapon(index: int, spec: WeaponSpec) -> bool:
	if index < 0 or index >= _views.size() or spec == null or not spec.is_valid():
		return false
	if _views[index].scene_file_path == spec.view_scene.resource_path:
		_views[index].apply_flash_profile(spec.muzzle_flash_profile)
		return true
	var instance: Node = spec.view_scene.instantiate()
	if not instance is BreachWeaponView or not instance.is_valid():
		instance.free()
		return false
	var view := instance as BreachWeaponView
	var old: BreachWeaponView = _views[index]
	view.name = old.name
	hand.remove_child(old)
	hand.add_child(view)
	view.apply_flash_profile(spec.muzzle_flash_profile)
	hand.move_child(view, index)
	view.scale /= _body_scale
	_views[index] = view
	old.queue_free()
	return true


func set_weapon(spec: WeaponSpec, slot: int = 0) -> void:
	if _dead or spec == null:
		return
	_weapon = spec
	_slot = slot
	if not is_node_ready():
		return
	_update_equipment()


func _update_equipment() -> void:
	_abort_actions()
	for index: int in _views.size():
		_views[index].visible = index == _slot
	aim_modifier.tool_mode = false
	aim_modifier.muzzle = _views[_slot].muzzle
	if aim_modifier.support_ik != null:
		var grip: Marker3D = _views[_slot].support_grip
		aim_modifier.support_ik.set_target_node(0, aim_modifier.support_ik.get_path_to(grip))


func set_aim(direction: Vector3) -> void:
	if _dead or not direction.is_finite() or direction.length_squared() < 0.001:
		return
	if is_node_ready():
		aim_modifier.direction = direction.normalized()


func set_aim_target(point: Vector3) -> void:
	if is_node_ready() and point.is_finite():
		aim_modifier.target_point = point


func prepare_shot() -> void:
	if actor != null:
		rotation.y = actor.facing * PI / 2.0
	aim_modifier.free_arm = false
	aim_modifier.set("_arm_weight", 1.0)
	aim_modifier.get_skeleton().advance(0.0)


func play_shot() -> void:
	if _dead:
		return
	animation_tree.set("parameters/Shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_views[_slot].play_fire()


func play_reload(duration: float) -> void:
	if _dead or not is_finite(duration) or duration <= 0.0:
		return
	_action_remaining = duration
	animation_tree.set("parameters/ReloadRate/scale", 1.0 / duration)
	animation_tree.set("parameters/Reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func get_muzzle_position() -> Vector3:
	if not is_node_ready():
		return global_position + Vector3.UP
	return aim_modifier.muzzle.global_position


func get_muzzle_direction() -> Vector3:
	return aim_modifier.muzzle.global_basis.x.normalized()


func play_hit() -> void:
	if not _dead:
		animation_tree.set("parameters/Hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_death() -> void:
	if _dead:
		return
	_dead = true
	foot_placement.enabled = false
	slope_posture.active = false
	_abort_actions()
	aim_modifier.active = false
	aim_modifier.support_ik.active = false
	animation_tree.set("parameters/DeathSeek/seek_request", 0.0)
	animation_tree.set("parameters/DeathBlend/blend_amount", 1.0)


func reset_visual() -> void:
	_dead = false
	foot_placement.enabled = true
	slope_posture.active = true
	_abort_actions()
	aim_modifier.active = true
	aim_modifier.support_ik.active = true
	animation_tree.set("parameters/DeathBlend/blend_amount", 0.0)
	playback.start("Grounded")
	set_weapon(_weapon, _slot)


func _abort_actions() -> void:
	_action_remaining = 0.0
	for action in [&"Shot", &"Reload", &"Hit"]:
		animation_tree.set("parameters/" + action + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	for view: BreachWeaponView in _views:
		view.reset_feedback()
