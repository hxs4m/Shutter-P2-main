extends Node
## Main Timer
## Retro Countdown GUI

# ---------------------------------------------------------------------------
# 1. Duration & Audio Settings
# ---------------------------------------------------------------------------
@export var total_duration: float = 301.0:
	set(value):
		total_duration = value
		if is_instance_valid(timer):
			timer.wait_time = max(0.001, total_duration)

@export var timeout_sound: AudioStream
@export var deduction_sound: AudioStream

# ---------------------------------------------------------------------------
# 2. Movement & FX Settings
# ---------------------------------------------------------------------------
@export var target_position: Vector2 = Vector2(0.0, 50.0)
@export var move_speed: float = 200.0
@export var glyph_spacing: int = 16
@export var flash_duration: float = 0.5
@export var deduction_delay: float = 0.5  # Delay in seconds before audio, flash, and deduction trigger
@export var glitch_intensity: float = 12.0  # Base shake multiplier for erratic timeout
@export var teleport_chance: float = 0.35  # Frequency of full screen jumps during timeout

# ---------------------------------------------------------------------------
# 3. Intro Text Settings
# ---------------------------------------------------------------------------
@export var show_intro_text: bool = true  # Toggle intro text on/off
@export var intro_text: String = "FIND THE DOOR"  # Customizable intro message
@export var hide_intro_text: bool = false  # Check this in the Inspector to force blank text on specific levels
@export var use_random_blank: bool = true  # Set to true to automatically calculate the 1/5 chance
@export_range(0.0, 1.0) var random_blank_chance: float = 0.20  # 0.20 = 20% (1/5) chance

@onready var time_display: RichTextLabel = $TimeDisplay
@onready var timer: Timer = $Timer

var audio_player: AudioStreamPlayer
var _last_built_second: int = -1
var _last_state: int = -1
var _is_finished: bool = false
var _is_frozen: bool = false

# --- Intro Sequence Trackers ---
var _intro_phase: int = 0
var _intro_timer: float = 0.0
var _intro_fade_duration: float = 1.0
var _intro_hold_duration: float = 2.0

# --- Deduction Flash Trackers ---
var _base_color: Color = Color(0.85, 0.90, 0.85, 1.0)
var _is_flashing: bool = false
var _flash_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not is_in_group('MainTimer'):
		add_to_group('MainTimer')

	# --- PERSISTENT TIMER CHECK ---
	# If time was saved from the previous level, override total_duration
	if ScoreManager and ScoreManager.get("saved_time") != null and ScoreManager.saved_time > 0.0:
		total_duration = ScoreManager.saved_time

	time_display.bbcode_enabled = true

	# --- Dynamic Audio Player Setup ---
	audio_player = AudioStreamPlayer.new()
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_player)

	# --- Centering & Initial Position ---
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	time_display.custom_minimum_size.x = viewport_width
	time_display.size.x = viewport_width
	time_display.position = Vector2(0.0, 50.0)

	time_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_display.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	time_display.add_theme_font_size_override('normal_font_size', 48)

	var base_font: Font = time_display.get_theme_font('normal_font')
	if base_font:
		var spaced_font := FontVariation.new()
		spaced_font.base_font = base_font
		spaced_font.spacing_glyph = glyph_spacing
		time_display.add_theme_font_override('normal_font', spaced_font)

	time_display.mouse_filter = Control.MOUSE_FILTER_IGNORE

	time_display.remove_theme_constant_override('outline_size')
	time_display.remove_theme_color_override('font_outline_color')

	time_display.add_theme_color_override('font_shadow_color', Color(0.2, 0.0, 0.0, 0.6))
	time_display.add_theme_constant_override('shadow_offset_x', 0)
	time_display.add_theme_constant_override('shadow_offset_y', 0)
	time_display.add_theme_constant_override('shadow_outline_size', 6)

	time_display.modulate.a = 0.0
	
	# Set the initial intro text
	time_display.text = '[center]%s[/center]' % _get_intro_text()

	timer.wait_time = max(0.001, total_duration)
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)

	# --- Connect Death Penalty Signal ---
	var gaze_mgr := get_node_or_null('/root/GazeManager')
	if gaze_mgr and gaze_mgr.has_signal('look_away_resolved'):
		if not gaze_mgr.look_away_resolved.is_connected(_on_player_death):
			gaze_mgr.look_away_resolved.connect(_on_player_death)


