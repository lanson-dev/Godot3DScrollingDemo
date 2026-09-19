class_name BreachWeapons
extends Node3D

signal changed
signal fired(weapon_id: StringName)
signal hit_confirmed(position: Vector3)

@export var actor: BreachActor
@export var visual: Node3D
@export var rifle: WeaponSpec
@export var shotgun: WeaponSpec
@export var projectile_scene: PackedScene
@export var muzzle_flash_scene: PackedScene
@export var hit_scene: PackedScene
@export var chest_height: float = 1.2
@export_flags_3d_physics var projectile_mask: int = 13

@onready var gun_audio: AudioStreamPlayer3D = $GunAudio
@onready var action_audio: AudioStreamPlayer3D = $ActionAudio

var selected: int = 0
var magazines: PackedInt32Array
var reserves: PackedInt32Array
var cooldown: float = 0.0
var reload_remaining: float = 0.0
var aim_direction: Vector3 = Vector3.RIGHT
var aim_target: Vector3
var aiming: bool = false
var virtual_pointer_enabled: bool = false
var virtual_pointer_position: Vector2
var _specs: Array[WeaponSpec]
var _needs_release: bool = false
var _aim_needs_release: bool = false
var _pending_shot: WeaponSpec
var _bloom := PackedFloat32Array([0.0, 0.0])
var _bloom_wait := PackedFloat32Array([0.0, 0.0])
var _spread_random := RandomNumberGenerator.new()


func _ready() -> void:
	_spread_random.randomize()
	_specs = [rifle, shotgun]
	for index: int in _specs.size():
		var spec: WeaponSpec = _specs[index]
		var mounted: bool = visual.call("mount_weapon", index, spec)
		assert(mounted, "Weapon slot needs a valid saved weapon view and spec")
		magazines.append(spec.magazine_size)
		reserves.append(spec.reserve_start)
	aim_target = actor.global_position + Vector3(10.0, chest_height, 0.0)
	visual.call("set_weapon", current_spec(), selected)
	actor.face_movement = false
	visual.connect("aim_updated", _finish_shot)


func current_spec() -> WeaponSpec:
	return _specs[selected]


func slot_spec(index: int) -> WeaponSpec:
	return _specs[index] if index >= 0 and index < _specs.size() else null


func _physics_process(delta: float) -> void:
	for index: int in _specs.size():
		var recovery_delta: float = maxf(0.0, delta - _bloom_wait[index])
		_bloom_wait[index] = maxf(0.0, _bloom_wait[index] - delta)
		_bloom[index] = move_toward(_bloom[index], 0.0, _specs[index].bloom_recovery_degrees * recovery_delta)
	cooldown = maxf(0.0, cooldown - delta)
	if actor.human_control:
		_update_pointer_aim()
		if not Input.is_action_pressed("aim"):
			_aim_needs_release = false
		aiming = actor.controls_enabled and actor.has_ground_support() \
			and not _aim_needs_release and Input.is_action_pressed("aim")
		if not Input.is_action_pressed("fire"):
			_needs_release = false
	visual.call("set_aim", aim_direction)
	visual.call("set_aim_target", aim_target)
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining == 0.0:
			_finish_reload()
	if actor.human_control and not _needs_release and Input.is_action_pressed("fire"):
		try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if not actor.human_control or not actor.controls_enabled:
		return
	for index in 2:
		if event.is_action_pressed(["rifle", "shotgun"][index]):
			select_weapon(index)
	if event.is_action_pressed("reload"):
		reload_weapon()


func set_aim_target(target: Vector3) -> void:
	if not target.is_finite():
		return
	aim_target = target
	var offset: Vector3 = target - _chest_position()
	offset.z = 0.0
	if not offset.is_zero_approx():
		aim_direction = offset.normalized()
	if absf(aim_direction.x) > 0.01:
		actor.facing = signf(aim_direction.x)
	if is_node_ready():
		visual.call("set_aim", aim_direction)
		visual.call("set_aim_target", aim_target)
		if _pending_shot != null:
			visual.call("prepare_shot")


func pointer_screen_position() -> Vector2:
	return virtual_pointer_position if virtual_pointer_enabled else get_viewport().get_mouse_position()


func _update_pointer_aim() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var pointer: Vector2 = pointer_screen_position()
	var plane := Plane(Vector3.BACK, actor.global_position.z)
	var point: Variant = plane.intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
	if point is Vector3:
		set_aim_target(point)


func select_weapon(index: int) -> void:
	if index < 0 or index >= _specs.size():
		return
	cancel_input()
	reload_remaining = 0.0
	action_audio.stop()
	selected = index
	visual.call("set_weapon", current_spec(), selected)
	visual.call("set_aim", aim_direction)
	visual.call("set_aim_target", aim_target)
	changed.emit()


func equip_weapon(index: int, spec: WeaponSpec) -> bool:
	if index < 0 or index >= _specs.size() or spec == null or not spec.is_valid():
		return false
	if not visual.call("mount_weapon", index, spec):
		return false
	cancel_input()
	_specs[index] = spec
	_bloom[index] = 0.0
	_bloom_wait[index] = 0.0
	magazines[index] = spec.magazine_size
	reserves[index] = spec.reserve_start
	select_weapon(index)
	return true


