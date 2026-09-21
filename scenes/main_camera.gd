extends Node3D

# --- LOOK INERTIA & SWAY ---
@export var SWAY_AMOUNT: float = 0.0015
@export var ROT_SWAY_AMOUNT: float = 0.05
@export var SWAY_SMOOTH: float = 10.0

# --- GMOD MOVEMENT BOB ---
@export var BOB_FREQ: float = 10.0
@export var BOB_AMP_X: float = 0.015
@export var BOB_AMP_Y: float = 0.012

# --- AIR / JUMP INERTIA ---
@export var JUMP_OFFSET: float = 0.03

# --- STRAFE ROLL ---
@export var STRAFE_ROLL_AMOUNT: float = 0.04
@export var ROLL_SPEED: float = 8.0

# --- CAMERA SNAPSHOT & COOLDOWN SETUP ---
@export var camera_viewport: SubViewport
@export var screen_mesh: MeshInstance3D
@export var fade_duration: float = 1.2
@export var fade_steps: int = 5
@export var snap_cooldown: float = 3.0

# --- FULL SCREEN FLASH ---
@export var flash_color_rect: ColorRect
@export var flash_tint_strength: float = 0.25

# --- CASTING & AUDIO SETUP ---
@export var enable_raycast: bool = true
@export var photo_shapecast: ShapeCast3D
@export var photo_raycast: RayCast3D
@export var capture_sound: AudioStream
@export var shutter_sound: AudioStream

# --- ZOOM / ADS ---
@export var crosshair: TextureRect
@export var zoom_action: String = "zoom"
@export var zoom_camera: Camera3D
@export var ZOOM_FOV: float = 35.0
@export var ZOOM_SPEED: float = 10.0
@export var zoom_sensitivity_mult: float = 0.5
@export var zoom_sound: AudioStream
@export var zoom_out_sound: AudioStream

# --- CAMERA MODES (STUN / REPEL / REVEAL) ---
enum CameraMode { STUN, REPEL, REVEAL }
@export var cycle_left_action: String = "cycle_left"
@export var cycle_right_action: String = "cycle_right"
@export var cycle_sound: AudioStream
@export var stun_light: MeshInstance3D
@export var repel_light: MeshInstance3D
@export var reveal_light: MeshInstance3D
@export var stun_color: Color = Color(1.0, 0.15, 0.1)
@export var repel_color: Color = Color(0.1, 0.5, 1.0)
@export var reveal_color: Color = Color(0.2, 1.0, 0.3)
@export var mode_off_brightness: float = 0.15
@export var mode_on_energy: float = 4.0
@export var mode_off_energy: float = 0.05

# --- MODE LABEL (PS1 STYLE STEPPED FADE) ---
@export var mode_label: Label
@export var mode_label_hold_time: float = 1.0
@export var mode_label_fade_duration: float = 0.6
@export var mode_label_fade_steps: int = 4

# --- REPEL EFFECT TUNING ---
@export var repel_hit_pitch: float = 1.0
@export var repel_perfect_pitch: float = 1.4
@export var repel_player_force: float = 10.0
@export var repel_player_vertical_force: float = 4.0
@export var repel_player_duration: float = 0.3

var current_mode: int = CameraMode.STUN
var _mode_lights: Array[MeshInstance3D] = []
var _mode_colors: Array[Color] = []
var _mode_materials: Array[StandardMaterial3D] = []

@onready var camera_sfx_player: AudioStreamPlayer = $CameraSFXPlayer
@onready var player: CharacterBody3D = get_tree().get_first_node_in_group("Player")

var default_pos: Vector3 = Vector3.ZERO
var mouse_delta: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var current_roll: float = 0.0
var fade_tween: Tween
var mode_label_tween: Tween
var can_snap: bool = true

var is_zoomed: bool = false
var _cached_sensitivity: float = 0.0

func _ready() -> void:
	default_pos = position
	_configure_screen_material()

	if camera_viewport:
		camera_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_set_screen_brightness(0.0)

	if not zoom_camera:
		zoom_camera = get_parent() as Camera3D

	if mode_label:
		mode_label.modulate.a = 0.0

	_mode_lights = [stun_light, repel_light, reveal_light]
	_mode_colors = [stun_color, repel_color, reveal_color]
	_setup_mode_lights()

