extends Node

@export var actor: BreachActor
@export var dust_scene: PackedScene
@export var minimum_landing_speed: float = 2.0
@export_range(0.2, 8.0, 0.05) var walk_cycle_distance: float = 2.18
@export_range(0.2, 10.0, 0.05) var run_cycle_distance: float = 1.76
@export_range(0.2, 3.0, 0.05) var crouch_cycle_distance: float = 1.0
@export var footstep_sounds: Array[AudioStream] = []
@export var full_landing_speed: float = 16.0
@export_range(-40.0, 0.0, 1.0) var landing_quiet_db: float = -16.0
@export_range(-40.0, 0.0, 1.0) var landing_loud_db: float = -3.0

@onready var _audio_origin: Node3D = $AudioOrigin
@onready var _feet: Array[AudioStreamPlayer3D] = [$AudioOrigin/LeftStep, $AudioOrigin/RightStep]
@onready var _landing: AudioStreamPlayer3D = $AudioOrigin/Landing

var _distance: float = 0.0
var _foot: int = 0
var _sound_index: int = 0
var _was_grounded: bool = false


func _ready() -> void:
	if actor == null:
		set_physics_process(false)
		return
	actor.landed.connect(_on_landed)
	actor.jumped.connect(_on_jumped)
	_audio_origin.global_position = actor.global_position


func _physics_process(_delta: float) -> void:
	_audio_origin.global_position = actor.global_position
	var grounded: bool = actor.has_ground_support()
	if not grounded or not _was_grounded or not actor.controls_enabled or absf(actor.velocity.x) < 0.1:
		_distance = 0.0
		_was_grounded = grounded
		return
	_was_grounded = grounded
	var speed: float = actor.get_real_velocity().length()
	var running: float = clampf((speed - actor.walk_speed) / maxf(actor.sprint_speed - actor.walk_speed, 0.1), 0.0, 1.0)
	var step_distance: float = lerpf(walk_cycle_distance, run_cycle_distance, running) * 0.5
	if actor.crouching:
		step_distance = crouch_cycle_distance * 0.5
	_distance += actor.get_position_delta().length()
	if _distance >= step_distance:
		_distance -= step_distance
		_play_step()


func _play_step() -> void:
	if footstep_sounds.is_empty():
		return
	var foot: AudioStreamPlayer3D = _feet[_foot]
	foot.stream = footstep_sounds[_sound_index]
	foot.play()
	_foot = 1 - _foot
	_sound_index = (_sound_index + 1) % footstep_sounds.size()


func _on_landed(impact_speed: float) -> void:
	_distance = 0.0
	if impact_speed >= minimum_landing_speed:
		_spawn_dust(Color(0.64, 0.7, 0.7, 0.65))
		_audio_origin.global_position = actor.global_position
		_landing.volume_db = lerpf(landing_quiet_db, landing_loud_db, clampf(impact_speed / full_landing_speed, 0.0, 1.0))
		_landing.play()


func _on_jumped(is_air_jump: bool) -> void:
	_distance = 0.0
	_spawn_dust(Color(0.18, 0.85, 0.8, 0.8) if is_air_jump else Color(0.64, 0.7, 0.7, 0.5))


func _spawn_dust(tint: Color) -> void:
	if dust_scene == null:
		return
	var burst := dust_scene.instantiate() as CPUParticles3D
	actor.get_parent().add_child(burst)
	burst.global_position = actor.global_position + Vector3.UP * 0.08
	burst.color = tint
