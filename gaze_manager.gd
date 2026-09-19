extends Node

# ============================================================
# AUTOLOAD SETUP:
# Project > Project Settings > Autoload > add this script,
# Node Name MUST be exactly GazeManager.
# ============================================================

signal look_away_resolved

@export var look_away_limit: float = 3.0
@export var decay_rate: float = 2.0

@export_group("Tint Controls")
@export var tint_delay: float = 0.1          # Delay in seconds before tint starts
@export var tint_max_alpha: float = 0.35      # Max opacity peak
@export var tint_power: float = 1.0         # Ramp exponent (>1 = starts faint, spikes near limit)
@export var tint_curve: Curve = null         # Optional: override with an Inspector Curve
@export var tint_steps: int = 6
@export var tint_step_interval: float = 0.06

@export_group("Warning Effects")
@export var shake_max_amount: float = 0.09
@export var warning_font: Font = null
@export var respawn_sound: AudioStream = null
@export var look_away_text: String = "LOOK AWAY"
@export var text_spawn_interval: float = 0.35

var watched_time: float = 0.0
var _watchers: Dictionary = {}
var _text_timer: float = 0.0
var _resolving: bool = false
var _tint_configured: bool = false

var _tint_step_timer: float = 0.0
var _current_tint_step: float = 0.0

var _tint_rect: ColorRect = null
var _warning_layer: Control = null
var _camera: Camera3D = null
var _audio_player: AudioStreamPlayer = null

var _shake_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_shake_rng.randomize()
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


func start_watching(source: Node) -> void:
	if is_instance_valid(source):
		_watchers[source] = true


func stop_watching(source: Node) -> void:
	_watchers.erase(source)


func get_gaze_progress() -> float:
	if look_away_limit <= 0.0:
		return 0.0
	return clamp(watched_time / look_away_limit, 0.0, 1.0)


func _process(delta: float) -> void:
	if _resolving:
		return

	_clean_invalid_watchers()
	_ensure_refs()

	if _watchers.size() > 0:
		watched_time = min(watched_time + delta, look_away_limit)
	else:
		watched_time = max(watched_time - delta * decay_rate, 0.0)

	var intensity: float = get_gaze_progress()

	_apply_shake(intensity)
	_apply_tint(intensity, delta)
	_process_warning_text(delta, intensity)

	if watched_time >= look_away_limit:
		_resolve_look_away()


func _clean_invalid_watchers() -> void:
	for source in _watchers.keys():
		if not is_instance_valid(source):
			_watchers.erase(source)


func _ensure_refs() -> void:
	if not is_instance_valid(_tint_rect):
		var rects := get_tree().get_nodes_in_group("GazeTintRect")
		_tint_rect = rects[0] if rects.size() > 0 else null
		_tint_configured = false

	if _tint_rect and not _tint_configured:
		_tint_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tint_configured = true

	if not is_instance_valid(_warning_layer):
		var layers := get_tree().get_nodes_in_group("GazeWarningLayer")
		_warning_layer = layers[0] if layers.size() > 0 else null

	if not is_instance_valid(_camera):
		var players := get_tree().get_nodes_in_group("PlayerGroup")
		if players.size() > 0:
			var player := players[0]
			if player.has_node("Head/Camera3D"):
				_camera = player.get_node("Head/Camera3D")
			else:
				_camera = get_viewport().get_camera_3d()


func _apply_shake(intensity: float) -> void:
	if not is_instance_valid(_camera):
		return

	if intensity <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return

	var punch: float = pow(intensity, 1.6)
	var amt: float = shake_max_amount * punch
	_camera.h_offset = _shake_rng.randf_range(-amt, amt)
	_camera.v_offset = _shake_rng.randf_range(-amt, amt)