func _configure_screen_material() -> void:
	if not screen_mesh:
		return

	var mat = _get_screen_material()
	if mat:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_delta = event.relative

	if event.is_action_pressed('snap'):
		take_snapshot()

	if event.is_action_pressed(zoom_action):
		_start_zoom()
	elif event.is_action_released(zoom_action):
		_stop_zoom()

	if event.is_action_pressed(cycle_right_action):
		_cycle_mode(-1)
	elif event.is_action_pressed(cycle_left_action):
		_cycle_mode(1)

func _setup_mode_lights() -> void:
	_mode_materials.clear()
	for light in _mode_lights:
		var mat: StandardMaterial3D = null
		if light:
			mat = light.get_surface_override_material(0) as StandardMaterial3D
			if not mat:
				mat = light.get_active_material(0) as StandardMaterial3D
			if mat:
				mat = mat.duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			mat.emission_enabled = true
			light.set_surface_override_material(0, mat)
		_mode_materials.append(mat)
	_update_mode_lights()

func _update_mode_lights() -> void:
	for i in _mode_materials.size():
		var mat = _mode_materials[i]
		if not mat:
			continue
		var base_color: Color = _mode_colors[i] if i < _mode_colors.size() else Color.WHITE
		var is_on: bool = i == current_mode
		mat.albedo_color = base_color if is_on else base_color * mode_off_brightness
		mat.emission = base_color
		mat.emission_energy_multiplier = mode_on_energy if is_on else mode_off_energy

func _cycle_mode(direction: int) -> void:
	var mode_count: int = _mode_lights.size()
	if mode_count == 0:
		return
	current_mode = (current_mode + direction + mode_count) % mode_count
	_update_mode_lights()
	_show_mode_label()
	if cycle_sound and camera_sfx_player:
		camera_sfx_player.stream = cycle_sound
		camera_sfx_player.pitch_scale = 1.0
		camera_sfx_player.play()

func _show_mode_label() -> void:
	if not mode_label:
		return

	var mode_color: Color = _mode_colors[current_mode] if current_mode < _mode_colors.size() else Color.WHITE
	mode_label.text = CameraMode.keys()[current_mode]
	mode_label.modulate = Color(mode_color.r, mode_color.g, mode_color.b, 1.0)

	if mode_label_tween and mode_label_tween.is_running():
		mode_label_tween.kill()

	mode_label_tween = create_tween()
	mode_label_tween.tween_interval(mode_label_hold_time)

	var step_delay: float = mode_label_fade_duration / float(mode_label_fade_steps)
	for i in range(mode_label_fade_steps, -1, -1):
		var target_alpha: float = float(i) / float(mode_label_fade_steps)
		mode_label_tween.tween_callback(func(): mode_label.modulate.a = target_alpha)
		mode_label_tween.tween_interval(step_delay)

func _start_zoom() -> void:
	is_zoomed = true
	if player:
		player.is_zoomed = true
		_cached_sensitivity = player.SENSITIVITY
		player.SENSITIVITY = _cached_sensitivity * zoom_sensitivity_mult
	_play_zoom_sfx(zoom_sound)

func _stop_zoom() -> void:
	is_zoomed = false
	if player:
		player.is_zoomed = false
		if _cached_sensitivity > 0.0:
			player.SENSITIVITY = _cached_sensitivity
	_play_zoom_sfx(zoom_out_sound)

func _play_zoom_sfx(sound_stream: AudioStream) -> void:
	if sound_stream and camera_sfx_player:
		camera_sfx_player.stream = sound_stream
		camera_sfx_player.pitch_scale = 1.0
		camera_sfx_player.play()

func take_snapshot() -> void:
	if not can_snap:
		return

	can_snap = false

	_play_shutter_sfx()
	_trigger_flash()

	if fade_tween and fade_tween.is_running():
		fade_tween.kill()

	_set_screen_brightness(1.0)

	if camera_viewport:
		camera_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	_start_stepped_fade()

	if is_zoomed and enable_raycast and photo_raycast:
		_check_raycast_hit()
	elif photo_shapecast:
		_check_shapecast_hit()

	get_tree().create_timer(snap_cooldown).timeout.connect(func(): can_snap = true)

