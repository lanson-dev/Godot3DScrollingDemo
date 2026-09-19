@tool
class_name MuzzleFlashProfile
extends Resource
## Duplicate a rifle/shotgun template for a weapon; each mounted view owns its animation copy.

@export var flame_scale: Vector3 = Vector3(1.6, 1.36, 1.36):
	set(value):
		flame_scale = value
		emit_changed()
@export_range(0.01, 0.5, 0.005) var duration: float = 0.055:
	set(value):
		duration = value
		emit_changed()
@export_range(0.0, 8.0, 0.1) var light_energy: float = 1.8:
	set(value):
		light_energy = value
		emit_changed()
@export_range(0.1, 6.0, 0.1) var light_range: float = 1.8:
	set(value):
		light_range = value
		emit_changed()
## Base spark radius in metres, before the saved emitter's random size variation.
@export_range(0.001, 0.05, 0.001) var spark_radius: float = 0.012:
	set(value):
		spark_radius = value
		emit_changed()

func is_valid() -> bool:
	return flame_scale.is_finite() and flame_scale.x > 0.0 and flame_scale.y > 0.0 and flame_scale.z > 0.0 \
		and is_finite(duration) and duration > 0.0 and duration <= 0.5 \
		and is_finite(light_energy) and light_energy >= 0.0 \
		and is_finite(light_range) and light_range > 0.0 and is_finite(spark_radius) and spark_radius > 0.0

func apply_sparks(effect: Node3D) -> void:
	if not effect is CPUParticles3D or not is_valid():
		return
	var particles := effect as CPUParticles3D
	var sphere := particles.mesh as SphereMesh
	if sphere != null and sphere.radius > 0.0:
		var factor: float = spark_radius / sphere.radius
		particles.scale_amount_min *= factor
		particles.scale_amount_max *= factor
