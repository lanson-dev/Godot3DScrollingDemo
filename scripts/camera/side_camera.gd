extends Camera3D

@export var target: Node3D
@export var follow_speed: float = 6.0
@export var look_ahead: float = 1.4
## Time constant in seconds: longer values ease starts, stops and direction changes.
@export_range(0.05, 2.0, 0.05) var look_ahead_response: float = 0.4
@export_range(0.0, 1.0, 0.05) var vertical_follow_weight: float = 0.65

var _offset: Vector3
var _initial_target_y: float
var _look_ahead_offset: float = 0.0
var _aim_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_physics_priority = 2
	if target != null:
		_offset = global_position - target.global_position
		_initial_target_y = target.global_position.y


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var destination: Vector3 = target.global_position + _offset
	destination.y = _initial_target_y + _offset.y + (target.global_position.y - _initial_target_y) * vertical_follow_weight
	var desired_ahead: float = 0.0
	if target is BreachPlayer:
		var player := target as BreachPlayer
		# Follow actual travel, not a key reversal while the body is still braking.
		desired_ahead = clampf(player.velocity.x / maxf(player.walk_speed, 0.01), -1.0, 1.0) * look_ahead
	_look_ahead_offset = lerpf(_look_ahead_offset, desired_ahead, 1.0 - exp(-delta / look_ahead_response))
	destination.x += _look_ahead_offset
	var desired_aim := Vector3.ZERO
	var response: float = look_ahead_response
	if target is BreachPlayer:
		var weapons: BreachWeapons = (target as BreachPlayer).weapons
		var spec: WeaponSpec = weapons.current_spec()
		response = maxf(0.05, spec.aim_camera_response)
		if weapons.aiming and spec.aim_camera_enabled:
			var rect: Rect2 = get_viewport().get_visible_rect()
			var cursor: Vector2 = (weapons.pointer_screen_position() - rect.get_center()) / (rect.size * 0.5)
			cursor = cursor.clamp(Vector2(-1, -1), Vector2.ONE)
			desired_aim = Vector3(cursor.x * spec.aim_camera_offset.x, -cursor.y * spec.aim_camera_offset.y, 0.0)
	_aim_offset = _aim_offset.lerp(desired_aim, 1.0 - exp(-delta / response))
	destination += _aim_offset
	global_position = global_position.lerp(destination, 1.0 - exp(-follow_speed * delta))
