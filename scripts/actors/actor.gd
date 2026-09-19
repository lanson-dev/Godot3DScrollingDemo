class_name BreachActor
extends CharacterBody3D

signal jumped(is_air_jump: bool)
signal landed(impact_speed: float)
signal fell

@export var human_control: bool = true
@export var walk_speed: float = 5.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 1.6
@export var acceleration: float = 36.0
@export var deceleration: float = 44.0
@export var gravity: float = 24.0
@export var jump_velocity: float = 10.8
@export var air_jump_velocity: float = 10.2
@export_range(0.1, 0.5, 0.01) var air_jump_min_interval: float = 0.1
@export var kill_height: float = -15.0
@export var face_movement: bool = true

var move_axis: float = 0.0
var sprinting: bool = false
var crouch_requested: bool = false
var crouching: bool = false
var jump_count: int = 0
var controls_enabled: bool = true
var facing: float = 1.0
var spawn_position: Vector3
var _corpse: bool = false
var _alive_collision_mask: int
var _ground_speed: float = 0.0
var _jump_requested: bool = false
var _air_jump_delay: float = 0.0
var _head_slide_direction: float = 0.0


func _ready() -> void:
	spawn_position = global_position
	_alive_collision_mask = collision_mask


func _physics_process(delta: float) -> void:
	var actor_support: BreachActor = _actor_support()
	if actor_support == null:
		_head_slide_direction = 0.0
	_air_jump_delay = maxf(0.0, _air_jump_delay - delta)
	var was_grounded: bool = is_on_floor() and actor_support == null
	if was_grounded and velocity.y <= 0.0:
		jump_count = 0
		_air_jump_delay = 0.0
	if human_control:
		move_axis = Input.get_axis("move_left", "move_right") if controls_enabled else 0.0
		sprinting = Input.is_action_pressed("sprint") and controls_enabled
		if controls_enabled and _jump_requested:
			request_jump()
	_jump_requested = false
	var speed: float = _movement_speed()
	var rate: float = acceleration if absf(move_axis) > 0.01 else deceleration
	var target_speed: float = clampf(move_axis, -1.0, 1.0) * speed
	var ground_motion: bool = floor_constant_speed and was_grounded and jump_count == 0 and not _corpse
	var tangent := Vector3.RIGHT
	if ground_motion:
		var normal: Vector3 = get_floor_normal()
		tangent = Vector3(normal.y, -normal.x, 0.0).normalized()
		# Honor explicit stops as well as native collisions that removed all velocity.
		if velocity.is_zero_approx():
			_ground_speed = 0.0
		_ground_speed = move_toward(_ground_speed, target_speed, rate * delta)
		velocity = tangent * _ground_speed
	else:
		velocity.x = 0.0 if _corpse else move_toward(velocity.x, target_speed, rate * delta)
	if actor_support != null and not _corpse:
		# Live capsules are obstacles, not stairs: slide off the rounded head with native collision.
		if _head_slide_direction == 0.0:
			_head_slide_direction = signf(global_position.x - actor_support.global_position.x)
			if _head_slide_direction == 0.0:
				_head_slide_direction = facing
		if is_on_wall() and get_wall_normal().x * _head_slide_direction < -0.5:
			_head_slide_direction *= -1.0
		velocity.x = _head_slide_direction * walk_speed
	if face_movement and absf(move_axis) > 0.01:
		facing = signf(move_axis)
	if not was_grounded:
		velocity.y -= gravity * delta
	velocity.z = 0.0
	var fall_speed: float = velocity.y
	var constant_speed: bool = floor_constant_speed
	# Native constant-speed descent projects horizontal input again; this request is already tangent.
	if ground_motion and constant_speed:
		floor_constant_speed = false
	move_and_slide()
	# Up-slope tangent motion points upward, so automatic snap may skip it.
	# Only a grounded walk can request this; jumps and head contacts cannot.
	if ground_motion:
		apply_floor_snap()
	floor_constant_speed = constant_speed
	if ground_motion:
		if is_on_wall() or is_on_ceiling():
			# A blocked actor must accelerate again after the obstruction disappears.
			_ground_speed = clampf(velocity.x / tangent.x, minf(_ground_speed, 0.0), maxf(_ground_speed, 0.0))
		elif not has_ground_support():
			# Walking off an edge retains horizontal control, without a slope-generated jump.
			velocity = Vector3(_ground_speed, 0.0, 0.0)
	else:
		_ground_speed = velocity.x
	if not was_grounded and has_ground_support():
		jump_count = 0
		_air_jump_delay = 0.0
		landed.emit(absf(fall_speed))
	if global_position.y < kill_height and controls_enabled:
		controls_enabled = false
		fell.emit()


