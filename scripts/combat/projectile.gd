class_name BreachProjectile
extends Node3D

signal hit_confirmed(position: Vector3)

@export var impact_scene: PackedScene

var _direction: Vector3
var _damage: float
var _speed: float
var _remaining: float
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	set_physics_process(false)


func launch(origin: Vector3, direction: Vector3, damage: float, speed: float, max_distance: float, mask: int, excluded: Array[RID]) -> void:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		queue_free()
		return
	if not is_finite(damage) or damage < 0.0 or not is_finite(speed) or speed <= 0.0 or not is_finite(max_distance) or max_distance <= 0.0:
		queue_free()
		return
	global_position = origin
	_direction = direction.normalized()
	global_basis = Basis(Quaternion(Vector3.RIGHT, _direction))
	reset_physics_interpolation()
	_damage = damage
	_speed = speed
	_remaining = max_distance
	_ray.collision_mask = mask
	_ray.exclude = excluded
	_ray.hit_from_inside = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var distance: float = minf(_speed * delta, _remaining)
	_ray.from = global_position
	_ray.to = global_position + _direction * distance
	var hit: Dictionary = BreachCombatTrace.ray_hit(get_world_3d().direct_space_state, _ray)
	if not hit.is_empty():
		set_physics_process(false)
		var hit_position: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		if collider.has_method("apply_damage"):
			collider.call("apply_damage", _damage, hit_position, _direction)
			hit_confirmed.emit(hit_position)
		elif impact_scene != null:
			var impact := impact_scene.instantiate() as Node3D
			get_tree().current_scene.add_child(impact)
			impact.global_position = hit_position
		queue_free()
		return
	global_position = _ray.to
	_remaining -= distance
	if _remaining <= 0.0:
		set_physics_process(false)
		queue_free()
