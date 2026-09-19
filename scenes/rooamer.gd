extends CharacterBody3D

@onready var anim_tree = $AnimationTree
@onready var playback = anim_tree.get("parameters/playback")
@onready var nav_agent = $NavigationAgent3D 

@export var speed: float = 8.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var player: CharacterBody3D

var is_attacking: bool = false
var parry_window_open: bool = false

# These signals connect to the existing lock-on functions in plyer.gd
signal lunge_started(roamer_node)
signal parry_window_closed(success)

func _ready() -> void:
	add_to_group("roamers") 
	# Grab the player reference on spawn
	player = get_tree().get_first_node_in_group("Player")

# Connect this to the body_entered signal of your lunge detection Area3D
func _on_lunge_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and not is_attacking:
		is_attacking = true
		playback.travel("attack")
		
		# Trigger the camera lock-on in plyer.gd
		emit_signal("lunge_started", self)
		
		# Apply initial forward lunge burst horizontally
		var lunge_dir = (body.global_position - global_position).normalized()
		velocity.x = lunge_dir.x * 18.0 
		velocity.z = lunge_dir.z * 18.0

# --- ANIMATION TRACK METHODS ---
# Add a Call Method keyframe at 0.2 seconds in the attack animation
func open_parry_window() -> void:
	parry_window_open = true

# Add a Call Method keyframe at 0.5 seconds in the attack animation
func close_parry_window() -> void:
	parry_window_open = false
	emit_signal("parry_window_closed", false)
	
	# Optional: Check distance to player here to apply damage if parry missed
	is_attacking = false
	playback.travel("run")

# --- CAMERA INTERACTION ---
# Called automatically by cmra.gd's _apply_repel() function
func apply_repel(from_pos: Vector3) -> bool:
	if parry_window_open:
		# 1. SUCCESSFUL PARRY LOGIC
		parry_window_open = false
		is_attacking = false
		
		# 2. Push Roamer Back
		var push_dir = (global_position - from_pos).normalized()
		velocity.x = push_dir.x * 25.0 
		velocity.z = push_dir.z * 25.0
		
		# 3. Trigger visual effect
		_spawn_shockwave()
		
		# 4. Interrupt animation and reset lock-on
		playback.travel("run")
		emit_signal("parry_window_closed", true)
		
		# Returning true tells cmra.gd to boost the player in the opposite direction
		return true 
		
	# Returning false tells cmra.gd the parry failed
	return false

func _spawn_shockwave() -> void:
	pass # Instance your explosion/shockwave particle scene here

func _physics_process(delta: float) -> void:
	# 1. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Nextbot Chasing Logic
	if not is_attacking and player:
		# Update path to player
		nav_agent.target_position = player.global_position
		
		# Look at the player (Y-axis only so it doesn't tilt up/down)
		var look_pos = player.global_position
		look_pos.y = global_position.y
		if global_position.distance_to(look_pos) > 0.1:
			look_at(look_pos, Vector3.UP)
		
		# Move along NavigationMesh
		var next_path_pos = nav_agent.get_next_path_position()
		var direction = (next_path_pos - global_position).normalized()
		
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
	elif is_attacking:
		# 3. Lunge & Knockback Friction
		# Slowly dampens the horizontal speed while attacking or knocked back
		velocity.x = lerp(velocity.x, 0.0, delta * 3.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 3.0)

	move_and_slide()
