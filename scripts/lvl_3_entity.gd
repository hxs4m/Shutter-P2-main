extends CharacterBody3D

@export_category("References")
@export var player: Node3D
@export var main_timer: Node 

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

var is_chasing: bool = true
var time_alive: float = 0.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

func _physics_process(delta: float) -> void:
	if not is_chasing or player == null:
		return
		
	time_alive += delta
	
	var direction = global_position.direction_to(player.global_position)
	var current_float_offset = sin(time_alive * bob_speed) * bob_height
	
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	var target_y = player.global_position.y + float_height + current_float_offset
	velocity.y = (target_y - global_position.y) * 2.0
	
	var look_pos = player.global_position
	look_pos.y = global_position.y
	look_at(look_pos, Vector3.UP)
	
	move_and_slide()
	
	if global_position.distance_to(player.global_position) <= catch_distance:
		_trigger_jumpscare()


# ---------------------------------------------------------
# CAMERA INTERACTION: REVEAL MODE
# ---------------------------------------------------------
func apply_reveal() -> float:
	# Prevent triggering multiple times if shot repeatedly
	if not is_chasing:
		return -1.0
		
	is_chasing = false
	
	# Disable collision so it can't catch the player while dying
	collision.set_deferred("disabled", true)
	
	# Create a procedural death animation
	var tween = create_tween().set_parallel(true)
	
	# Spin wildly, float upward, and shrink to nothing
	tween.tween_property(mesh, "rotation_degrees:y", 1080.0, 0.7).set_ease(Tween.EASE_IN)
	tween.tween_property(mesh, "position:y", mesh.position.y + 2.5, 0.7)
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# When the animation finishes, spawn a new one and delete this one
	tween.chain().tween_callback(_respawn_and_delete)
	
	# Returns a high pitch for the camera's capture sound success
	return 1.3 


func _respawn_and_delete() -> void:
	# Load this exact same scene file dynamically
	var new_slime = load(scene_file_path).instantiate()
	
	# Pass the necessary references to the new clone
	new_slime.player = player
	new_slime.main_timer = main_timer
	
	# Pick a random spawn location 15 to 25 meters away from the player
	var random_angle = randf() * TAU
	var spawn_dist = randf_range(15.0, 25.0)
	var spawn_offset = Vector3(cos(random_angle) * spawn_dist, 0.0, sin(random_angle) * spawn_dist)
	
	new_slime.global_position = player.global_position + spawn_offset
	
	# Add the new slime to the world
	get_tree().current_scene.add_child(new_slime)
	
	# Delete the old slime
	queue_free()


func _trigger_jumpscare() -> void:
	is_chasing = false
	
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