func _check_shapecast_hit() -> void:
	photo_shapecast.force_shapecast_update()
	if not photo_shapecast.is_colliding():
		return

	var processed_objects: Array[Object] = []
	var capture_pitch: float = -1.0
	for i in photo_shapecast.get_collision_count():
		var hit_object = photo_shapecast.get_collider(i)
		if hit_object and not processed_objects.has(hit_object):
			processed_objects.append(hit_object)
			var pitch: float = _process_photo_hit(hit_object)
			if pitch >= 0.0 and capture_pitch < 0.0:
				capture_pitch = pitch
			if current_mode != CameraMode.REPEL and pitch >= 0.0:
				break

	if capture_pitch >= 0.0:
		_play_capture_sfx(capture_pitch)

func _check_raycast_hit() -> void:
	photo_raycast.force_raycast_update()
	if not photo_raycast.is_colliding():
		return

	var hit_object = photo_raycast.get_collider()
	var pitch: float = _process_photo_hit(hit_object)
	if pitch >= 0.0:
		_play_capture_sfx(pitch)

func _process_photo_hit(target: Object) -> float:
	if not target:
		return -1.0

	# --- SANCTUM CHECK ---
	# Sanctums are neutral: they're not stunned/repelled/revealed like the
	# Roamer/Abstract targets below. Any photo mode landing on one just
	# provokes it, so this branch short-circuits before the mode match.
	var sanctum_target: Object = target
	if not (sanctum_target is Node and sanctum_target.is_in_group("sanctums")):
		if target.get("owner") and target.owner is Node and target.owner.is_in_group("sanctums"):
			sanctum_target = target.owner

	if sanctum_target is Node and sanctum_target.is_in_group("sanctums"):
		if sanctum_target.has_method("apply_flash"):
			var from_pos: Vector3 = zoom_camera.global_transform.origin if zoom_camera else global_transform.origin
			return sanctum_target.apply_flash(from_pos)
		return -1.0

	# --- ABSTRACT CHECK ---
	# Abstracts are collectibles, so any camera mode captures them.
	# Short-circuits before the mode match, same as sanctums.
	var abstract_target: Object = target
	if not (abstract_target is Node and abstract_target.is_in_group("abstracts")):
		if target.get("owner") and target.owner is Node and target.owner.is_in_group("abstracts"):
			abstract_target = target.owner

	if abstract_target is Node and abstract_target.is_in_group("abstracts"):
		if abstract_target.has_method("disappear_from_photo"):
			return abstract_target.disappear_from_photo()
		return -1.0

	match current_mode:
		CameraMode.STUN:
			return _apply_stun(target)
		CameraMode.REPEL:
			return _apply_repel(target)
		CameraMode.REVEAL:
			return _apply_reveal(target)

	return -1.0

func _apply_stun(target: Object) -> float:
	if target.has_method("apply_stun"):
		target.apply_stun()
	elif target.get("owner") and target.owner.has_method("apply_stun"):
		target.owner.apply_stun()

	if target.has_method("disappear_from_photo"):
		return target.disappear_from_photo()
	elif target.get("owner") and target.owner.has_method("disappear_from_photo"):
		return target.owner.disappear_from_photo()

	return -1.0

func _apply_reveal(target: Object) -> float:
	if target.has_method("apply_reveal"):
		return target.apply_reveal()
	elif target.get("owner") and target.owner.has_method("apply_reveal"):
		return target.owner.apply_reveal()

	return -1.0

func _apply_repel(target: Object) -> float:
	var repel_target: Object = target
	if not repel_target.has_method("apply_repel") and repel_target.get("owner") and repel_target.owner.has_method("apply_repel"):
		repel_target = repel_target.owner

	if not repel_target.has_method("apply_repel"):
		return -1.0

	var from_pos: Vector3 = zoom_camera.global_transform.origin if zoom_camera else global_transform.origin
	var perfect: bool = repel_target.apply_repel(from_pos)

	if perfect and player:
		var push_dir: Vector3 = player.global_transform.origin - repel_target.global_transform.origin
		push_dir.y = 0.0
		if push_dir.length() > 0.001:
			push_dir = push_dir.normalized()
		player.apply_knockback(push_dir, repel_player_force, repel_player_vertical_force, repel_player_duration)

	return repel_perfect_pitch if perfect else repel_hit_pitch

func _play_shutter_sfx() -> void:
	if not shutter_sound:
		return

	var target_player: AudioStreamPlayer = player.camera_sfx_player if player and player.camera_sfx_player else camera_sfx_player
	if target_player:
		target_player.stream = shutter_sound
		target_player.pitch_scale = randf_range(0.95, 1.05)
		target_player.play()

