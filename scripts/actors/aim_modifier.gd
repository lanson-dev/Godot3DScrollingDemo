@tool
extends SkeletonModifier3D

@export var hand: BoneAttachment3D
@export var muzzle: Marker3D
@export var direction: Vector3 = Vector3.RIGHT
@export_range(0.0, 75.0, 1.0) var tool_pitch_limit: float = 65.0
@export_range(0.0, 1.0, 0.05) var head_follow: float = 0.3
@export_range(0.0, 110.0, 1.0) var elbow_bend: float = 95.0
@export_range(0.0, 60.0, 1.0) var steep_elbow_lift: float = 35.0
@export_range(30.0, 90.0, 1.0) var downward_extension_angle: float = 50.0
@export var support_ik: TwoBoneIK3D
var tool_mode: bool = false
var free_arm: bool = false
var _arm_weight: float = 1.0
var target_point: Vector3 = Vector3.INF


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or not direction.is_finite() or direction.length_squared() < 0.001:
		return
	var target: Vector3 = (skeleton.global_basis.inverse() * direction).normalized()
	var pitch: float = asin(clampf(target.y, -1.0, 1.0))
	_arm_weight = move_toward(_arm_weight, 0.0 if tool_mode or free_arm else 1.0, delta / 0.12)
	if support_ik != null:
		support_ik.influence = _arm_weight
	if tool_mode:
		var yaw: float = clampf(atan2(target.x, target.z), -PI * 0.4, PI * 0.4)
		var rotation_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -clampf(pitch, -deg_to_rad(tool_pitch_limit), deg_to_rad(tool_pitch_limit)))
		_rotate_bone(skeleton, "Torso", rotation_basis)
	elif _arm_weight > 0.001 and hand != null and muzzle != null:
		var pose: Dictionary = gun_pose(target_point, _arm_weight)
		skeleton.set_bone_global_pose(skeleton.find_bone("UpperArm.R"), pose["upper"])
		skeleton.set_bone_global_pose(skeleton.find_bone("LowerArm.R"), pose["lower"])
		hand.on_skeleton_update()
	if not tool_mode:
		_rotate_bone(skeleton, "Neck", Basis(Vector3.RIGHT, -pitch * head_follow))


func _rotate_bone(skeleton: Skeleton3D, bone_name: String, rotation_basis: Basis) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index < 0:
		return
	var pose: Transform3D = skeleton.get_bone_global_pose(index)
	pose.basis = rotation_basis * pose.basis
	skeleton.set_bone_global_pose(index, pose)


func gun_pose(point: Vector3, weight: float = 1.0) -> Dictionary:
	var skeleton: Skeleton3D = get_skeleton()
	var upper: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("UpperArm.R"))
	var lower: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("LowerArm.R"))
	var grip: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone(hand.bone_name))
	var desired: Vector3 = (skeleton.global_basis.inverse() * direction).normalized()
	var pitch: float = asin(clampf(desired.y, -1.0, 1.0))
	var extension: float = deg_to_rad(downward_extension_angle) if pitch < 0.0 else PI / 2.0
	var bend: float = deg_to_rad(lerpf(elbow_bend, -steep_elbow_lift, clampf(absf(pitch) / extension, 0.0, 1.0))) * weight
	var rotation_basis := Basis(Vector3.RIGHT, bend)
	var rotation := Transform3D(rotation_basis, upper.origin - rotation_basis * upper.origin)
	upper = rotation * upper
	lower = rotation * lower
	grip = rotation * grip
	rotation_basis = Basis(Vector3.RIGHT, -bend)
	rotation = Transform3D(rotation_basis, lower.origin - rotation_basis * lower.origin)
	lower = rotation * lower
	grip = rotation * grip
	var relative: Transform3D = hand.global_transform.affine_inverse() * muzzle.global_transform
	var barrel: Transform3D = grip * relative
	var forward: Vector3 = barrel.basis.x.normalized()
	var reachable: bool = true
	var from: Vector3 = forward
	var to: Vector3 = desired
	if point.is_finite():
		var offset: Vector3 = barrel.origin - lower.origin
		var target: Vector3 = skeleton.to_local(point) - lower.origin
		var discriminant: float = target.length_squared() - offset.cross(forward).length_squared()
		var distance: float = -offset.dot(forward) + sqrt(maxf(discriminant, 0.0))
		reachable = discriminant >= 0.0 and distance > 0.02 and target.length_squared() > 0.0001
		if reachable:
			# R(offset + distance * forward) = target: the offset barrel ray passes through the target.
			from = (offset + distance * forward).normalized()
			to = target.normalized()
	var correction := Quaternion(from, to)
	if from.dot(to) < -0.99999:
		var axis: Vector3 = lower.basis.x.normalized()
		axis = (axis - from * axis.dot(from)).normalized()
		if axis.length_squared() < 0.001:
			axis = from.cross(lower.basis.y).normalized()
		correction = Quaternion(axis, PI)
	rotation_basis = Basis(Quaternion.IDENTITY.slerp(correction, weight))
	rotation = Transform3D(rotation_basis, lower.origin - rotation_basis * lower.origin)
	lower = rotation * lower
	return {"upper": upper, "lower": lower}
