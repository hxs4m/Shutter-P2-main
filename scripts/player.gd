extends CharacterBody3D

# --- STAMINA VARIABLES ---
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 100.0
@export var stamina_regen_delay: float = 0.0
var current_stamina: float = max_stamina
var stamina_cooldown: float = 0.0

# --- MOVEMENT EXPORTS ---
@export var WALK_SPEED: float = 5.0
@export var SPRINT_SPEED: float = 16.0
@export var JUMP_VELOCITY: float = 4.8
@export var SENSITIVITY: float = 0.004
@export var gravity: float = 11.8
var speed: float

# --- BHOP / MOMENTUM VARIABLES ---
@export var MAX_BHOP_SPEED: float = 26.0
@export var BHOP_WINDOW: float = 0.15
var bhop_count: int = 0
var floor_time: float = 0.0
var current_max_speed: float = SPRINT_SPEED

# --- HEAD BOB, ROLL & IMPACT ROTATION VARIABLES ---
@export var BOB_FREQ = 1.8
@export var BOB_AMP = 0.08
@export var BOB_SMOOTH: float = 14.0
@export var LAND_ROT_AMOUNT = 0.05
@export var WALL_ROT_AMOUNT = 0.04
@export var IMPACT_RECOVERY = 10.0
@export var STRAFE_ROLL_AMOUNT: float = 0.03
@export var ROLL_SPEED: float = 8.0

var bob_phase: float = 0.0
var target_impact_pitch: float = 0.0
var current_impact_pitch: float = 0.0
var camera_base_pitch: float = 0.0
var target_roll: float = 0.0
var current_roll: float = 0.0

@export var BASE_FOV = 75.0
@export var FOV_CHANGE = 1.5

# --- ZOOM / ADS / REPEL ---
var is_zoomed: bool = false
var is_repel_mode_active: bool = true 
var locked_enemy: Node3D = null

# --- KNOCKBACK ---
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_timer: float = 0.0
var knockback_duration: float = 0.0

# --- AUDIO ARRAYS & EXPORTS ---
@export var walk_sounds: Array[AudioStream] = []
@export var jump_sounds: Array[AudioStream] = []
@export var land_sounds: Array[AudioStream] = []
@export var wall_hit_sounds: Array[AudioStream] = []
@export var camera_snap_sound: AudioStream

# --- UI EXPORTS ---
@export var flash_color_rect: ColorRect
@onready var hit_overlay: ColorRect = $CanvasLayer/HitOverlay

# --- CAMERA LOWER ---
@export var CAMERA_LOWER_OFFSET: float = 0.8   # how far the camera model drops (local units)
@export var CAMERA_LOWER_TIME: float = 0.6

var camera_lowered: bool = false
var camera_toggled_once: bool = false
var lower_parts: Array[Node3D] = []             # visual parts of Main_Camera that get lowered
var lower_part_rest: Dictionary = {}            # part -> rest position
var camera_tween: Tween

# --- INPUT BLOCKING WHILE LOWERED ---
@export var zoom_actions: Array[StringName] = []
@export var always_allowed_actions: Array[StringName] = [
	&"left", &"right", &"up", &"down", &"sprint", &"jump", &"toggle_camera"
]
var saved_action_events: Dictionary = {}

# --- MOUSE BUTTON BLOCKING WHILE LOWERED ---
@export var block_left_click_while_lowered: bool = true    # Flash / Snap Picture
@export var block_right_click_while_lowered: bool = true   # Zoom

# --- CAMERA SNAP COOLDOWN & CAST SETTINGS ---
@export var enable_raycast: bool = true
var can_snap: bool = true
const SNAP_COOLDOWN: float = 3.0

# --- AUDIO TRACKERS & SETTINGS ---
var step_interval: float = 0.4
var step_timer: float = 0.0
var was_in_air: bool = false
var was_on_wall: bool = false

# --- NODES ---
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var camera_model: Node3D = $Head/Camera3D/Main_Camera
@onready var camera_ray: RayCast3D = $Head/Camera3D/RayCast3D
@onready var camera_shapecast: ShapeCast3D = $Head/Camera3D/ShapeCast3D
@onready var viewmodel_camera = get_node_or_null('SubViewportContainer/SubViewport/ViewmodelCamera')
@onready var sfx_player: AudioStreamPlayer3D = $SFXPlayer
@onready var impact_player: AudioStreamPlayer3D = $ImpactPlayer
@onready var camera_sfx_player: AudioStreamPlayer = $CameraSFXPlayer
@onready var stamina_bar: ProgressBar = get_parent().get_node_or_null('UI/StaminaBar')


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	add_to_group("PlayerGroup")
	add_to_group("Player")

	if camera_ray:
		camera_ray.target_position = Vector3(0, 0, -150.0)

	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina
		
	if flash_color_rect:
		flash_color_rect.color.a = 0.0
		flash_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not InputMap.has_action('toggle_camera'):
		InputMap.add_action('toggle_camera')
		var c_key := InputEventKey.new()
		c_key.physical_keycode = KEY_C
		InputMap.action_add_event('toggle_camera', c_key)

	if camera_model:
		for child in camera_model.get_children():
			var part := child as Node3D
			if part:
				lower_parts.append(part)
				lower_part_rest[part] = part.position


