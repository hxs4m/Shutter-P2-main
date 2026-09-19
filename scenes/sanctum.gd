extends CharacterBody3D

enum State { ROAM, CONTACT_FOLLOW }
var current_state: State = State.ROAM

# --- FLIGHT / ROAM ---
@export var roam_speed: float = 6.0
@export var follow_speed: float = 14.0
@export var acceleration: float = 12.0
@export var vertical_acceleration: float = 8.0
@export var roam_radius: float = 150.0
@export var min_altitude: float = 15.0
@export var max_altitude: float = 45.0
@export var ground_check_ray_length: float = 200.0
@export var new_target_interval: float = 8.0
var _roam_timer: float = 0.0
var roam_target: Vector3 = Vector3.ZERO
var home_position: Vector3 = Vector3.ZERO

# --- PLAYER DISTANCE & CONTACT ---
@export_group("Player Interaction")
@export var contact_distance: float = 2.0
@export var min_player_distance: float = 30.0
@export var close_flyby_chance: float = 0.25
@export var close_flyby_distance: float = 12.0

# --- BOUNDARY GUARDIAN MODE ---
@export_group("Boundary Guardian")
@export var is_boundary_guardian: bool = false
@export var boundary_center: Node3D
@export var boundary_radius: float = 500.0
@export var guardian_fade_duration: float = 1.5
@export var guardian_fade_steps: int = 5
var _guardian_active: bool = false
var _fade_tween: Tween = null

# --- GAZE DETECTION & AUDIO ---
@export_group("Gaze Detection")
@export var look_ray_length: float = 150.0
@export var gaze_angle_degrees: float = 14.0
@export var gaze_check_interval: float = 0.1
@export var gaze_start_sound: AudioStream
@export var gaze_too_long_sound: AudioStream
@export var sfx_fade_duration: float = 0.25
@export var target_muffle_bus: String = "Master"
@export var muffled_cutoff_hz: float = 600.0
var _gaze_check_timer: float = 0.0
var _is_being_watched: bool = false
var _is_on_screen: bool = true

# --- CAMERA SHAKE ---
@export_group("Camera Shake")
@export var shake_intensity: float = 0.08
@export var shake_speed: float = 25.0
var _shake_time: float = 0.0

# --- DEATH & RESPAWN ---
@export_group("Death & Respawn")
@export var player_death_sound: AudioStream
@export var player_respawn_sound: AudioStream

# --- AUDIO FILTER TRACKING ---
var _lpf_effect: AudioEffectLowPassFilter = null
var _lpf_bus_idx: int = 0
var _lpf_effect_idx: int = -1
var _muffle_tween: Tween = null
var _audio_tween: Tween = null

# --- PROVOKE ---
@export_group("Provoke")
@export var provoke_cooldown: float = 0.5
var _provoke_locked: bool = false

# --- REFERENCES ---
@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var visual_notifier: VisibleOnScreenNotifier3D = $VisualNotifier

var player: Node3D = null
var player_camera: Camera3D = null
var _audio_player: AudioStreamPlayer = null


func _ready() -> void:
	add_to_group("sanctums")

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	_setup_muffle_filter()

	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		player = players[0]
		if player.has_node("Head/Camera3D"):
			player_camera = player.get_node("Head/Camera3D")

		if player.has_signal("died"):
			player.died.connect(play_player_death_sound)
		if player.has_signal("respawned"):
			player.respawned.connect(play_player_respawn_sound)

	home_position = global_position

	visual_notifier.screen_entered.connect(func(): _is_on_screen = true)
	visual_notifier.screen_exited.connect(func(): _is_on_screen = false)
	_is_on_screen = visual_notifier.is_on_screen()

	_offset_animation()

	if is_boundary_guardian:
		_set_guardian_dormant()
	else:
		_choose_new_roam_target()

	if not GazeManager.look_away_resolved.is_connected(_on_look_away_resolved):
		GazeManager.look_away_resolved.connect(_on_look_away_resolved)


