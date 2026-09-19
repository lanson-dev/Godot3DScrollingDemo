extends CPUParticles3D


func _ready() -> void:
	# Finish caller transform/color setup before the first native particle update.
	set_deferred("emitting", true)
	finished.connect(queue_free)