# --- CAMERA TOGGLE (C) ---
func toggle_camera() -> void:
	camera_toggled_once = true
	if camera_lowered:
		raise_camera()
	else:
		lower_camera()


func lower_camera() -> void:
	if camera_lowered or lower_parts.is_empty():
		return
	camera_lowered = true
	_set_actions_blocked(true)
	_tween_camera_parts(true)


func raise_camera() -> void:
	if not camera_lowered or lower_parts.is_empty():
		return
	camera_lowered = false
	_tween_camera_parts(false)
	camera_tween.finished.connect(_on_camera_raised, CONNECT_ONE_SHOT)


func _tween_camera_parts(lowered: bool) -> void:
	if camera_tween:
		camera_tween.kill()
	camera_tween = create_tween().set_parallel(true)
	camera_tween.set_trans(Tween.TRANS_SINE)
	camera_tween.set_ease(Tween.EASE_IN if lowered else Tween.EASE_OUT)
	for part in lower_parts:
		var target: Vector3 = lower_part_rest[part]
		if lowered:
			target += Vector3(0.0, -CAMERA_LOWER_OFFSET, 0.0)
		camera_tween.tween_property(part, "position", target, CAMERA_LOWER_TIME)


func _on_camera_raised() -> void:
	if not camera_lowered:
		_set_actions_blocked(false)


func _exit_tree() -> void:
	_set_actions_blocked(false)


func _get_actions_to_block() -> Array[StringName]:
	var allowed: Array[StringName] = []
	allowed.append_array(always_allowed_actions)
	allowed.append_array(zoom_actions)

	var result: Array[StringName] = []
	for a in InputMap.get_actions():
		if allowed.has(a) or String(a).begins_with("ui_"):
			continue
		result.append(a)
	return result


func _set_actions_blocked(blocked: bool) -> void:
	if blocked:
		if not saved_action_events.is_empty():
			return
		for a in _get_actions_to_block():
			saved_action_events[a] = InputMap.action_get_events(a).duplicate()
			InputMap.action_erase_events(a)
			Input.action_release(a)
	else:
		for a in saved_action_events:
			for e in saved_action_events[a]:
				InputMap.action_add_event(a, e)
		saved_action_events.clear()


func _process(_delta: float) -> void:
	if viewmodel_camera and camera:
		viewmodel_camera.global_transform = camera.global_transform


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed('toggle_camera'):
		toggle_camera()
		return

	var snap_pressed = InputMap.has_action('snap') and event.is_action_pressed('snap') and can_snap and not camera_lowered

	if locked_enemy != null:
		if snap_pressed:
			_attempt_snap()
		return

	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera_base_pitch -= event.relative.y * SENSITIVITY
		camera_base_pitch = clamp(camera_base_pitch, deg_to_rad(-40), deg_to_rad(60))

	if snap_pressed:
		_attempt_snap()


func _attempt_snap() -> void:
	can_snap = false
	if camera_ray.is_colliding():
		var collider = camera_ray.get_collider()
		var hit_distance = camera.global_position.distance_to(camera_ray.get_collision_point())
		
		if hit_distance <= 5.0:
			if collider.is_in_group('abstracts'):
				pass
				
	await get_tree().create_timer(SNAP_COOLDOWN).timeout
	can_snap = true


