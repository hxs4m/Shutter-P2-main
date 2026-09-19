extends CharacterBody3D

# ============================================================
# STATES
# ============================================================
enum State { ROAM, SPOTTING, CHASE, SEARCH, STUNNED }
var current_state: State = State.ROAM

# ============================================================
# STUN STATE
# ============================================================
var stun_timer: float = 0.0
@export var stun_duration: float = 5.0

# ============================================================
# MOVEMENT & VISION
# ============================================================
@export var roam_speed: float = 8.0
@export var chase_speed: float = 14.0
@export var acceleration: float = 35.0
@export var friction: float = 4.0
@export var max_spotting_distance: float = 300.0
@export var time_until_roam: float = 5.0
@export var min_teleport_distance: float = 30.0

# --- Search State Settings ---
@export var search_duration: float = 6.0
@export var search_radius: float = 12.0
var search_timer: float = 0.0
var last_known_player_position: Vector3 = Vector3.ZERO

@export var max_nav_point_height: float = 400.0
@export var eye_height: float = 1.4
@export var target_height: float = 0.9
@export var debug_vision: bool = false

# How long (in seconds) the player must remain in line of sight before chase triggers
@export var spot_reaction_delay: float = 1.2

# ============================================================
# AUDIO
# ============================================================
@export_group("Audio")
@export var catch_sounds: Array[AudioStream] = []
@export var min_pitch: float = 0.85
@export var max_pitch: float = 1.15

# ============================================================
# AFTER-IMAGE
# ============================================================
@export_group("After Image Settings")
@export var trail_enabled: bool = true
@export var ghost_spawn_rate: float = 0.2
@export var ghost_lifetime: float = 1.5
@export var ghost_initial_alpha: float = 1.0

# ============================================================
# REFERENCES
# ============================================================
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var main_sprite: Sprite3D = $Sprite3D
@onready var vision_ray: RayCast3D = $VisionRay
@onready var catch_audio_player: AudioStreamPlayer = $CatchAudioPlayer

# ============================================================
# VARIABLES
# ============================================================
var player: Node3D = null
var time_since_player_seen: float = 0.0

# --- Spotting Timers ---
var spot_timer: float = 0.0
var spot_flicker_timer: float = 0.0
const SPOT_FLICKER_TOLERANCE := 0.3

var roam_target: Vector3
var ghost_timer: float = 0.0

# --- Catch Handling ---
var is_caught_sequence_playing: bool = false
const CATCH_DISTANCE := 1.5
const TIME_PENALTY := 60.0


func _ready() -> void:
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	if players.size() > 0:
		player = players[0]
		print("Enemy: Player found.")
	else:
		print("Enemy: ERROR - No player found in PlayerGroup.")

	vision_ray.enabled = true
	vision_ray.add_exception(self)

	# Configure NavigationAgent3D distances for tight path tracking
	nav_agent.path_desired_distance = 0.8
	nav_agent.target_desired_distance = 1.0

	await NavigationServer3D.map_changed
	_change_state(State.ROAM)


func _physics_process(delta: float) -> void:
	if player == null:
		return

	# Apply Gravity
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	# Process Current State Logic
	match current_state:
		State.STUNNED:
			_process_stun_state(delta)
		State.ROAM:
			_process_roam_state(delta)
		State.SPOTTING:
			_process_spotting_state(delta)
		State.CHASE:
			_process_chase_state(delta)
		State.SEARCH:
			_process_search_state(delta)

	# Nextbot Flat Orienting: Always face movement/target directly on Y-axis
	_face_target(player.global_position if current_state == State.CHASE else nav_agent.get_next_path_position())

	# After-Image Trail
	if current_state != State.STUNNED and trail_enabled and Vector3(velocity.x, 0, velocity.z).length() > 0.1:
		ghost_timer += delta
		if ghost_timer >= ghost_spawn_rate:
			spawn_ghost_image()
			ghost_timer = 0.0

	move_and_slide()


# ============================================================
# STATE PROCESSORS
# ============================================================
func _process_stun_state(delta: float) -> void:
	_apply_friction(delta)
	stun_timer += delta
	if stun_timer >= stun_duration:
		print("Enemy unstunned!")
		_change_state(State.ROAM)