func _exit_tree() -> void:
	if _is_being_watched:
		_stop_sfx(0.0)
		_set_muffled(false)
		_reset_camera_shake()
		get_tree().call_group("GazeOverlay", "stop_gaze_flash")
		GazeManager.stop_watching(self)


func _physics_process(delta: float) -> void:
	if player == null or player_camera == null:
		return

	if is_boundary_guardian:
		var center_pos: Vector3 = boundary_center.global_position if boundary_center else home_position
		var outside_boundary: bool = player.global_position.distance_to(center_pos) >= boundary_radius

		if outside_boundary and not _guardian_active:
			_activate_guardian()
		elif not outside_boundary and _guardian_active:
			_deactivate_guardian()

		if not _guardian_active and (sprite == null or sprite.modulate.a <= 0.0):
			return

	var dist_to_player: float = global_position.distance_to(player.global_position)
	if dist_to_player <= contact_distance:
		current_state = State.CONTACT_FOLLOW
		_fly_toward(player.global_position, follow_speed, delta)
	else:
		current_state = State.ROAM
		_process_roam(delta)

	if _is_on_screen:
		_process_gaze_check(delta)
	elif _is_being_watched:
		_is_being_watched = false
		_stop_sfx()
		_set_muffled(false)
		_reset_camera_shake()
		get_tree().call_group("GazeOverlay", "stop_gaze_flash")
		GazeManager.stop_watching(self)

	_process_camera_shake(delta)
	move_and_slide()


func _offset_animation() -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(sprite.animation):
		var total_frames: int = sprite.sprite_frames.get_frame_count(sprite.animation)
		if total_frames > 0:
			sprite.frame = randi() % total_frames
			sprite.frame_progress = randf()
		sprite.speed_scale = randf_range(0.85, 1.15)


# ============================================================
# ROAM MOVEMENT
# ============================================================
func _process_roam(delta: float) -> void:
	_roam_timer += delta
	if _roam_timer >= new_target_interval or global_position.distance_to(roam_target) < 3.0:
		_choose_new_roam_target()

	_fly_toward(roam_target, roam_speed, delta)


func _fly_toward(target: Vector3, target_speed: float, delta: float) -> void:
	var to_target: Vector3 = target - global_position
	if to_target.length() < 0.01:
		return
	var dir: Vector3 = to_target.normalized()
	var target_vel: Vector3 = dir * target_speed
	velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
	velocity.y = move_toward(velocity.y, target_vel.y, vertical_acceleration * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)


func _choose_new_roam_target() -> void:
	_roam_timer = 0.0

	var is_close_pass: bool = randf() < close_flyby_chance
	var random_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	if random_dir.length_squared() < 0.01:
		random_dir = Vector3.FORWARD

	var target_center: Vector3
	if is_close_pass and player:
		target_center = player.global_position + random_dir * close_flyby_distance
	else:
		if player and global_position.distance_to(player.global_position) < min_player_distance:
			target_center = player.global_position + random_dir * min_player_distance
		else:
			target_center = home_position + random_dir * randf_range(roam_radius * 0.2, roam_radius)

	var probe_origin: Vector3 = target_center + Vector3.UP * (ground_check_ray_length * 0.5)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		probe_origin,
		probe_origin + Vector3.DOWN * ground_check_ray_length
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	var ground_y: float = home_position.y
	if result:
		ground_y = result.position.y

	roam_target = Vector3(
		probe_origin.x,
		ground_y + randf_range(min_altitude, max_altitude),
		probe_origin.z
	)


