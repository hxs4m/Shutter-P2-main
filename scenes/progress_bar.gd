extends ProgressBar

@export_group("Fade Settings")
@export var fade_in_duration: float = 0.3
@export var fade_out_duration: float = 0.5
@export var alpha_step: float = 0.25 # Stepped fade resolution (0.25 = 4 distinct steps)

var _target_alpha: float = 0.0
var _current_alpha: float = 0.0


func _ready() -> void:
	# Hide by default on start
	modulate.a = 0.0
	visible = false


func _process(delta: float) -> void:
	if modulate.a <= 0.0 and _target_alpha == 0.0:
		visible = false
		return

	visible = true

	# Step alpha smoothly towards target, then apply snapping
	var fade_speed: float = (1.0 / fade_in_duration) if _target_alpha > _current_alpha else (1.0 / fade_out_duration)
	_current_alpha = move_toward(_current_alpha, _target_alpha, fade_speed * delta)

	# Apply retro stepped modulation
	modulate.a = snappedf(_current_alpha, alpha_step)


func update_stamina(current_stamina: float, max_stamina: float, is_sprinting: bool) -> void:
	max_value = max_stamina
	value = current_stamina

	# Show bar when actively sprinting OR when stamina is regenerating back to max
	if is_sprinting or current_stamina < max_stamina:
		_target_alpha = 1.0
	else:
		_target_alpha = 0.0
