extends Node3D


func _enter_tree() -> void:
	TranslationServer.set_locale("zh_CN")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		get_tree().reload_current_scene()
		get_viewport().set_input_as_handled()
