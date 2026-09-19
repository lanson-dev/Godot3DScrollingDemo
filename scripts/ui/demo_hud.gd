extends Control

const REPOSITORY_URL: String = "https://github.com/lanson-dev/Godot3DScrollingDemo"

@export var player: BreachPlayer
@export var hide_system_pointer: bool = true
@export var reticle_color: Color = Color(0.95, 0.95, 0.91)
@export_range(2.0, 12.0, 0.5) var reticle_line_length: float = 6.0
@export_range(1.0, 4.0, 0.25) var reticle_line_width: float = 1.5

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_value: Label = %HealthValue
@onready var weapon_name: Label = %WeaponName
@onready var ammo_value: Label = %AmmoValue
@onready var reload_hint: Label = %ReloadHint
@onready var chinese_button: Button = %ChineseButton
@onready var english_button: Button = %EnglishButton
@onready var repository_button: TextureButton = %RepositoryButton

var _bound: bool = false
var _pointer: Vector2
var _reticle_visible: bool = false
var _spread_radius: float = 0.0


func _ready() -> void:
	chinese_button.pressed.connect(_set_language.bind("zh_CN"))
	english_button.pressed.connect(_set_language.bind("en"))
	repository_button.pressed.connect(_open_repository)
	_sync_language_buttons()
	_bind_player()


func bind_player(actor: BreachPlayer) -> void:
	if _bound:
		return
	player = actor
	if is_node_ready():
		_bind_player()


func _bind_player() -> void:
	if _bound or player == null:
		return
	_bound = true
	process_physics_priority = player.weapons.process_physics_priority - 1
	player.health_component.changed.connect(_refresh_health.unbind(2))
	player.weapons.changed.connect(_refresh_weapon)
	_refresh_health()
	_refresh_weapon()


func _physics_process(_delta: float) -> void:
	if player == null or not player.controls_enabled or get_tree().paused:
		return
	if get_viewport().gui_get_hovered_control() != null:
		player.weapons.cancel_input()


func _process(_delta: float) -> void:
	_pointer = get_local_mouse_position()
	_reticle_visible = player != null and player.controls_enabled and not get_tree().paused \
		and get_rect().has_point(_pointer) and get_viewport().gui_get_hovered_control() == null
	if _reticle_visible:
		var spec: WeaponSpec = player.weapons.current_spec()
		_spread_radius = clampf(spread_radius(get_viewport().get_camera_3d()),
			spec.crosshair_min_radius, spec.crosshair_max_radius)
	if hide_system_pointer:
		var mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN if _reticle_visible else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != mode:
			Input.mouse_mode = mode
	if player != null:
		_refresh_reload()
	queue_redraw()


func _draw() -> void:
	if not _reticle_visible:
		return
	var spec: WeaponSpec = player.weapons.current_spec()
	if spec.pellets > 1:
		var half_arc: float = minf(PI / 8.0, reticle_line_length / _spread_radius)
		for corner: int in 4:
			var angle: float = PI * (0.25 + corner * 0.5)
			draw_arc(_pointer, _spread_radius, angle - half_arc, angle + half_arc, 6,
				reticle_color, reticle_line_width, true)
	else:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(_pointer + axis * _spread_radius,
				_pointer + axis * (_spread_radius + reticle_line_length),
				reticle_color, reticle_line_width, true)
	draw_circle(_pointer, 2.0, reticle_color)


func spread_radius(camera: Camera3D) -> float:
	if player == null or camera == null:
		return 0.0
	var weapons: BreachWeapons = player.weapons
	var origin: Vector3 = weapons.spread_origin()
	var direction: Vector3 = weapons.spread_direction()
	var distance: float = maxf(0.0, (weapons.aim_target - origin).dot(direction))
	var center: Vector3 = origin + direction * distance
	if camera.is_position_behind(center):
		return 0.0
	var to_local: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var projected: Vector2 = to_local * camera.unproject_position(center)
	var radius: float = 0.0
	for side: float in [-1.0, 1.0]:
		var edge: Vector3 = direction.rotated(Vector3.BACK,
			deg_to_rad(weapons.spread_half_angle_degrees()) * side)
		var point: Vector3 = origin + edge * distance / maxf(0.001, edge.dot(direction))
		radius = maxf(radius, projected.distance_to(to_local * camera.unproject_position(point)))
	return radius


func _refresh_health() -> void:
	var health: BreachHealth = player.health_component
	health_bar.max_value = health.max_health
	health_bar.value = health.health
	health_value.text = "%d / %d" % [ceili(health.health), ceili(health.max_health)]


func _refresh_weapon() -> void:
	var weapons: BreachWeapons = player.weapons
	weapon_name.text = tr(weapons.current_spec().display_name)
	ammo_value.text = "%d / %d" % [weapons.magazines[weapons.selected], weapons.reserves[weapons.selected]]
	_refresh_reload()


func _refresh_reload() -> void:
	var weapons: BreachWeapons = player.weapons
	var spec: WeaponSpec = weapons.current_spec()
	if weapons.reload_remaining > 0.0:
		reload_hint.text = tr("HUD_RELOADING") % weapons.reload_remaining
		reload_hint.show()
	elif weapons.magazines[weapons.selected] == 0 and weapons.reserves[weapons.selected] == 0:
		reload_hint.text = tr("HUD_NO_AMMO")
		reload_hint.show()
	elif weapons.magazines[weapons.selected] < spec.magazine_size and weapons.reserves[weapons.selected] > 0:
		reload_hint.text = tr("HUD_RELOAD_HINT")
		reload_hint.show()
	else:
		reload_hint.hide()


func _set_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_sync_language_buttons()
	if player != null:
		_refresh_weapon()


func _open_repository() -> void:
	OS.shell_open(REPOSITORY_URL)


func _sync_language_buttons() -> void:
	var chinese: bool = TranslationServer.get_locale().begins_with("zh")
	chinese_button.set_pressed_no_signal(chinese)
	english_button.set_pressed_no_signal(not chinese)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync_language_buttons()
		if player != null:
			_refresh_weapon()


func _exit_tree() -> void:
	if hide_system_pointer and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
