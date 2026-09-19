extends CanvasLayer
## Screen Fade
## Full-screen blackout used for the "knocked out, then wake up" moment when
## the enemy catches the player.

@onready var fade_rect: ColorRect = $FadeRect

var _is_playing: bool = false


func _ready() -> void:
	add_to_group("ScreenFade")
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Quantizes the alpha into discrete PS1-style steps
func _set_stepped_alpha(target_alpha: float, step_size: float = 0.25) -> void:
	var current_color = fade_rect.color
	current_color.a = snappedf(clamp(target_alpha, 0.0, 1.0), step_size)
	fade_rect.color = current_color


## Custom stepped tween loop for PS1 aesthetic
func _tween_stepped_alpha(start_a: float, end_a: float, duration: float, steps: int = 4) -> void:
	var step_duration: float = duration / float(steps)
	for i in range(1, steps + 1):
		var progress: float = float(i) / float(steps)
		var lerped_alpha: float = lerp(start_a, end_a, progress)
		_set_stepped_alpha(lerped_alpha, 1.0 / float(steps))
		await get_tree().create_timer(step_duration, true, false, true).timeout


## Fades the screen to solid black in discrete steps.
func fade_to_black(fade_time: float = 0.2) -> void:
	_is_playing = true
	var start_a: float = fade_rect.color.a
	await _tween_stepped_alpha(start_a, 1.0, fade_time, 4)


## Holds on solid black, then blinks awake with a stepped PS1 effect.
func wake_up(hold_time: float = 1.0, fade_in_time: float = 0.1) -> void:
	await get_tree().create_timer(hold_time, true, false, true).timeout

	# Stepped blink sequence (eyelids fluttering)
	var blink_open_alphas := [0.75, 0.5, 0.25]
	for open_alpha in blink_open_alphas:
		# Crack open (stepped)
		await _tween_stepped_alpha(fade_rect.color.a, open_alpha, 0.08, 2)
		# Snap shut
		await _tween_stepped_alpha(fade_rect.color.a, 1.0, 0.06, 2)

	# Final stepped fade to clear
	await _tween_stepped_alpha(1.0, 0.0, fade_in_time, 4)

	_is_playing = false


## Convenience wrapper: fades out, deducts 1 minute from MainTimer while hidden,
## holds, blinks awake, and fades in.
func play_blackout(fade_out_time: float = 0.4, hold_time: float = 1.8, fade_in_time: float = 0.6) -> void:
	if _is_playing:
		return  # already mid-sequence; ignore a second trigger

	# 1. Screen goes black (stepped)
	await fade_to_black(fade_out_time)

	# 2. Deduct 60 seconds from the timer while blacked out
	var timers = get_tree().get_nodes_in_group("MainTimer")
	if timers.size() > 0 and timers[0].has_method("subtract_time"):
		timers[0].subtract_time(60.0)

	# 3. Blink awake with stepped PS1 transition
	await wake_up(hold_time, fade_in_time)


## Flash function for camera damage/entity attacks
func play_damage_flash(flash_color: Color = Color(1.0, 0.0, 0.0, 0.6), flash_duration: float = 0.15) -> void:
	if _is_playing:
		return
		
	_is_playing = true
	
	# Immediate abrupt flash
	fade_rect.color = flash_color
	
	# Stepped fade-out back to transparent
	await _tween_stepped_alpha(flash_color.a, 0.0, flash_duration, 3)
	
	fade_rect.color = Color(0, 0, 0, 0)
	_is_playing = false