func _apply_tint(intensity: float, delta: float) -> void:
	if not is_instance_valid(_tint_rect):
		return

	if watched_time < tint_delay or intensity <= 0.0:
		_tint_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		_tint_step_timer = 0.0
		return

	# Normalize progress specifically for active tint duration after delay
	var active_time: float = watched_time - tint_delay
	var active_limit: float = max(look_away_limit - tint_delay, 0.001)
	var ramp_progress: float = clamp(active_time / active_limit, 0.0, 1.0)

	# Calculate intensity via Curve resource or math power exponent
	var curved_intensity: float = 0.0
	if tint_curve:
		curved_intensity = tint_curve.sample(ramp_progress)
	else:
		curved_intensity = pow(ramp_progress, tint_power)

	_tint_step_timer += delta
	var interval: float = lerp(tint_step_interval, tint_step_interval * 0.3, curved_intensity)
	if _tint_step_timer >= interval:
		_tint_step_timer = 0.0
		var jitter: float = randf_range(-0.08, 0.08) * curved_intensity
		var raw: float = clamp(curved_intensity + jitter, 0.0, 1.0)
		_current_tint_step = snappedf(raw, 1.0 / float(tint_steps))

	var light_red := Color(1.0, 0.2, 0.2)
	_tint_rect.color = Color(light_red.r, light_red.g, light_red.b, tint_max_alpha * _current_tint_step)


func _process_warning_text(delta: float, intensity: float) -> void:
	if intensity <= 0.1 or not is_instance_valid(_warning_layer):
		_text_timer = 0.0
		return

	_text_timer += delta
	var interval: float = lerp(text_spawn_interval, text_spawn_interval * 0.25, intensity)
	if _text_timer >= interval:
		_text_timer = 0.0
		_spawn_warning_text(intensity)


func _spawn_warning_text(intensity: float) -> void:
	if not is_instance_valid(_warning_layer):
		return

	var label := Label.new()
	label.text = look_away_text
	if warning_font:
		label.add_theme_font_override("font", warning_font)
	label.add_theme_color_override("font_color", Color(1.0, 0.05, 0.05, 1.0))
	label.add_theme_font_size_override("font_size", int(lerp(20.0, 48.0, intensity)))
	label.z_index = 100
	label.rotation_degrees = randf_range(-12.0, 12.0)

	_warning_layer.add_child(label)

	var viewport_size: Vector2 = _warning_layer.get_viewport_rect().size
	label.position = Vector2(
		randf_range(0.0, max(viewport_size.x - 220.0, 0.0)),
		randf_range(0.0, max(viewport_size.y - 60.0, 0.0))
	)

	var original_text: String = look_away_text
	var tween := create_tween()

	tween.tween_callback(func():
		if is_instance_valid(label):
			label.text = _get_glitched_text(original_text)
			label.position += Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
			label.modulate.a = 1.0
	)
	tween.tween_interval(0.04)

	tween.tween_callback(func():
		if is_instance_valid(label):
			label.text = original_text
			label.modulate.a = 0.3 if randf() > 0.6 else 1.0
			label.position += Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	)
	tween.tween_interval(0.04)

	tween.tween_callback(func():
		if is_instance_valid(label):
			label.modulate.a = 1.0
	)
	tween.tween_interval(randf_range(0.1, 0.2))

	tween.tween_callback(func():
		if is_instance_valid(label):
			label.modulate.a = 0.0
	)
	tween.tween_interval(0.02)
	tween.tween_callback(label.queue_free)


func _get_glitched_text(text: String) -> String:
	var corrupt_chars := "@#$%&*!?X/\\|[]<>"
	var result := ""
	for i in range(text.length()):
		if randf() < 0.5:
			result += corrupt_chars[randi() % corrupt_chars.length()]
		else:
			result += text[i]
	return result


func _clear_warning_labels() -> void:
	if is_instance_valid(_warning_layer):
		for child in _warning_layer.get_children():
			child.queue_free()


func _resolve_look_away() -> void:
	_resolving = true
	_clear_warning_labels()

	var fades := get_tree().get_nodes_in_group("ScreenFade")
	if fades.size() > 0:
		await fades[0].fade_to_black()

	_reset_player_to_start()

	if respawn_sound and _audio_player:
		_audio_player.stream = respawn_sound
		_audio_player.play()

	if fades.size() > 0:
		await fades[0].wake_up()

	watched_time = 0.0
	_watchers.clear()
	_apply_shake(0.0)
	_apply_tint(0.0, 0.0)
	_resolving = false
	look_away_resolved.emit()


func _reset_player_to_start() -> void:
	var players := get_tree().get_nodes_in_group("PlayerGroup")
	var starts := get_tree().get_nodes_in_group("LevelStart")

	if players.size() == 0 or starts.size() == 0:
		return

	var player: Node3D = players[0]
	var start_marker: Node3D = starts[0]

	player.global_transform = start_marker.global_transform
	if "velocity" in player:
		player.velocity = Vector3.ZERO
