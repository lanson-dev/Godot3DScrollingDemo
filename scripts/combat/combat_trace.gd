class_name BreachCombatTrace
extends RefCounted
## Native queries preserve nearest hits; world cover wins equal-distance overlaps.

const WORLD_MASK: int = 1 | 8 # Static terrain and cover.


static func ray_hit(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	var original_mask: int = query.collision_mask
	if (original_mask & WORLD_MASK) == original_mask:
		return hit
	query.collision_mask &= WORLD_MASK
	var cover: Dictionary = space.intersect_ray(query)
	query.collision_mask = original_mask
	if not cover.is_empty() and (hit.is_empty() or query.from.distance_squared_to(cover["position"]) <= query.from.distance_squared_to(hit["position"]) + 0.000001):
		return cover
	return hit
