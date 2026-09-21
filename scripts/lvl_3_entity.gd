extends CharacterBody3D

@export_category("References")
@export var player: Node3D
@export var main_timer: Node

@export_category("Detection Radius")
@export var detection_radius: float = 12.0     # Horizontal radius to spot the player
@export var lose_sight_radius: float = 18.0    # Radius where it loses track completely

@export_category("Roaming / Idle Behavior")
@export var enable_roaming: bool = true
@export var roam_radius: float = 8.0           # Max distance from spawn to pick roam targets
@export var roam_speed: float = 1.8            # Speed while wandering
@export var roam_wait_time: float = 2.0        # Pause time at destination
@export var max_stuck_time: float = 5.0        # Pick new roam target if blocked by obstacle

@export_category("Movement")
@export var move_speed: float = 4.0
@export var float_height: float = 1.5
@export var bob_speed: float = 2.0
@export var bob_height: float = 0.5

@export_category("Jumpscare Settings")
@export var catch_distance: float = 1.5
@export var time_penalty: float = 60.0
@export var jumpscare_duration: float = 1.2
@export var jumpscare_shake_intensity: float = 0.5

@export_category("Respawn Settings")
@export_range(0.0, 1.0) var respawn_chance: float = 0.15  # Set to 0.0 to disable respawning entirely

var is_chasing: bool = false
var has_target_position: bool = false
var last_known_position: Vector3 = Vector3.ZERO
var time_alive: float = 0.0

var _is_jumpscaring: bool = false

# Roaming internal variables
var _spawn_origin: Vector3
var _roam_target: Vector3
var _is_roaming: bool = false
var _roam_timer: float = 0.0
var _stuck_timer: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_spawn_origin = global_position
	_pick_new_roam_target()


func _flat_distance_to(target: Vector3) -> float:
	var pos_2d := Vector2(global_position.x, global_position.z)
	var target_2d := Vector2(target.x, target.z)
	return pos_2d.distance_to(target_2d)


func _physics_process(delta: float) -> void:
	if player == null or _is_jumpscaring:
		return

	time_alive += delta

	var dist_to_player := _flat_distance_to(player.global_position)
	var effective_lose_radius := maxf(lose_sight_radius, detection_radius)

	# --- AGGRO STATE MACHINE ---
	if dist_to_player <= detection_radius:
		is_chasing = true
		has_target_position = true
		last_known_position = player.global_position
	elif is_chasing and dist_to_player > effective_lose_radius:
		is_chasing = false
	elif is_chasing:
		last_known_position = player.global_position

	# --- MOVEMENT EXECUTION ---
	if is_chasing or has_target_position:
		_is_roaming = false
		_roam_timer = 0.0
		_stuck_timer = 0.0

		var target_pos := player.global_position if is_chasing else last_known_position
		var target_dir := global_position.direction_to(target_pos)
		var current_float_offset := sin(time_alive * bob_speed) * bob_height

		velocity.x = target_dir.x * move_speed
		velocity.z = target_dir.z * move_speed

		var target_y := target_pos.y + float_height + current_float_offset
		velocity.y = (target_y - global_position.y) * 2.0

		var look_target := target_pos
		look_target.y = global_position.y
		if global_position.distance_squared_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

		move_and_slide()

		if not is_chasing and _flat_distance_to(last_known_position) <= 0.8:
			has_target_position = false
			velocity = Vector3.ZERO
			_spawn_origin = global_position
			_pick_new_roam_target()

	elif enable_roaming:
		_process_roaming(delta)

	# --- CATCH / JUMPSCARE CHECK ---
	if dist_to_player <= catch_distance:
		_trigger_jumpscare()