# ============================================================
# GAZE DETECTION & MUFFLE FILTER
# ============================================================
func _process_gaze_check(delta: float) -> void:
	_gaze_check_timer += delta
	if _gaze_check_timer < gaze_check_interval:
		return
	_gaze_check_timer = 0.0

	var looking: bool = _is_player_looking_at_this()

	if looking and not _is_being_watched:
		_is_being_watched = true
		_play_sfx(gaze_start_sound)
		_set_muffled(true)
		get_tree().call_group("GazeOverlay", "start_gaze_flash")
		GazeManager.start_watching(self)
	elif not looking and _is_being_watched:
		_is_being_watched = false
		_stop_sfx()
		_set_muffled(false)
		_reset_camera_shake()
		get_tree().call_group("GazeOverlay", "stop_gaze_flash")
		GazeManager.stop_watching(self)


func _is_player_looking_at_this() -> bool:
	if player == null or not player.has_node("Head/Camera3D/RayCast3D"):
		return false
	var ray: RayCast3D = player.get_node("Head/Camera3D/RayCast3D")
	if not ray.is_colliding():
		return false

	var hit: Object = ray.get_collider()
	return hit == self or (hit is Node and self.is_ancestor_of(hit))


func _setup_muffle_filter() -> void:
	_lpf_bus_idx = AudioServer.get_bus_index(target_muffle_bus)
	if _lpf_bus_idx == -1:
		_lpf_bus_idx = 0

	for i in range(AudioServer.get_bus_effect_count(_lpf_bus_idx)):
		var eff = AudioServer.get_bus_effect(_lpf_bus_idx, i)
		if eff is AudioEffectLowPassFilter:
			_lpf_effect = eff
			_lpf_effect_idx = i
			break

	if _lpf_effect == null:
		_lpf_effect = AudioEffectLowPassFilter.new()
		_lpf_effect.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(_lpf_bus_idx, _lpf_effect)
		_lpf_effect_idx = AudioServer.get_bus_effect_count(_lpf_bus_idx) - 1

	AudioServer.set_bus_effect_enabled(_lpf_bus_idx, _lpf_effect_idx, false)


func _set_muffled(muffled: bool) -> void:
	if _lpf_effect == null:
		return

	if _muffle_tween and _muffle_tween.is_running():
		_muffle_tween.kill()

	_muffle_tween = create_tween()
	if muffled:
		AudioServer.set_bus_effect_enabled(_lpf_bus_idx, _lpf_effect_idx, true)
		_muffle_tween.tween_property(_lpf_effect, "cutoff_hz", muffled_cutoff_hz, 0.3)
	else:
		_muffle_tween.tween_property(_lpf_effect, "cutoff_hz", 20000.0, 0.3)
		_muffle_tween.tween_callback(func():
			AudioServer.set_bus_effect_enabled(_lpf_bus_idx, _lpf_effect_idx, false)
		)


# ============================================================
# CAMERA SHAKE
# ============================================================
func _process_camera_shake(delta: float) -> void:
	if player_camera == null:
		return

	if _is_being_watched:
		_shake_time += delta * shake_speed
		player_camera.h_offset = sin(_shake_time * 1.1) * shake_intensity
		player_camera.v_offset = cos(_shake_time * 1.3) * shake_intensity
	else:
		if abs(player_camera.h_offset) > 0.001 or abs(player_camera.v_offset) > 0.001:
			player_camera.h_offset = move_toward(player_camera.h_offset, 0.0, delta * 2.0)
			player_camera.v_offset = move_toward(player_camera.v_offset, 0.0, delta * 2.0)
		else:
			_reset_camera_shake()


func _reset_camera_shake() -> void:
	if player_camera:
		player_camera.h_offset = 0.0
		player_camera.v_offset = 0.0
	_shake_time = 0.0


# ============================================================
# DEATH & RESPAWN HANDLERS
# ============================================================
func play_player_death_sound() -> void:
	_play_one_shot_sfx(player_death_sound)


func play_player_respawn_sound() -> void:
	_play_one_shot_sfx(player_respawn_sound)


func _execute_respawn_sequence() -> void:
	if player and player.has_method("respawn"):
		player.respawn()
	_play_one_shot_sfx(player_respawn_sound)


