extends Node3D

const AUTO: int = 0
const TOUCH: int = 1
const KEYBOARD_MOUSE: int = 2
const CONTROL_SETTINGS: String = "user://3c_controls.cfg"

@export var enemy_scene: PackedScene = preload("res://scenes/actors/enemy.tscn")

@onready var player: BreachPlayer = $Player
@onready var demo_hud: BreachDemoHUD = $HUD/DemoHUD
@onready var mobile_controls: BreachMobileControls = $HUD/MobileControls
@onready var settings: BreachDemoSettings = $HUD/DemoSettings

var _mode: int = AUTO
var _auto_touch: bool = false


func _enter_tree() -> void:
	TranslationServer.set_locale("zh_CN")


func _ready() -> void:
	mobile_controls.settings_requested.connect(settings.toggle_panel)
	settings.add_npc_requested.connect(_add_npc)
	settings.respawn_requested.connect(_respawn_player)
	settings.mode_selected.connect(_select_mode)
	settings.panel_toggled.connect(_on_settings_toggled)
	var config := ConfigFile.new()
	if config.load(CONTROL_SETTINGS) == OK:
		_mode = clampi(int(config.get_value("controls", "mode", AUTO)), AUTO, KEYBOARD_MOUSE)
	_auto_touch = DisplayServer.is_touchscreen_available()
	settings.set_mode(_mode)
	_apply_controls()


func _input(event: InputEvent) -> void:
	if _mode != AUTO or settings.panel_open:
		return
	if event is InputEventScreenTouch and event.pressed and not _auto_touch:
		_auto_touch = true
		_apply_controls()
		mobile_controls._input(event)
	elif event is InputEventKey and event.pressed and not event.echo and _auto_touch:
		_auto_touch = false
		_apply_controls()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()


func _select_mode(mode: int) -> void:
	_mode = clampi(mode, AUTO, KEYBOARD_MOUSE)
	var config := ConfigFile.new()
	config.set_value("controls", "mode", _mode)
	config.save(CONTROL_SETTINGS)
	_apply_controls()


func _apply_controls() -> void:
	var touch: bool = _mode == TOUCH or (_mode == AUTO and _auto_touch)
	mobile_controls.set_active(touch and not settings.panel_open)
	demo_hud.set_touch_mode(touch)
	settings.set_touch_mode(touch)


func _on_settings_toggled(open: bool) -> void:
	mobile_controls.set_active(not open and (_mode == TOUCH or (_mode == AUTO and _auto_touch)))
	get_tree().paused = open


func _respawn_player() -> void:
	player.respawn(player.spawn_position)


func _add_npc() -> void:
	if enemy_scene == null:
		return
	var direction: float = 1.0 if player.facing >= 0.0 else -1.0
	for side: float in [direction, -direction]:
		for step: int in 8:
			var x: float = player.global_position.x + side * (5.0 + float(step) * 1.5)
			if absf(x) > 18.0 or not _spawn_clear(x):
				continue
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, 0.0), Vector3(x, -8.0, 0.0), 1)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				continue
			var enemy := enemy_scene.instantiate() as BreachEnemy
			if enemy == null:
				return
			enemy.position = Vector3(x, (hit["position"] as Vector3).y + 0.05, 0.0)
			enemy.target = player
			add_child(enemy)
			return


func _spawn_clear(x: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as BreachEnemy
		if enemy != null and enemy.controls_enabled and absf(enemy.global_position.x - x) < 1.2:
			return false
	return true
