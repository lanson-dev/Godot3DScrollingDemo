class_name BreachEnemy
extends BreachActor

enum State { PATROL, CHASE, ATTACK, DEAD }

signal died

@export var target: BreachPlayer
@export_enum("Left:-1", "Right:1") var patrol_start_direction: int = 1
@export_range(0.5, 30.0, 0.5) var patrol_radius: float = 5.0
@export_range(1.0, 50.0, 0.5) var detection_range: float = 18.0
@export_range(1.0, 28.0, 0.5) var firing_range: float = 15.0
@export_range(1.0, 20.0, 0.5) var preferred_distance: float = 7.5
@export_range(0.1, 30.0, 0.1) var memory_seconds: float = 6.0
@export_range(0.0, 3.0, 0.05) var reaction_seconds: float = 0.45
@export_range(0.1, 3.0, 0.1) var jump_retry_seconds: float = 0.7
@export_range(0.5, 2.2, 0.1) var maximum_jump_rise: float = 1.8
@export_range(0.8, 10.0, 0.1) var corpse_seconds: float = 2.5
@export var flash_material: Material

@onready var health_component: BreachHealth = $Health
@onready var weapons: BreachWeapons = $Weapons
@onready var visual: Node3D = $VisualRoot
@onready var health_label: Label3D = $HealthLabel
@onready var sight: RayCast3D = $Sight
@onready var probes: Node3D = $Probes
@onready var low_probe: RayCast3D = $Probes/Low
@onready var high_probe: RayCast3D = $Probes/High
@onready var near_ground: RayCast3D = $Probes/NearGround
@onready var landing_probe: RayCast3D = $Probes/Landing

var state: State = State.PATROL
var _patrol_direction: float = 1.0
var _memory_remaining: float = 0.0
var _reaction_remaining: float = 0.0
var _jump_remaining: float = 0.0
var _last_seen: Vector3
var _flash_remaining: float = 0.0
var _overlays: Dictionary[MeshInstance3D, Material] = {}


func _ready() -> void:
	super._ready()
	_patrol_direction = float(patrol_start_direction)
	health_component.changed.connect(_update_health)
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_die)
	fell.connect(func() -> void: health_component.damage(health_component.health))
	sight.add_exception(self)
	for probe: RayCast3D in [low_probe, high_probe, near_ground, landing_probe]:
		probe.add_exception(self)
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		_overlays[mesh] = mesh.material_overlay
	_update_health(health_component.health, health_component.max_health)
	_find_target()


func _physics_process(delta: float) -> void:
	_jump_remaining = maxf(0.0, _jump_remaining - delta)
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			for mesh: MeshInstance3D in _overlays:
				mesh.material_overlay = _overlays[mesh]
	if state != State.DEAD and controls_enabled:
		_think(delta)
	super._physics_process(delta)
	if state == State.DEAD and global_position.y < kill_height:
		_finish_corpse()


func _find_target() -> void:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as BreachPlayer


func _think(delta: float) -> void:
	_find_target()
	_memory_remaining = maxf(0.0, _memory_remaining - delta)
	_reaction_remaining = maxf(0.0, _reaction_remaining - delta)
	var visible_target: bool = false
	var blocker: Object
	var target_height: float = target.weapons.chest_height if is_instance_valid(target) else weapons.chest_height
	if is_instance_valid(target) and target.health_component.health > 0.0:
		var target_point: Vector3 = target.global_position + Vector3.UP * target_height
		sight.target_position = sight.to_local(target_point)
		sight.force_raycast_update()
		blocker = sight.get_collider() if sight.is_colliding() else null
		visible_target = global_position.distance_to(target.global_position) <= detection_range and blocker == target
		if visible_target:
			if _memory_remaining <= 0.0:
				_reaction_remaining = reaction_seconds
			_memory_remaining = memory_seconds
			_last_seen = target.global_position
	else:
		_memory_remaining = 0.0
	if _memory_remaining <= 0.0:
		_patrol()
		return
	var offset: Vector3 = _last_seen - global_position
	weapons.set_aim_target(_last_seen + Vector3.UP * target_height)
	var can_fire: bool = visible_target and offset.length() <= firing_range
	state = State.ATTACK if can_fire else State.CHASE
	if can_fire and _reaction_remaining <= 0.0:
		weapons.try_fire()
	var must_approach: bool = absf(offset.x) > preferred_distance or not can_fire or absf(offset.y) > 1.3
	sprinting = absf(offset.x) > firing_range
	move_axis = signf(offset.x) if must_approach and absf(offset.x) > 0.3 else 0.0
	if move_axis != 0.0:
		_navigate(true)


func _patrol() -> void:
	state = State.PATROL
	sprinting = false
	if global_position.x >= spawn_position.x + patrol_radius:
		_patrol_direction = -1.0
	elif global_position.x <= spawn_position.x - patrol_radius:
		_patrol_direction = 1.0
	move_axis = _patrol_direction
	weapons.set_aim_target(global_position + Vector3(_patrol_direction * 10.0, weapons.chest_height, 0))
	_navigate(false)


func _navigate(pursuing: bool) -> void:
	if not has_ground_support():
		return
	probes.scale.x = signf(move_axis)
	for probe: RayCast3D in [low_probe, high_probe, near_ground, landing_probe]:
		probe.force_raycast_update()
	var slope: bool = low_probe.is_colliding() and low_probe.get_collision_normal().y >= cos(floor_max_angle)
	var wall: bool = low_probe.is_colliding() and not slope
	if high_probe.is_colliding() and wall:
		_stop_at_edge(pursuing)
		return
	var gap: bool = not near_ground.is_colliding()
	if not wall and not gap:
		return
	var landing_ok: bool = landing_probe.is_colliding()
	if landing_ok:
		landing_ok = landing_probe.get_collision_normal().y > 0.65 and landing_probe.get_collision_point().y - global_position.y <= maximum_jump_rise
	if landing_ok and _jump_remaining <= 0.0:
		request_jump()
		_jump_remaining = jump_retry_seconds
	elif gap or wall:
		_stop_at_edge(pursuing)


func _stop_at_edge(pursuing: bool) -> void:
	move_axis = 0.0
	if not pursuing:
		_patrol_direction *= -1.0


func apply_damage(amount: float, _at: Vector3, _direction: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	health_component.damage(amount)


func _on_damaged(_amount: float) -> void:
	visual.call("play_hit")
	_flash_remaining = 0.12
	for mesh: MeshInstance3D in _overlays:
		mesh.material_overlay = flash_material
	if is_instance_valid(target):
		_last_seen = target.global_position
		_memory_remaining = memory_seconds
		_reaction_remaining = reaction_seconds


func _update_health(current: float, maximum: float) -> void:
	health_label.text = "%d / %d" % [ceili(current), ceili(maximum)]
	health_label.modulate = Color(1.0, 0.25, 0.12) if current < maximum * 0.35 else Color(1.0, 0.8, 0.75)


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	settle_as_corpse()
	collision_layer = 0
	weapons.cancel_input()
	weapons.reload_remaining = 0.0
	visual.call("play_death")
	health_label.hide()
	died.emit()
	get_tree().create_timer(corpse_seconds, false).timeout.connect(_finish_corpse)


func _finish_corpse() -> void:
	queue_free()