# ============================================================
# PROVOKE
# ============================================================
func apply_flash(_from_pos: Vector3) -> float:
	if _provoke_locked:
		return -1.0
	_provoke_locked = true
	get_tree().create_timer(provoke_cooldown).timeout.connect(func(): _provoke_locked = false)
	return -1.0


func _on_look_away_resolved() -> void:
	if _is_being_watched:
		_stop_sfx()
		_is_being_watched = false
		_set_muffled(false)
		_reset_camera_shake()

		_play_one_shot_sfx(gaze_too_long_sound)
		_play_one_shot_sfx(player_death_sound)

		get_tree().call_group("MainTimer", "subtract_time", 60.0)

		get_tree().call_group(
			"GazeOverlay",
			"trigger_full_red_stepped_fade",
			Callable(self, "_execute_respawn_sequence")
		)

	_choose_new_roam_target()


# ============================================================
# BOUNDARY GUARDIAN ACTIVATION / DEACTIVATION
# ============================================================
func _set_guardian_dormant() -> void:
	if sprite:
		sprite.modulate.a = 0.0
	_guardian_active = false


func _activate_guardian() -> void:
	_guardian_active = true
	_choose_new_roam_target()

	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()

	_fade_tween = create_tween()
	for i in range(1, guardian_fade_steps + 1):
		var alpha: float = float(i) / float(guardian_fade_steps)
		_fade_tween.tween_callback(func(): if sprite: sprite.modulate.a = alpha)
		_fade_tween.tween_interval(guardian_fade_duration / float(guardian_fade_steps))


func _deactivate_guardian() -> void:
	_guardian_active = false

	if _is_being_watched:
		_is_being_watched = false
		_stop_sfx()
		_set_muffled(false)
		_reset_camera_shake()
		get_tree().call_group("GazeOverlay", "stop_gaze_flash")
		GazeManager.stop_watching(self)

	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()

	_fade_tween = create_tween()
	for i in range(guardian_fade_steps - 1, -1, -1):
		var alpha: float = float(i) / float(guardian_fade_steps)
		_fade_tween.tween_callback(func(): if sprite: sprite.modulate.a = alpha)
		_fade_tween.tween_interval(guardian_fade_duration / float(guardian_fade_steps))

	_fade_tween.tween_callback(func(): velocity = Vector3.ZERO)


# ============================================================
# AUDIO
# ============================================================
func _play_sfx(stream: AudioStream, fade_time: float = -1.0) -> void:
	if stream == null or _audio_player == null:
		return

	var duration: float = sfx_fade_duration if fade_time < 0.0 else fade_time

	if _audio_tween and _audio_tween.is_running():
		_audio_tween.kill()

	_audio_player.stream = stream

	if duration <= 0.0:
		_audio_player.volume_db = 0.0
		_audio_player.play()
		return

	_audio_player.volume_db = -80.0
	_audio_player.play()

	_audio_tween = create_tween()
	_audio_tween.tween_property(_audio_player, "volume_db", 0.0, duration)


func _stop_sfx(fade_time: float = -1.0) -> void:
	if _audio_player == null or not _audio_player.playing:
		return

	var duration: float = sfx_fade_duration if fade_time < 0.0 else fade_time

	if _audio_tween and _audio_tween.is_running():
		_audio_tween.kill()

	if duration <= 0.0:
		_audio_player.stop()
		_audio_player.volume_db = 0.0
		return

	_audio_tween = create_tween()
	_audio_tween.tween_property(_audio_player, "volume_db", -80.0, duration)
	_audio_tween.tween_callback(func():
		if _audio_player:
			_audio_player.stop()
			_audio_player.volume_db = 0.0
	)


func _play_one_shot_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var asp := AudioStreamPlayer.new()
	asp.stream = stream
	asp.bus = "Master"
	add_child(asp)
	asp.finished.connect(asp.queue_free)
	asp.play()
