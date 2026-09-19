class_name BreachHealth
extends Node

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0

var health: float = 100.0


func _ready() -> void:
	reset()


func damage(amount: float) -> float:
	if not is_finite(amount) or amount <= 0.0 or health <= 0.0:
		return 0.0
	var applied: float = minf(amount, health)
	health -= applied
	var killed: bool = health <= 0.0
	changed.emit(health, max_health)
	damaged.emit(applied)
	if killed:
		died.emit()
	return applied


func heal(amount: float) -> float:
	if not is_finite(amount) or amount <= 0.0 or health <= 0.0:
		return 0.0
	var restored: float = minf(amount, maxf(0.0, max_health - health))
	health += restored
	if restored > 0.0:
		changed.emit(health, max_health)
	return restored


func reset() -> void:
	health = max_health
	changed.emit(health, max_health)