func _process_roam_state(delta: float) -> void:
	if is_player_visible():
		_change_state(State.SPOTTING)
		return

	if nav_agent.is_navigation_finished():
		_choose_new_roam_target()

	_move_along_navigation(roam_speed, delta)


func _process_spotting_state(delta: float) -> void:
	_apply_friction(delta)

	if is_player_visible():
		spot_flicker_timer = 0.0
		spot_timer += delta
		if spot_timer >= spot_reaction_delay:
			_change_state(State.CHASE)
	else:
		spot_flicker_timer += delta
		if spot_flicker_timer >= SPOT_FLICKER_TOLERANCE:
			_change_state(State.ROAM)


func _process_chase_state(delta: float) -> void:
	var flat_enemy_pos := Vector2(global_position.x, global_position.z)
	var flat_player_pos := Vector2(player.global_position.x, player.global_position.z)

	# Catch Distance Check
	if flat_enemy_pos.distance_to(flat_player_pos) <= CATCH_DISTANCE:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_caught_sequence_playing:
			_trigger_catch()
		return

	if is_player_visible():
		time_since_player_seen = 0.0
		last_known_player_position = player.global_position
		nav_agent.target_position = last_known_player_position
	else:
		# Line of sight lost — enter search state to investigate last known location
		_change_state(State.SEARCH)
		return

	_move_along_navigation(chase_speed, delta)


func _process_search_state(delta: float) -> void:
	# If player walks back into view while searching, resume chase instantly
	if is_player_visible():
		_change_state(State.CHASE)
		return

	search_timer += delta
	if search_timer >= search_duration:
		print("Enemy: Search failed, resuming roam.")
		_change_state(State.ROAM)
		return

	# Search logic: move to last known spot, then check nearby nav points
	if nav_agent.is_navigation_finished():
		_choose_nearby_search_target()

	_move_along_navigation(roam_speed * 1.2, delta)


func _change_state(new_state: State) -> void:
	current_state = new_state

	match current_state:
		State.ROAM:
			_choose_new_roam_target()
		State.SPOTTING:
			spot_timer = 0.0
			spot_flicker_timer = 0.0
			print("Enemy: spotted player, reacting...")
		State.CHASE:
			time_since_player_seen = 0.0
			nav_agent.target_position = player.global_position
		State.SEARCH:
			search_timer = 0.0
			nav_agent.target_position = last_known_player_position
			print("Enemy: Lost visual, searching near last known position...")
		State.STUNNED:
			stun_timer = 0.0


# ============================================================
# MOVEMENT & NAVIGATION
# ============================================================
func _move_along_navigation(target_speed: float, delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_apply_friction(delta)
		return

	var next_path_position := nav_agent.get_next_path_position()
	var dir := (next_path_position - global_position)
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		
		# Prevent overshooting / breaking ankles
		var current_dir := Vector3(velocity.x, 0.0, velocity.z)
		if current_dir.length_squared() > 0.1:
			var alignment := current_dir.normalized().dot(dir)
			
			if alignment < 0.5:
				var brake_force := acceleration * 2.5 * delta
				velocity.x = move_toward(velocity.x, 0.0, brake_force)
				velocity.z = move_toward(velocity.z, 0.0, brake_force)

		# Accelerate toward target
		var target_vel := dir * target_speed
		velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)
	else:
		_apply_friction(delta)


func _apply_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * acceleration * delta)


func _face_target(target_pos: Vector3) -> void:
	var look_at_pos := target_pos
	look_at_pos.y = global_position.y
	if global_position.distance_squared_to(look_at_pos) > 0.001:
		look_at(look_at_pos, Vector3.UP)


func _choose_new_roam_target() -> void:
	var navigation_map := get_world_3d().get_navigation_map()
	if navigation_map == RID():
		return

	roam_target = _get_random_nav_point(navigation_map)
	nav_agent.target_position = roam_target


func _choose_nearby_search_target() -> void:
	var navigation_map := get_world_3d().get_navigation_map()
	if navigation_map == RID():
		return

	# Sample random navigation points near the last known position
	for i in range(10):
		var random_point := _get_random_nav_point(navigation_map)
		if random_point.distance_to(last_known_player_position) <= search_radius:
			nav_agent.target_position = random_point
			return

	# Fallback if no nearby point is found
	nav_agent.target_position = last_known_player_position


