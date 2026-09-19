@tool
extends SkeletonModifier3D
## Keep the standing torso balanced uphill before shoulder shaping and weapon aim.

@export var actor: BreachActor
@export_range(0.0, 35.0, 1.0) var minimum_uphill_degrees: float = 20.0
var _torso: int = -1


func _ready() -> void:
	_torso = get_skeleton().find_bone("Torso")


func _process_modification_with_delta(_delta: float) -> void:
	if Engine.is_editor_hint() or actor == null or _torso < 0:
		return
	if not actor.has_ground_support() or actor.jump_count > 0 or actor.crouching:
		return
	var normal: Vector3 = actor.get_floor_normal()
	if absf(normal.x) < 0.001 or minimum_uphill_degrees <= 0.0:
		return
	var skeleton: Skeleton3D = get_skeleton()
	var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_torso)
	var uphill_sign: float = -signf(normal.x)
	var slope_fraction: float = clampf(absf(atan2(normal.x, normal.y)) / (PI / 4.0), 0.0, 1.0)
	var minimum_angle: float = deg_to_rad(minimum_uphill_degrees) * slope_fraction
	var current_angle: float = atan2(pose.basis.y.x, pose.basis.y.y)
	var missing_angle: float = maxf(0.0, minimum_angle - current_angle * uphill_sign)
	# Positive Z rotation reduces atan2(up.x, up.y), hence the opposite sign.
	pose.basis = Basis(Vector3.BACK, -uphill_sign * missing_angle) * pose.basis
	skeleton.set_bone_global_pose(_torso, skeleton.global_transform.affine_inverse() * pose)