func save_time_for_next_level() -> void:
	if is_instance_valid(timer) and not timer.is_stopped():
		ScoreManager.saved_time = timer.time_left


func _get_intro_text() -> String:
	if not show_intro_text or hide_intro_text:
		return ""
	if use_random_blank and randf() < random_blank_chance:
		return ""
	return intro_text


func _process(delta: float) -> void:
	if _is_frozen or not is_instance_valid(time_display):
		return

	# --- Timeout Erratic Screen Glitch ---
	if _is_finished:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size

		if randf() < teleport_chance:
			time_display.position = Vector2(
				randf_range(-150.0, vp_size.x * 0.4),
				randf_range(20.0, vp_size.y - 120.0)
			)
		else:
			var shake := Vector2(
				randf_range(-glitch_intensity * 15.0, glitch_intensity * 15.0),
				randf_range(-glitch_intensity * 15.0, glitch_intensity * 15.0)
			)
			time_display.position = target_position + shake

		time_display.add_theme_constant_override('shadow_offset_x', randi_range(-20, 20))
		time_display.add_theme_constant_override('shadow_offset_y', randi_range(-20, 20))
		return

	# --- Phase 1: Intro Text Sequence ---
	if _intro_phase < 3:
		_process_intro_sequence(delta)
		return

	# --- Phase 2: Standard Movement ---
	if not _is_finished:
		time_display.position = Vector2(0.0, 50.0).move_toward(
			target_position,
			move_speed * delta
		)

	# --- Phase 3: Stepped Red Flash Recovery ---
	if _is_flashing:
		_flash_timer += delta
		var progress: float = clamp(_flash_timer / flash_duration, 0.0, 1.0)
		var stepped_progress: float = snappedf(progress, 0.25)
		var flash_color := Color(1.0, 0.0, 0.0, 1.0)
		
		time_display.self_modulate = flash_color.lerp(_base_color, stepped_progress)

		if progress >= 1.0:
			_is_flashing = false
			time_display.self_modulate = _base_color

	# --- Countdown Formatting ---
	if not timer.is_stopped() and not _is_finished:
		_update_display(timer.time_left)


func _process_intro_sequence(delta: float) -> void:
	_intro_timer += delta

	match _intro_phase:
		0:
			var progress: float = clamp(_intro_timer / _intro_fade_duration, 0.0, 1.0)
			time_display.modulate.a = progress
			if progress >= 1.0:
				_intro_phase = 1
				_intro_timer = 0.0

		1:
			time_display.modulate.a = 1.0
			if _intro_timer >= _intro_hold_duration:
				_intro_phase = 2
				_intro_timer = 0.0

		2:
			var progress: float = clamp(_intro_timer / _intro_fade_duration, 0.0, 1.0)
			time_display.modulate.a = 1.0 - progress
			if progress >= 1.0:
				_intro_phase = 3
				time_display.modulate.a = 1.0
				time_display.add_theme_font_size_override('normal_font_size', 34)
				timer.start()
				_update_display(timer.wait_time)


func _on_player_death() -> void:
	var screen_fade := get_node_or_null('/root/ScreenFade')
	var gaze_mgr := get_node_or_null('/root/GazeManager')

	if screen_fade:
		if screen_fade.has_signal('fade_in_completed'):
			await screen_fade.fade_in_completed
		elif screen_fade.has_signal('fade_completed'):
			await screen_fade.fade_completed
	elif gaze_mgr:
		if gaze_mgr.has_signal('gaze_overlay_finished'):
			await gaze_mgr.gaze_overlay_finished
		elif gaze_mgr.has_signal('fade_completed'):
			await gaze_mgr.fade_completed

	subtract_time(60.0)


func freeze_timer() -> void:
	_is_frozen = true
	if is_instance_valid(timer):
		timer.stop()