func apply_knockback(direction: Vector3, force: float, vertical_force: float = 0.0, duration: float = 0.3) -> void:
	knockback_velocity = direction * force
	knockback_timer = duration
	knockback_duration = duration
	if vertical_force > 0.0:
		velocity.y = vertical_force


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if locked_enemy:
		var to_target = (locked_enemy.global_position + Vector3.UP * 1.5) - camera.global_position
		var target_y = atan2(-to_target.x, -to_target.z)
		var target_pitch = asin(to_target.y / to_target.length())
		head.rotation.y = lerp_angle(head.rotation.y, target_y, 15.0 * delta)
		camera_base_pitch = lerp_angle(camera_base_pitch, target_pitch, 15.0 * delta)

	if was_in_air and is_on_floor():
		_play_random_sfx(land_sounds, sfx_player, 0.0, 0.05, 1.0)
		target_impact_pitch = -LAND_ROT_AMOUNT
		floor_time = 0.0
	was_in_air = not is_on_floor()

	if is_on_floor():
		floor_time += delta
		if floor_time > BHOP_WINDOW:
			bhop_count = 0

	var input_dir = Input.get_vector('left', 'right', 'up', 'down')
	var is_moving = input_dir.length() > 0.0
	var is_trying_to_sprint = Input.is_action_pressed('sprint') and is_moving
	
	if is_trying_to_sprint and current_stamina > 0.0:
		speed = SPRINT_SPEED
		step_interval = 0.25
		current_stamina -= delta
		stamina_cooldown = stamina_regen_delay
	else:
		speed = WALK_SPEED
		step_interval = 0.42
		
		if current_stamina <= 0.0:
			bhop_count = 0
		
		if stamina_cooldown > 0.0:
			stamina_cooldown -= delta
		elif current_stamina < max_stamina:
			current_stamina += stamina_regen_rate * delta
			
	current_stamina = clamp(current_stamina, 0.0, max_stamina)

	if stamina_bar:
		if stamina_bar.has_method('update_stamina'):
			stamina_bar.update_stamina(current_stamina, max_stamina, is_trying_to_sprint)
		else:
			stamina_bar.value = current_stamina

	var base_speed = speed
	var bhop_progress = float(bhop_count) / 3.0
	current_max_speed = lerp(base_speed, MAX_BHOP_SPEED, clamp(bhop_progress, 0.0, 1.0))

	if Input.is_action_just_pressed('jump') and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_random_sfx(jump_sounds, sfx_player, 0.0, 0.05, 1.0)
		
		if floor_time <= BHOP_WINDOW and current_stamina > 0.0:
			bhop_count = min(bhop_count + 1, 3)
		floor_time = 0.0

	var direction = (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if knockback_timer > 0.0:
		knockback_timer -= delta
		var knockback_decay: float = clamp(knockback_timer / knockback_duration, 0.0, 1.0)
		velocity.x = knockback_velocity.x * knockback_decay
		velocity.z = knockback_velocity.z * knockback_decay
	elif is_on_floor():
		if direction:
			velocity.x = direction.x * current_max_speed
			velocity.z = direction.z * current_max_speed
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 7.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * current_max_speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * current_max_speed, delta * 3.0)

	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and is_moving and horizontal_speed > 0.5:
		if Input.is_action_just_pressed('up') or Input.is_action_just_pressed('down') or Input.is_action_just_pressed('left') or Input.is_action_just_pressed('right'):
			_play_footstep()
			step_timer = 0.0
		else:
			step_timer += delta
			if step_timer >= step_interval:
				step_timer = 0.0
				_play_footstep()
	else:
		step_timer = 0.0

	var target_bob_pos = _headbob(horizontal_speed, delta)
	camera.transform.origin = camera.transform.origin.lerp(target_bob_pos, delta * BOB_SMOOTH)

	target_impact_pitch = lerp_angle(target_impact_pitch, 0.0, delta * IMPACT_RECOVERY)
	current_impact_pitch = lerp_angle(current_impact_pitch, target_impact_pitch, delta * IMPACT_RECOVERY)
	
	target_roll = -input_dir.x * STRAFE_ROLL_AMOUNT
	current_roll = lerp_angle(current_roll, target_roll, delta * ROLL_SPEED)

	camera.rotation.x = camera_base_pitch + current_impact_pitch
	camera.rotation.z = current_roll
	
	if not is_zoomed:
		var velocity_clamped = clamp(velocity.length(), 0.5, MAX_BHOP_SPEED * 1.5)
		var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
		camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	move_and_slide()

	if is_on_wall() and not was_on_wall and horizontal_speed > 2.5:
		_play_random_sfx(wall_hit_sounds, impact_player, 0.0, 0.1, 1.5)
		target_impact_pitch = WALL_ROT_AMOUNT
		bhop_count = 0
	was_on_wall = is_on_wall()


func _headbob(horizontal_speed: float, delta: float) -> Vector3:
	var pos = Vector3.ZERO
	if is_on_floor():
		bob_phase += horizontal_speed * delta * BOB_FREQ
		var speed_factor = clamp(horizontal_speed / SPRINT_SPEED, 0.0, 1.0)
		pos.y = sin(bob_phase) * BOB_AMP * speed_factor
		pos.x = cos(bob_phase * 0.5) * BOB_AMP * speed_factor
	return pos


func _play_footstep() -> void:
	_play_random_sfx(walk_sounds, sfx_player, 0.0, 0.08, 1.0)


func _play_random_sfx(sound_array: Array[AudioStream], target_player: AudioStreamPlayer3D, base_volume_db: float = 0.0, pitch_range: float = 0.08, volume_range: float = 1.0) -> void:
	if sound_array.is_empty() or not target_player:
		return
	var random_sound = sound_array.pick_random()
	if random_sound:
		target_player.stream = random_sound
		target_player.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
		target_player.volume_db = base_volume_db + randf_range(-volume_range, volume_range)
		target_player.play()


func _on_roamer_lunge_started(roamer_node: Node3D) -> void:
	locked_enemy = roamer_node


func _on_roamer_parry_window_closed(_success: bool) -> void:
	locked_enemy = null


func trigger_hit_overlay() -> void:
	hit_overlay.color.a = 1.0 
	
	var tween = create_tween()
	var steps = 4
	var step_duration = 0.1
	
	for i in range(steps - 1, -1, -1):
		var target_alpha = float(i) / float(steps)
		tween.tween_property(hit_overlay, "color:a", target_alpha, 0.0)
		tween.tween_interval(step_duration)
