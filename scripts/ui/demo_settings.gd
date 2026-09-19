class_name BreachDemoSettings
extends Control

signal add_npc_requested
signal respawn_requested
signal mode_selected(mode: int)
signal panel_toggled(open: bool)

@export var hud: BreachDemoHUD

const MODE_AUTO := 0
const MODE_TOUCH := 1
const MODE_KEYBOARD_MOUSE := 2

@onready var pc_button: Button = %PCButton
@onready var backdrop: ColorRect = %Backdrop
@onready var panel: ColorRect = $Backdrop/Panel
@onready var close_button: Button = %CloseButton
@onready var add_button: Button = %AddNPCButton
@onready var respawn_button: Button = %RespawnButton
@onready var mode_buttons: Array[Button] = [%AutoButton, %TouchButton, %KeyboardButton]

var selected_mode: int = MODE_AUTO
var panel_open: bool = false
var _touch_index: int = -1
var _touch_button: BaseButton


func _ready() -> void:
	backdrop.hide()
	panel_open = false
	pc_button.pressed.connect(toggle_panel)
	close_button.pressed.connect(close_panel)
	add_button.pressed.connect(_request_add_npc)
	respawn_button.pressed.connect(_request_respawn)
	for index: int in mode_buttons.size():
		mode_buttons[index].pressed.connect(_select_mode.bind(index))
	set_mode(selected_mode)
	panel.pivot_offset = panel.size * 0.5
	get_viewport().size_changed.connect(_update_panel_scale)
	_update_panel_scale()


func _update_panel_scale() -> void:
	var height: float = maxf(1.0, float(get_window().size.y))
	var factor: float = clampf(720.0 / height, 1.0, 2.0)
	panel.scale = Vector2.ONE * factor


func set_touch_mode(touch_enabled: bool) -> void:
	pc_button.visible = not touch_enabled


func set_mode(mode: int) -> void:
	if mode < MODE_AUTO or mode > MODE_KEYBOARD_MOUSE:
		return
	selected_mode = mode
	for index: int in mode_buttons.size():
		mode_buttons[index].set_pressed_no_signal(index == mode)


func open_panel() -> void:
	if panel_open:
		return
	panel_open = true
	backdrop.show()
	panel_toggled.emit(true)


func close_panel() -> void:
	if not panel_open:
		return
	panel_open = false
	backdrop.hide()
	panel_toggled.emit(false)


func toggle_panel() -> void:
	if panel_open:
		close_panel()
	else:
		open_panel()


func _select_mode(mode: int) -> void:
	set_mode(mode)
	mode_selected.emit(mode)


func _request_add_npc() -> void:
	close_panel()
	add_npc_requested.emit()


func _request_respawn() -> void:
	close_panel()
	respawn_requested.emit()


func _input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return
	var touch := event as InputEventScreenTouch
	var intercept: bool = panel_open or _touch_button != null
	if touch.pressed and _touch_index < 0:
		_touch_button = touch_button_at(touch.position)
		if _touch_button != null or panel_open:
			_touch_index = touch.index
			intercept = true
	elif not touch.pressed and touch.index == _touch_index:
		var button: BaseButton = _touch_button
		_touch_index = -1
		_touch_button = null
		if button != null and _contains(button, touch.position):
			button.pressed.emit()
	if intercept or panel_open:
		get_viewport().set_input_as_handled()


func touch_button_at(position: Vector2) -> BaseButton:
	var candidates: Array[BaseButton]
	if panel_open:
		candidates = [close_button, add_button, respawn_button, mode_buttons[0], mode_buttons[1], mode_buttons[2]]
	else:
		candidates = [pc_button]
		if hud != null:
			candidates.append_array([hud.chinese_button, hud.english_button, hud.repository_button])
	for button: BaseButton in candidates:
		if button.is_visible_in_tree() and not button.disabled and _contains(button, position):
			return button
	return null


func _contains(button: BaseButton, position: Vector2) -> bool:
	var local_position: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * position
	return Rect2(Vector2.ZERO, button.size).has_point(local_position)


func _unhandled_key_input(event: InputEvent) -> void:
	if panel_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