func hide_timer() -> void:
	_is_frozen = true
	if is_instance_valid(timer):
		timer.stop()
	if is_instance_valid(time_display):
		time_display.hide()


func _on_timer_timeout() -> void:
	if _is_finished or _is_frozen:
		return
	_is_finished = true

	get_tree().paused = true

	if is_instance_valid(time_display):
		time_display.self_modulate = Color(1.0, 0.1, 0.1, 1.0)
		time_display.add_theme_color_override('font_shadow_color', Color(0.5, 0.0, 0.0, 0.7))
		time_display.text = '[center]TOO LATE[/center]'

	if timeout_sound:
		audio_player.stream = timeout_sound
		audio_player.play()

	await get_tree().create_timer(3.0, true, false, true).timeout
	get_tree().quit()


func subtract_time(amount_seconds: float = 60.0) -> void:
	if timer.is_stopped() or _is_finished or _is_frozen:
		return

	if deduction_delay > 0.0:
		await get_tree().create_timer(deduction_delay, true, false, true).timeout

	_is_flashing = true
	_flash_timer = 0.0
	time_display.self_modulate = Color(1.0, 0.0, 0.0, 1.0)

	if deduction_sound:
		audio_player.stream = deduction_sound
		audio_player.play()

	var current_remaining: float = timer.time_left
	var new_time: float = max(0.0, current_remaining - amount_seconds)

	if new_time <= 0.0:
		timer.stop()
		_on_timer_timeout()
	else:
		timer.start(new_time)
		_update_display(new_time)


func add_time(amount_seconds: float) -> void:
	if timer.is_stopped() or _is_finished or _is_frozen:
		return

	var current_remaining: float = timer.time_left
	var new_time: float = current_remaining + amount_seconds
	timer.start(new_time)
	_update_display(new_time)


func _update_display(time_left: float) -> void:
	if _is_finished or _is_frozen or not is_instance_valid(time_display):
		return

	var clamped_time: float = max(0.0, time_left)

	var minutes: int = int(clamped_time) / 60
	var seconds: int = int(clamped_time) % 60
	var time_string: String = '%02d:%02d' % [minutes, seconds]

	var state: int
	if clamped_time > 30.0:
		state = 0
	elif clamped_time > 10.0:
		state = 1
	else:
		state = 2

	if state == 0:
		_base_color = Color(0.85, 0.90, 0.85, 1.0)
		time_display.add_theme_color_override('font_shadow_color', Color(0.1, 0.3, 0.1, 0.4))
	elif state == 1:
		var progress: float = (30.0 - clamped_time) / 20.0
		var stepped_p: float = snappedf(progress, 0.33)
		_base_color = Color(1.0, lerp(0.8, 0.3, stepped_p), 0.0, 1.0)
		time_display.add_theme_color_override('font_shadow_color', Color(0.4, 0.2, 0.0, 0.5))
	else:
		_base_color = Color(1.0, 0.1, 0.1, 1.0)
		time_display.add_theme_color_override('font_shadow_color', Color(0.5, 0.0, 0.0, 0.7))

	if not _is_flashing:
		time_display.self_modulate = _base_color

	var current_second: int = int(clamped_time)
	if state == _last_state and current_second == _last_built_second:
		return
	_last_state = state
	_last_built_second = current_second

	time_display.text = '[center]%s[/center]' % time_string


func reset_for_next_level() -> void:
	_is_finished = false
	_is_frozen = false
	_is_flashing = false
	_flash_timer = 0.0
	
	if is_instance_valid(time_display):
		time_display.show()
		time_display.modulate.a = 0.0
		time_display.self_modulate = Color(0.85, 0.90, 0.85, 1.0)
		time_display.add_theme_font_size_override('normal_font_size', 48)
		time_display.text = '[center]%s[/center]' % _get_intro_text()
		time_display.position = Vector2(0.0, 50.0)

	_intro_phase = 0
	_intro_timer = 0.0
	_last_built_second = -1
	_last_state = -1

	if is_instance_valid(timer):
		timer.stop()
		timer.wait_time = max(0.001, total_duration)