func cancel_input() -> void:
	if _pending_shot != null:
		magazines[selected] += 1
		_pending_shot = null
		cooldown = 0.0
		changed.emit()
	_needs_release = true
	_aim_needs_release = true
	aiming = false


func try_fire() -> bool:
	if not actor.controls_enabled or cooldown > 0.0 or reload_remaining > 0.0 or _pending_shot != null:
		return false
	var spec: WeaponSpec = current_spec()
	if magazines[selected] <= 0:
		reload_weapon()
		return false
	visual.call("set_aim", aim_direction)
	visual.call("set_aim_target", aim_target)
	magazines[selected] -= 1
	cooldown = spec.interval
	_pending_shot = spec
	visual.call("prepare_shot")
	return true


func reload_weapon() -> bool:
	var spec: WeaponSpec = current_spec()
	if not actor.controls_enabled or reload_remaining > 0.0:
		return false
	if magazines[selected] >= spec.magazine_size or reserves[selected] <= 0:
		return false
	reload_remaining = spec.reload_seconds
	visual.call("play_reload", spec.reload_seconds)
	_play_action_sound(spec.reload_sound)
	changed.emit()
	return true


func _finish_reload() -> void:
	var amount: int = mini(current_spec().magazine_size - magazines[selected], reserves[selected])
	magazines[selected] += amount
	reserves[selected] -= amount
	changed.emit()


func _chest_position() -> Vector3:
	return actor.global_position + Vector3.UP * chest_height


func spread_half_angle_degrees() -> float:
	var spec: WeaponSpec = current_spec()
	var velocity: Vector3 = actor.get_real_velocity()
	var speed: float = Vector2(velocity.x, velocity.y).length() if actor.has_ground_support() else absf(velocity.x)
	speed = clampf(speed / maxf(actor.walk_speed, 0.1), 0.0, 1.0)
	var angle: float = spec.spread_degrees + spec.move_spread_degrees * speed + _bloom[selected]
	if not actor.has_ground_support():
		angle += spec.air_spread_degrees
	angle *= spec.crouch_spread_multiplier if actor.crouching else 1.0
	angle *= spec.ads_spread_multiplier if aiming else 1.0
	return clampf(angle * 0.5, 0.0, 45.0)


func spread_origin() -> Vector3:
	return visual.call("get_muzzle_position")


func spread_direction() -> Vector3:
	return visual.call("get_muzzle_direction")


func _shoot(spec: WeaponSpec) -> void:
	var muzzle: Vector3 = spread_origin()
	var direction: Vector3 = spread_direction()
	var half_angle: float = spread_half_angle_degrees()
	var excluded: Array[RID] = [actor.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(_chest_position(), muzzle, projectile_mask, excluded)
	query.hit_from_inside = true
	var obstruction: Dictionary = BreachCombatTrace.ray_hit(get_world_3d().direct_space_state, query)
	spec.muzzle_flash_profile.apply_sparks(_spawn_effect(muzzle_flash_scene, muzzle, direction))
	if not obstruction.is_empty():
		var collider: Object = obstruction["collider"]
		if collider.has_method("apply_damage"):
			collider.call("apply_damage", spec.damage * spec.pellets, obstruction["position"], direction)
			hit_confirmed.emit(obstruction["position"])
		else:
			_spawn_effect(hit_scene, obstruction["position"])
		return
	for pellet in spec.pellets:
		var spread: float = lerpf(-half_angle, half_angle, (float(pellet) + _spread_random.randf()) / spec.pellets)
		var bullet := projectile_scene.instantiate() as BreachProjectile
		bullet.hit_confirmed.connect(hit_confirmed.emit)
		get_tree().current_scene.add_child(bullet)
		bullet.launch(muzzle, direction.rotated(Vector3.BACK, deg_to_rad(spread)), spec.damage,
			spec.projectile_speed, spec.reach, projectile_mask, excluded)


func _finish_shot() -> void:
	if _pending_shot == null:
		return
	if get_tree().paused or not actor.controls_enabled or reload_remaining > 0.0:
		cancel_input()
		return
	var spec: WeaponSpec = _pending_shot
	_pending_shot = null
	cooldown = spec.interval
	_shoot(spec)
	_bloom[selected] = minf(spec.bloom_limit_degrees, _bloom[selected] + spec.bloom_per_shot_degrees)
	_bloom_wait[selected] = spec.bloom_delay
	visual.call("play_shot")
	var stream: AudioStream = spec.fire_sound
	if stream != null:
		if gun_audio.stream != stream:
			gun_audio.stream = stream
		gun_audio.pitch_scale = randf_range(0.96, 1.04)
		gun_audio.play()
	fired.emit(spec.weapon_id)
	changed.emit()


func _spawn_effect(scene: PackedScene, at: Vector3, direction: Vector3 = Vector3.ZERO) -> Node3D:
	if scene == null:
		return null
	var effect := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(effect)
	effect.global_position = at
	var axis: Vector3 = aim_direction if direction.is_zero_approx() else direction
	effect.global_basis = Basis(Quaternion(Vector3.RIGHT, axis.normalized()))
	return effect


func _play_action_sound(stream: AudioStream) -> void:
	if stream != null:
		action_audio.stream = stream
		action_audio.play()