func _get_random_nav_point(navigation_map: RID) -> Vector3:
	const MAX_ATTEMPTS := 20
	var point := Vector3.ZERO

	for i in range(MAX_ATTEMPTS):
		point = NavigationServer3D.map_get_random_point(navigation_map, 1, false)
		if point.y <= max_nav_point_height:
			return point

	push_warning("Enemy: couldn't find a nav point below max_nav_point_height after %d tries — using last sample (y=%s)." % [MAX_ATTEMPTS, point.y])
	return point


# ============================================================
# VISION
# ============================================================
func is_player_visible() -> bool:
	if player == null:
		return false

	if global_position.distance_to(player.global_position) > max_spotting_distance:
		return false

	var eye_pos: Vector3 = global_position + Vector3.UP * eye_height
	var target_pos: Vector3 = player.global_position + Vector3.UP * target_height

	vision_ray.global_position = eye_pos
	vision_ray.target_position = vision_ray.to_local(target_pos)
	vision_ray.force_raycast_update()

	if not vision_ray.is_colliding():
		return true

	var collider = vision_ray.get_collider()
	if collider == player or (collider is Node and player.is_ancestor_of(collider)):
		return true

	if debug_vision:
		print("Enemy: vision blocked by ", collider)

	return false


# ============================================================
# UTILITY & CATCH SEQUENCE
# ============================================================
func spawn_ghost_image() -> void:
	var ghost: Sprite3D = Sprite3D.new()
	ghost.texture = main_sprite.texture
	ghost.billboard = main_sprite.billboard
	ghost.shaded = main_sprite.shaded
	ghost.alpha_cut = main_sprite.alpha_cut
	ghost.pixel_size = main_sprite.pixel_size

	get_parent().add_child(ghost)
	ghost.global_position = main_sprite.global_position
	ghost.global_transform.basis = main_sprite.global_transform.basis
	ghost.scale = main_sprite.scale
	ghost.modulate.a = ghost_initial_alpha

	var tween = create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, ghost_lifetime)
	tween.tween_callback(ghost.queue_free)


func apply_stun() -> void:
	_change_state(State.STUNNED)
	ScoreManager.enemies_stunned += 1
	print("Enemy blinded by camera!")


func _trigger_catch() -> void:
	is_caught_sequence_playing = true
	ScoreManager.times_caught += 1
	print("Enemy: player caught!")

	if catch_sounds.size() > 0 and catch_audio_player:
		var random_sound: AudioStream = catch_sounds.pick_random()
		if random_sound:
			catch_audio_player.stream = random_sound
			catch_audio_player.pitch_scale = randf_range(min_pitch, max_pitch)
			catch_audio_player.play()
			print("Enemy: Playing random catch sound with pitch ", catch_audio_player.pitch_scale)
	elif catch_audio_player and catch_audio_player.stream:
		catch_audio_player.pitch_scale = randf_range(min_pitch, max_pitch)
		catch_audio_player.play()

	var fades := get_tree().get_nodes_in_group("ScreenFade")
	var timers := get_tree().get_nodes_in_group("MainTimer")

	if fades.size() > 0:
		await fades[0].fade_to_black()
	else:
		push_warning("Enemy: no ScreenFade node found in group 'ScreenFade' — skipping blackout.")

	if timers.size() > 0:
		timers[0].subtract_time(TIME_PENALTY)
	else:
		push_warning("Enemy: no Main Timer found in group 'MainTimer' — time penalty skipped.")

	_teleport_away()

	if fades.size() > 0:
		await fades[0].wake_up()

	is_caught_sequence_playing = false


func _teleport_away() -> void:
	var navigation_map := get_world_3d().get_navigation_map()
	if navigation_map == RID():
		return

	var new_position: Vector3 = global_position
	const MAX_TELEPORT_ATTEMPTS := 30
	
	for i in range(MAX_TELEPORT_ATTEMPTS):
		new_position = _get_random_nav_point(navigation_map)
		if player == null or new_position.distance_to(player.global_position) >= min_teleport_distance:
			break

	global_position = new_position
	_change_state(State.ROAM)