func _movement_speed() -> float:
	return crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)


func has_ground_support() -> bool:
	return is_on_floor() and _actor_support() == null


func _actor_support() -> BreachActor:
	if not is_on_floor():
		return null
	var support: BreachActor
	for index: int in get_slide_collision_count():
		var hit: KinematicCollision3D = get_slide_collision(index)
		for contact: int in hit.get_collision_count():
			var body: Object = hit.get_collider(contact)
			var upward: float = hit.get_normal(contact).dot(up_direction)
			if body is BreachActor and upward > 0.0:
				# Native physics can also combine steep actor/wall contacts into a floor.
				support = body as BreachActor
			elif not body is BreachActor and upward >= cos(floor_max_angle + 0.01):
				return null # A real floor still supports the actor at a mixed contact.
	if support != null:
		return support
	# Native floor snapping does not add a slide collision. Ask the same physics
	# backend for the support using a read-only capsule sweep, without moving it.
	var snap := KinematicCollision3D.new()
	if test_move(global_transform, -up_direction * maxf(floor_snap_length, safe_margin), snap, safe_margin, true, max_slides):
		for contact: int in snap.get_collision_count():
			var body: Object = snap.get_collider(contact)
			var upward: float = snap.get_normal(contact).dot(up_direction)
			if body is BreachActor and upward > 0.0:
				support = body as BreachActor
			elif not body is BreachActor and upward >= cos(floor_max_angle + 0.01):
				return null
	return support


func _unhandled_key_input(event: InputEvent) -> void:
	# A fresh Space/W/Up event still matters while another key bound to jump is held.
	# One pending request coalesces simultaneous keys into one physics-frame impulse.
	if human_control and controls_enabled and event.is_action_pressed("jump") and not event.is_echo():
		_jump_requested = true
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_jump_requested = false


func request_jump() -> void:
	if not controls_enabled or jump_count >= 2 or (jump_count > 0 and _air_jump_delay > 0.000001):
		return
	var is_air_jump: bool = jump_count > 0
	if has_ground_support() and not is_air_jump:
		velocity.x = _ground_speed
	velocity.y = air_jump_velocity if is_air_jump else jump_velocity
	jump_count += 1
	_air_jump_delay = air_jump_min_interval
	jumped.emit(is_air_jump)


func reset_at(at: Vector3) -> void:
	_corpse = false
	collision_mask = _alive_collision_mask
	global_position = at
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	move_axis = 0.0
	sprinting = false
	crouch_requested = false
	jump_count = 0
	_jump_requested = false
	_air_jump_delay = 0.0
	_head_slide_direction = 0.0


func settle_as_corpse() -> void:
	_corpse = true
	controls_enabled = false
	move_axis = 0.0
	sprinting = false
	velocity.x = 0.0
	velocity.z = 0.0
	_ground_speed = 0.0
	_jump_requested = false
	_air_jump_delay = 0.0
	_head_slide_direction = 0.0
	# Still collide with native terrain, but live actors cannot recovery-push a corpse.
	collision_mask &= ~6