func _process_roaming(delta: float) -> void:
	var current_float_offset := sin(time_alive * bob_speed) * bob_height

	if _is_roaming:
		_stuck_timer += delta

		var dir := global_position.direction_to(_roam_target)
		velocity.x = dir.x * roam_speed
		velocity.z = dir.z * roam_speed

		var target_y := _spawn_origin.y + float_height + current_float_offset
		velocity.y = (target_y - global_position.y) * 2.0

		var look_target := _roam_target
		look_target.y = global_position.y
		if global_position.distance_squared_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

		move_and_slide()

		if _flat_distance_to(_roam_target) <= 0.8 or _stuck_timer >= max_stuck_time:
			_is_roaming = false
			_roam_timer = roam_wait_time
			_stuck_timer = 0.0
			velocity = Vector3.ZERO
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		var target_y := _spawn_origin.y + float_height + current_float_offset
		velocity.y = (target_y - global_position.y) * 2.0
		move_and_slide()

		_roam_timer -= delta
		if _roam_timer <= 0.0:
			_pick_new_roam_target()


func _pick_new_roam_target() -> void:
	var random_angle := randf() * TAU
	var random_dist := randf_range(3.0, roam_radius)
	var offset := Vector3(cos(random_angle) * random_dist, 0.0, sin(random_angle) * random_dist)
	_roam_target = _spawn_origin + offset
	_is_roaming = true
	_stuck_timer = 0.0


# ---------------------------------------------------------
# CAMERA INTERACTION: REVEAL MODE
# ---------------------------------------------------------
func apply_reveal() -> float:
	if _is_jumpscaring:
		return -1.0

	if not collision.disabled and is_instance_valid(collision):
		collision.set_deferred("disabled", true)
	else:
		return -1.0

	is_chasing = false
	has_target_position = false
	enable_roaming = false
	set_physics_process(false)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(mesh, "rotation_degrees:y", 1080.0, 0.7).set_ease(Tween.EASE_IN)
	tween.tween_property(mesh, "position:y", mesh.position.y + 2.5, 0.7)
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.chain().tween_callback(_respawn_and_delete)
	return 1.3


func _respawn_and_delete() -> void:
	# 15% probability roll check to instantiate a replacement
	if randf() <= respawn_chance:
		var new_slime = load(scene_file_path).instantiate()

		# Transfer scene references
		new_slime.player = player
		new_slime.main_timer = main_timer

		# Transfer Inspector overrides to the new clone
		new_slime.detection_radius = detection_radius
		new_slime.lose_sight_radius = lose_sight_radius
		new_slime.enable_roaming = enable_roaming
		new_slime.roam_radius = roam_radius
		new_slime.roam_speed = roam_speed
		new_slime.roam_wait_time = roam_wait_time
		new_slime.move_speed = move_speed
		new_slime.catch_distance = catch_distance
		new_slime.time_penalty = time_penalty
		new_slime.respawn_chance = respawn_chance

		var random_angle = randf() * TAU
		var spawn_dist = randf_range(15.0, 25.0)
		var spawn_offset = Vector3(cos(random_angle) * spawn_dist, 0.0, sin(random_angle) * spawn_dist)

		new_slime.global_position = player.global_position + spawn_offset

		get_tree().current_scene.add_child(new_slime)

	queue_free()


func _trigger_jumpscare() -> void:
	if _is_jumpscaring:
		return
	_is_jumpscaring = true
	set_physics_process(false)

	is_chasing = false
	has_target_position = false
	enable_roaming = false

	if main_timer and main_timer.has_method("subtract_time"):
		main_timer.subtract_time(time_penalty)

	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera:
		var forward_dir = -camera.global_transform.basis.z
		global_position = camera.global_position + (forward_dir * 1.0)
		look_at(camera.global_position, Vector3.UP)

		var tween = create_tween()
		tween.set_loops(int(jumpscare_duration * 10))

		for i in range(int(jumpscare_duration * 10)):
			var random_offset = Vector3(
				randf_range(-jumpscare_shake_intensity, jumpscare_shake_intensity),
				randf_range(-jumpscare_shake_intensity, jumpscare_shake_intensity),
				0
			)
			tween.tween_property(mesh, "position", random_offset, 0.05)
			tween.tween_property(mesh, "position", Vector3.ZERO, 0.05)

		await get_tree().create_timer(jumpscare_duration).timeout
		queue_free()
	else:
		queue_free()
