extends ColorRect

signal fade_completed

@export var flash_hold_time: float = 0.03  # Initial shutter hold time
@export var fade_steps: int = 5            # Total steps in the fade out
@export var step_duration: float = 0.02     # Delay per step (lower = faster camera flash)

var is_gazing: bool = false


func _ready() -> void:
	add_to_group('GazeOverlay')
	color = Color(0.0, 0.0, 0.0, 0.0)


func _process(_delta: float) -> void:
	pass


func start_gaze_flash() -> void:
	is_gazing = true
	color = Color(0.0, 0.0, 0.0, 0.0)


func stop_gaze_flash() -> void:
	is_gazing = false
	color = Color(0.0, 0.0, 0.0, 0.0)


func trigger_full_red_stepped_fade(on_respawn_callable: Callable = Callable()) -> void:
	is_gazing = false
	
	# Instant shutter snap to solid black
	color = Color(0.0, 0.0, 0.0, 1.0)

	if on_respawn_callable.is_valid():
		on_respawn_callable.call()

	var tween := create_tween()
	
	# Brief shutter hold
	if flash_hold_time > 0.0:
		tween.tween_interval(flash_hold_time)

	# Stepped camera flash fade out (pure black to transparent)
	for i in range(fade_steps - 1, -1, -1):
		var target_alpha: float = float(i) / float(fade_steps)
		
		# Bind parameter directly to the Callable
		var set_alpha_func := (func(a: float) -> void:
			color = Color(0.0, 0.0, 0.0, a)
		).bind(target_alpha)
		
		tween.tween_callback(set_alpha_func)
		tween.tween_interval(step_duration)

	tween.tween_callback(func() -> void:
		color = Color(0.0, 0.0, 0.0, 0.0)
		fade_completed.emit()
	)
