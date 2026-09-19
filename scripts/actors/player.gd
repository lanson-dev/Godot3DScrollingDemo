class_name BreachPlayer
extends BreachActor

signal status_changed
signal hurt(amount: float)
signal died

@export_range(0.6, 0.95, 0.01) var crouch_height_ratio: float = 0.82

@onready var health_component: BreachHealth = $Health
@onready var weapons: BreachWeapons = $Weapons
@onready var visual: Node3D = $VisualRoot
@onready var body_collision: CollisionShape3D = $CollisionShape3D

var _standing_capsule: CapsuleShape3D
var _standing_center: Vector3
var _standing_chest_height: float
var _capsule_crouched: bool = false
var _alive_collision_layer: int


func _ready() -> void:
	super._ready()
	_standing_capsule = body_collision.shape.duplicate() as CapsuleShape3D
	_standing_center = body_collision.position
	_standing_chest_height = weapons.chest_height
	_alive_collision_layer = collision_layer
	health_component.died.connect(_die)
	health_component.changed.connect(func(_hp: float, _maximum: float) -> void: status_changed.emit())
	fell.connect(func() -> void: health_component.damage(health_component.health))


func _physics_process(delta: float) -> void:
	_update_crouch()
	super._physics_process(delta)


func _movement_speed() -> float:
	if weapons.aiming and controls_enabled:
		return (crouch_speed if crouching else walk_speed) * weapons.current_spec().ads_move_multiplier
	return super._movement_speed()


func _update_crouch() -> void:
	if not controls_enabled:
		return
	if human_control:
		crouch_requested = Input.is_action_pressed("crouch")
	var wants_crouch: bool = crouch_requested
	if not wants_crouch and crouching and not _capsule_fits(_standing_capsule):
		wants_crouch = true
	if wants_crouch != crouching:
		crouching = wants_crouch
		if not crouching:
			_set_stance_capsule(false)
		visual.call("set_crouching", crouching)
	# Keep standing clearance until the crouch animation has finished lowering the body.
	if crouching and not _capsule_crouched and visual.call("is_crouch_ready"):
		_set_stance_capsule(true)


func _capsule_fits(shape: CapsuleShape3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := shape.duplicate() as CapsuleShape3D
	capsule.height -= 0.01
	query.shape = capsule
	query.transform = global_transform * Transform3D(body_collision.basis, _standing_center)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _set_stance_capsule(lowered: bool) -> void:
	_capsule_crouched = lowered
	var capsule := _standing_capsule.duplicate() as CapsuleShape3D
	if lowered:
		capsule.height = maxf(capsule.radius * 2.0, capsule.height * crouch_height_ratio)
	body_collision.shape = capsule
	var height_delta: float = _standing_capsule.height - capsule.height
	body_collision.position = _standing_center - Vector3.UP * height_delta * 0.5
	weapons.chest_height = _standing_chest_height - height_delta


func apply_damage(amount: float, _hit_position: Vector3, _direction: Vector3 = Vector3.ZERO) -> void:
	if not controls_enabled or not is_finite(amount) or amount <= 0.0 or health_component.health <= 0.0:
		return
	visual.call("play_hit")
	health_component.damage(amount)
	hurt.emit(amount)


func _die() -> void:
	settle_as_corpse()
	weapons.cancel_input()
	weapons.reload_remaining = 0.0
	visual.call("play_death")
	collision_layer = 0
	died.emit()


func respawn(at: Vector3) -> void:
	weapons.cancel_input()
	weapons.reload_remaining = 0.0
	weapons.cooldown = 0.0
	weapons.action_audio.stop()
	weapons.gun_audio.stop()
	reset_at(at)
	crouching = false
	_set_stance_capsule(false)
	collision_layer = _alive_collision_layer
	visual.call("reset_visual")
	health_component.reset()
	controls_enabled = true
