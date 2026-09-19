@tool
extends SkeletonModifier3D
## Ground targets for the existing rig; the saved TwoBoneIK3D nodes solve the legs.
## Foot.L/R are Root children, so they follow the same virtual endpoint explicitly.

@export var actor: BreachActor
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not value and is_node_ready():
			left_ik.active = false
			right_ik.active = false
@export var left_ik: TwoBoneIK3D
@export var right_ik: TwoBoneIK3D
@export_flags_3d_physics var ground_mask: int = 9
@export_range(0.1, 1.0, 0.01) var probe_above: float = 0.65
@export_range(0.1, 1.0, 0.01) var probe_below: float = 0.65
@export_range(0.01, 0.7, 0.01) var max_adjustment: float = 0.45
@export_range(0.0, 0.03, 0.001) var sole_clearance: float = 0.006
## Conservative sole corners in the original Foot bone space; morphs leave boots intact.
@export var left_sole: PackedVector3Array
@export var right_sole: PackedVector3Array

@onready var left_ray: RayCast3D = $LeftGround
@onready var right_ray: RayCast3D = $RightGround
@onready var targets: Array[Marker3D] = [$LeftTarget, $RightTarget]
@onready var poles: Array[Marker3D] = [$LeftKnee, $RightKnee]
var _feet: PackedInt32Array
var _uppers: PackedInt32Array
var _lowers: PackedInt32Array


func _ready() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	for side: String in ["L", "R"]:
		_feet.append(skeleton.find_bone("Foot." + side))
		_uppers.append(skeleton.find_bone("UpperLeg." + side))
		_lowers.append(skeleton.find_bone("LowerLeg." + side))


func _process_modification_with_delta(_delta: float) -> void:
	if not is_node_ready():
		return
	left_ik.active = false
	right_ik.active = false
	if Engine.is_editor_hint() or not enabled or actor == null or not actor.is_inside_tree():
		return
	if not actor.has_ground_support() or actor.jump_count > 0 or _feet.has(-1) or _uppers.has(-1) or _lowers.has(-1):
		return
	var skeleton: Skeleton3D = get_skeleton()
	_place_leg(skeleton, 0, left_ik, left_ray, left_sole)
	_place_leg(skeleton, 1, right_ik, right_ray, right_sole)


func _place_leg(skeleton: Skeleton3D, side: int, ik: TwoBoneIK3D, ray: RayCast3D, sole: PackedVector3Array) -> void:
	if sole.size() != 4:
		return
	var original: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_feet[side])
	var center: Vector3 = Vector3.ZERO
	var animated_floor: float = INF
	for corner: Vector3 in sole:
		center += original * corner / 4.0
		animated_floor = minf(animated_floor, (original * corner).y)
	var contact: Dictionary = _ground(ray, center)
	if contact.is_empty():
		return
	var normal: Vector3 = contact.normal
	# Flat-ground animation stays unchanged; a foot beyond a slope may still land on a flat tile.
	if normal.y > 0.9999 and actor.get_floor_normal().y > 0.9999:
		return
	var placed: Transform3D = original
	placed.basis = Basis(Quaternion(Vector3.UP, normal)) * original.basis
	var lift: float = maxf(0.0, animated_floor - actor.global_position.y)
	var required_y: float = -INF
	for corner: Vector3 in sole:
		var offset: Vector3 = placed.basis * corner
		var ground: Dictionary = _ground(ray, placed.origin + offset)
		if not ground.is_empty():
			required_y = maxf(required_y, float(ground.point.y) + lift + sole_clearance - offset.y)
	if not is_finite(required_y):
		return
	placed.origin.y = clampf(required_y, original.origin.y - max_adjustment, original.origin.y + max_adjustment)
	var lower: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_lowers[side])
	var upper: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_uppers[side])
	var tail: Vector3 = Vector3.UP * ik.get_end_bone_length(0)
	# Preserve the rig's small independent Foot-to-lower-tail offset, including animated poses.
	var endpoint: Vector3 = placed * (original.affine_inverse() * (lower * tail))
	var rest_upper: Transform3D = skeleton.get_bone_global_rest(_uppers[side])
	var rest_lower: Transform3D = skeleton.get_bone_global_rest(_lowers[side])
	var upper_length: float = (skeleton.global_basis * (rest_lower.origin - rest_upper.origin)).length()
	var lower_length: float = (skeleton.global_basis * rest_lower.basis * tail).length()
	var reach: Vector3 = endpoint - upper.origin
	if reach.length_squared() < 0.000001:
		return
	var limited: Vector3 = upper.origin + reach.normalized() * clampf(reach.length(),
		absf(upper_length - lower_length) + 0.0001, upper_length + lower_length - 0.0001)
	placed.origin += limited - endpoint
	targets[side].global_position = limited
	var original_end: Vector3 = lower * tail
	var axis: Vector3 = (original_end - upper.origin).normalized()
	var bend: Vector3 = lower.origin - upper.origin
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = skeleton.global_basis.z.normalized()
	poles[side].global_position = lower.origin + bend.normalized() * 0.35
	skeleton.set_bone_global_pose(_feet[side], skeleton.global_transform.affine_inverse() * placed)
	ik.active = true


func _ground(ray: RayCast3D, at: Vector3) -> Dictionary:
	# Start below the parallel upper plate, relative to the actual grounded actor, not a guessed plane.
	ray.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, actor.global_position.y + probe_above, at.z))
	ray.target_position = Vector3(0, -probe_above - probe_below, 0)
	ray.collision_mask = ground_mask
	ray.add_exception(actor)
	ray.force_raycast_update()
	if not ray.is_colliding() or ray.get_collision_normal().y < cos(actor.floor_max_angle):
		return {}
	return {"point": ray.get_collision_point(), "normal": ray.get_collision_normal()}