func _play_capture_sfx(pitch: float) -> void:
	if camera_sfx_player and capture_sound:
		camera_sfx_player.stream = capture_sound
		camera_sfx_player.pitch_scale = pitch
		camera_sfx_player.play()

func _trigger_flash() -> void:
	if flash_color_rect:
		var mode_color: Color = _mode_colors[current_mode] if current_mode < _mode_colors.size() else Color.WHITE
		var tinted: Color = Color.WHITE.lerp(mode_color, flash_tint_strength)
		flash_color_rect.color = Color(tinted.r, tinted.g, tinted.b, 1.0)
		var duration: float = 0.18
		var steps: int = 3
		var step_delay: float = duration / float(steps)

		for i in range(steps, -1, -1):
			var raw_alpha: float = float(i) / float(steps)
			flash_color_rect.color.a = snappedf(raw_alpha, 0.33)
			await get_tree().create_timer(step_delay, true, false, true).timeout

		flash_color_rect.color.a = 0.0
	else:
		var screen_fades = get_tree().get_nodes_in_group("ScreenFade")
		if screen_fades.size() > 0 and screen_fades[0].has_method("play_damage_flash"):
			screen_fades[0].play_damage_flash(Color(1.0, 1.0, 1.0, 0.9), 0.15)

func _start_stepped_fade() -> void:
	fade_tween = create_tween()
	var step_delay: float = fade_duration / float(fade_steps)

	for i in range(fade_steps, -1, -1):
		var target_brightness: float = float(i) / float(fade_steps)
		fade_tween.tween_callback(func(): _set_screen_brightness(target_brightness))
		fade_tween.tween_interval(step_delay)

func _set_screen_brightness(val: float) -> void:
	var mat = _get_screen_material()
	if mat:
		mat.albedo_color = Color(val, val, val, 1.0)

func _get_screen_material() -> StandardMaterial3D:
	if not screen_mesh:
		return null

	var mat = screen_mesh.get_active_material(0) as StandardMaterial3D
	if not mat:
		mat = screen_mesh.get_surface_override_material(0) as StandardMaterial3D
	return mat

func _process(delta: float) -> void:
	if not player:
		player = get_parent().get_parent().get_parent() as CharacterBody3D
		return

	var target_sway_pos = Vector3(
		clamp(-mouse_delta.x * SWAY_AMOUNT, -0.05, 0.05),
		clamp(mouse_delta.y * SWAY_AMOUNT, -0.05, 0.05),
		0.0
	)

	var target_sway_rot = Vector3(
		clamp(-mouse_delta.y * ROT_SWAY_AMOUNT * 0.01, -0.2, 0.2),
		clamp(mouse_delta.x * ROT_SWAY_AMOUNT * 0.01, -0.2, 0.2),
		0.0
	)

	var horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var bob_offset = Vector3.ZERO

	if player.is_on_floor() and horizontal_speed > 0.5:
		bob_time += delta
		bob_offset.x = cos(bob_time * BOB_FREQ * 0.5) * BOB_AMP_X
		bob_offset.y = sin(bob_time * BOB_FREQ) * BOB_AMP_Y
	else:
		bob_time = 0.0

	var vertical_lag = 0.0
	if not player.is_on_floor():
		vertical_lag = clamp(-player.velocity.y * 0.003, -JUMP_OFFSET, JUMP_OFFSET)

	var input_dir_x = Input.get_axis("left", "right")
	var target_roll = -input_dir_x * STRAFE_ROLL_AMOUNT
	current_roll = lerp_angle(current_roll, target_roll, delta * ROLL_SPEED)

	var final_target_pos = default_pos + target_sway_pos + bob_offset + Vector3(0, vertical_lag, 0)

	position = position.lerp(final_target_pos, delta * SWAY_SMOOTH)
	rotation.x = lerp_angle(rotation.x, target_sway_rot.x, delta * SWAY_SMOOTH)
	rotation.y = lerp_angle(rotation.y, target_sway_rot.y, delta * SWAY_SMOOTH)
	rotation.z = current_roll

	mouse_delta = mouse_delta.lerp(Vector2.ZERO, delta * 12.0)

	if zoom_camera and is_zoomed:
		zoom_camera.fov = lerp(zoom_camera.fov, ZOOM_FOV, delta * ZOOM_SPEED)

	if crosshair:
		var target_rot: float = 45.0 if is_zoomed else 0.0
		crosshair.rotation_degrees = lerp(crosshair.rotation_degrees, target_rot, delta * ZOOM_SPEED)
