class_name BreachMobileControls
extends Control

signal settings_requested

@export var player: BreachPlayer
@export var settings: BreachDemoSettings
@export_range(0.3, 2.0, 0.05) var look_sensitivity: float = 1.0

@onready var joystick: Panel = %Joystick
@onready var joystick_thumb: Panel = %JoystickThumb
@onready var settings_button: Panel = %SettingsButton
@onready var aim_button: Panel = %AimButton
@onready var jump_button: Panel = %JumpButton
@onready var crouch_button: Panel = %CrouchButton
@onready var fire_button: Panel = %FireButton

var active: bool = false
var _touches: Dictionary = {}
var _pressed_actions: Dictionary = {}
var _thumb_home_x: float = 0.0


func _ready() -> void:
	_thumb_home_x = joystick_thumb.position.x
	visible = active


func set_active(enabled: bool) -> void:
	if not enabled:
		_clear_input()
	active = enabled
	visible = enabled
	if player == null or not is_node_ready():
		return
	player.weapons.virtual_pointer_enabled = enabled
	if enabled:
		var center: Vector2 = get_viewport().get_visible_rect().get_center()
		var facing_sign: float = 1.0 if player.facing >= 0.0 else -1.0
		player.weapons.virtual_pointer_position = center + Vector2(220.0 * facing_sign, -30.0)


func _input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree() or player == null or get_tree().paused:
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
			and settings_button.get_global_rect().grow(20.0).has_point(click.position):
			settings_requested.emit()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and settings_button.get_global_rect().grow(20.0).has_point(touch.position):
			settings_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if not player.controls_enabled:
			return
		var tracked: bool = _touches.has(touch.index)
		if touch.pressed:
			_start_touch(touch.index, touch.position)
		else:
			_end_touch(touch.index)
		if tracked or _touches.has(touch.index):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not player.controls_enabled:
			return
		var drag: InputEventScreenDrag = event
		var role: StringName = _touches.get(drag.index, &"")
		if role == &"move":
			_update_joystick(drag.position)
		elif role == &"look" or role == &"fire":
			_move_pointer(drag.relative)
		if role != &"":
			get_viewport().set_input_as_handled()


func _start_touch(index: int, position: Vector2) -> void:
	if _touches.has(index):
		return
	if settings != null and settings.touch_button_at(position) != null:
		return
	for button: Panel in [fire_button, aim_button, jump_button, crouch_button]:
		if button.get_global_rect().has_point(position):
			var action: StringName = StringName(button.name.trim_suffix("Button").to_lower())
			_touches[index] = action
			if action == &"jump":
				player.request_jump()
			elif action == &"aim" or action == &"crouch":
				_set_action(action, not _pressed_actions.has(action))
			else:
				_set_action(action, true)
			return
	if joystick.get_global_rect().grow(24.0).has_point(position) and not _touches.values().has(&"move"):
		_touches[index] = &"move"
		_update_joystick(position)
	elif position.x >= get_viewport().get_visible_rect().size.x * 0.45 and not _touches.values().has(&"look"):
		_touches[index] = &"look"


func _end_touch(index: int) -> void:
	if not _touches.has(index):
		return
	var role: StringName = _touches[index]
	_touches.erase(index)
	if role == &"move":
		_update_joystick(joystick.get_global_rect().get_center())
	elif role != &"look" and role != &"jump" and role != &"aim" \
		and role != &"crouch" and not _touches.values().has(role):
		_set_action(role, false)


func _update_joystick(position: Vector2) -> void:
	var center: Vector2 = joystick.get_global_rect().get_center()
	var normalized: float = clampf((position.x - center.x) / (joystick.size.x * 0.5), -1.0, 1.0)
	joystick_thumb.position.x = _thumb_home_x + normalized * (joystick.size.x - joystick_thumb.size.x) * 0.5
	var strength: float = clampf((absf(normalized) - 0.15) / 0.85, 0.0, 1.0)
	_set_action(&"move_left", normalized < 0.0 and strength > 0.0, strength)
	_set_action(&"move_right", normalized > 0.0 and strength > 0.0, strength)
	_set_action(&"sprint", absf(normalized) >= 0.82)


func _move_pointer(relative: Vector2) -> void:
	var bounds: Rect2 = get_viewport().get_visible_rect()
	var next: Vector2 = player.weapons.virtual_pointer_position + relative * look_sensitivity
	player.weapons.virtual_pointer_position = Vector2(
		clampf(next.x, bounds.position.x, bounds.end.x),
		clampf(next.y, bounds.position.y, bounds.end.y))


func _set_action(action: StringName, pressed: bool, strength: float = 1.0) -> void:
	if action == &"aim":
		aim_button.modulate = Color(1.0, 0.84, 0.6) if pressed else Color.WHITE
	elif action == &"crouch":
		crouch_button.modulate = Color(1.0, 0.84, 0.6) if pressed else Color.WHITE
	if pressed:
		_pressed_actions[action] = true
		Input.action_press(action, strength)
	elif _pressed_actions.erase(action):
		Input.action_release(action)


func _clear_input() -> void:
	_touches.clear()
	for action: StringName in _pressed_actions.keys():
		Input.action_release(action)
	_pressed_actions.clear()
	if is_node_ready():
		joystick_thumb.position.x = _thumb_home_x
		aim_button.modulate = Color.WHITE
		crouch_button.modulate = Color.WHITE


func _process(_delta: float) -> void:
	if active and (player == null or not player.controls_enabled or get_tree().paused):
		_clear_input()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED \
		or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_clear_input()


func _exit_tree() -> void:
	_clear_input()
	if player != null and is_instance_valid(player) and is_instance_valid(player.weapons):
		player.weapons.virtual_pointer_enabled = false
