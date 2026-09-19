extends CharacterBody3D

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var playback = anim_tree.get("parameters/playback")
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D 
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio
@onready var sfx_audio: AudioStreamPlayer3D = $SFXAudio

@export_group("Movement Settings")
@export var speed: float = 8.0
@export var attack_radius: float = 3.5  
@export var hit_distance_threshold: float = 4.0
@export var attack_duration: float = 0.8 # Match your lunge animation length
@export var knockback_force: float = 35.0 
@export var knockback_upward_force: float = 6.0 

@export_group("Audio Streams")
@export var footstep_sounds: Array[AudioStream] = []
@export var lunge_jump_sound: AudioStream
@export var parry_success_sound: AudioStream
@export var parry_fail_sound: AudioStream
@export var teleport_sound: AudioStream

@export_group("Footstep Tuning")
@export var step_distance: float = 2.2

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var player: CharacterBody3D
var spawn_position: Vector3
var step_cycle_distance: float = 0.0
var attack_timer: float = 0.0

var is_attacking: bool = false
var is_knocked_back: bool = false
var parry_window_open: bool = false

signal lunge_started(roamer_node)
signal parry_window_closed(success)

func _ready() -> void:
	add_to_group("roamers") 
	spawn_position = global_position
	player = get_tree().get_first_node_in_group("Player")

func _physics_process(delta: float) -> void:
	# 1. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Dynamic Player Fetch
	if not player:
		player = get_tree().get_first_node_in_group("Player")
		if not player:
			return 

	var dist_to_player = global_position.distance_to(player.global_position)

	# 3. Trigger Lunge Attack
	if not is_attacking and not is_knocked_back and dist_to_player <= attack_radius:
		_start_lunge_attack()

	# 4. Knockback State (Unsuccessful Attack via Parry)
	if is_knocked_back:
		velocity.x = lerp(velocity.x, 0.0, delta * 4.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 4.0)
		
		var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
		if is_on_floor() and horizontal_speed < 1.0:
			is_knocked_back = false
			playback.start("run")

	# 5. Recovery Timer (Unsuccessful Attack via Miss/Dodge)
	elif is_attacking:
		velocity.x = lerp(velocity.x, 0.0, delta * 3.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 3.0)
		
		attack_timer -= delta
		if attack_timer <= 0.0:
			is_attacking = false
			parry_window_open = false
			playback.start("run")

	# 6. Navigation Chase
	else:
		nav_agent.target_position = player.global_position
		
		var look_pos = player.global_position
		look_pos.y = global_position.y
		if dist_to_player > 0.1:
			look_at(look_pos, Vector3.UP)
		
		var next_path_pos = nav_agent.get_next_path_position()
		var direction = global_position.direction_to(next_path_pos)
		direction.y = 0
		direction = direction.normalized()
		
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		_process_footsteps(delta)

	move_and_slide()

# --- FOOTSTEP AUDIO ---
func _process_footsteps(delta: float) -> void:
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	
	if is_on_floor() and horizontal_speed > 0.5:
		step_cycle_distance += horizontal_speed * delta
		if step_cycle_distance >= step_distance:
			step_cycle_distance = 0.0
			_play_random_footstep()

func _play_random_footstep() -> void:
	if footstep_sounds.size() > 0:
		var random_index = randi() % footstep_sounds.size()
		footstep_audio.stream = footstep_sounds[random_index]
		footstep_audio.pitch_scale = randf_range(0.9, 1.1)
		footstep_audio.play()

func _play_sfx(stream: AudioStream) -> void:
	if stream:
		sfx_audio.stream = stream
		sfx_audio.pitch_scale = 1.0
		sfx_audio.play()

# --- ATTACK LOGIC ---
func _start_lunge_attack() -> void:
	is_attacking = true
	parry_window_open = false
	attack_timer = attack_duration
	playback.travel("attack")
	
	_play_sfx(lunge_jump_sound)
	emit_signal("lunge_started", self)
	
	var lunge_dir = (player.global_position - global_position).normalized()
	velocity.x = lunge_dir.x * 18.0 
	velocity.z = lunge_dir.z * 18.0

func _teleport_to_random_location() -> void:
	var nav_map = nav_agent.get_navigation_map()
	var random_point = NavigationServer3D.map_get_random_point(nav_map, 1, true)
	
	if random_point != Vector3.ZERO:
		global_position = random_point
	else:
		global_position = spawn_position
		
	velocity = Vector3.ZERO
	is_attacking = false
	is_knocked_back = false
	parry_window_open = false
	playback.start("run")

# --- ANIMATION TRACK METHODS ---
func open_parry_window() -> void:
	parry_window_open = true

func close_parry_window() -> void:
	if parry_window_open:
		parry_window_open = false
		
		var dist_to_player = global_position.distance_to(player.global_position) if player else 999.0
		
		if dist_to_player <= hit_distance_threshold:
			# --- SUCCESSFUL ATTACK (HIT) ---
			_play_sfx(parry_fail_sound)
			
			# 1. Deduct 30 seconds from MainTimer
			var main_timer = get_tree().get_first_node_in_group("MainTimer")
			if main_timer and main_timer.has_method("subtract_time"):
				main_timer.subtract_time(30.0)
			
			# 2. Trigger black screen overlay
			if player and player.has_method("trigger_hit_overlay"):
				player.trigger_hit_overlay()
				
			# 3. Teleport & play SFX
			_teleport_to_random_location()
			_play_sfx(teleport_sound)
			
			emit_signal("parry_window_closed", false)
		else:
			# --- UNSUCCESSFUL ATTACK (MISSED / DODGED) ---
			emit_signal("parry_window_closed", false)

# --- CAMERA REPEL / PARRY ---
func apply_repel(from_pos: Vector3) -> bool:
	if parry_window_open:
		# --- UNSUCCESSFUL ATTACK (PARRIED) ---
		parry_window_open = false
		is_attacking = false
		is_knocked_back = true
		
		_play_sfx(parry_success_sound)
		
		var push_dir = (global_position - from_pos).normalized()
		push_dir.y = 0.0
		push_dir = push_dir.normalized()
		
		velocity.x = push_dir.x * knockback_force
		velocity.z = push_dir.z * knockback_force
		velocity.y = knockback_upward_force
		
		emit_signal("parry_window_closed", true)
		return true 
		
	return false
