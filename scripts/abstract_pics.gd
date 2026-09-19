extends MeshInstance3D

enum Shapes { SPHERE, CUBE, CONE, CYLINDER, PRISM }
@export var target_shape: Shapes = Shapes.SPHERE

@export_group("Coin Animation Settings")
@export var coin_sprite_frames: SpriteFrames
@export var animation_name: String = "abstract"

@export_group("Floating & Spinning")
@export var spin_speed: float = 2.0       # How fast it spins (radians per second)
@export var float_amplitude: float = 0.15  # How high and low it floats
@export var float_speed: float = 3.0      # How fast it bobs up and down

var mat: ShaderMaterial
var total_frames: int = 0
var fps: float = 10.0
var frame_duration: float = 0.1

var elapsed_time: float = 0.0 
var last_frame_index: int = -1

# Cache the initial starting height so it doesn't drift away
var start_y: float = 0.0

func _ready() -> void:
	if material_override is ShaderMaterial:
		mat = material_override as ShaderMaterial
	
	update_mesh_shape()
	
	# Save the exact Y position where you placed the mesh in your scene
	start_y = position.y
	
	if coin_sprite_frames and coin_sprite_frames.has_animation(animation_name):
		fps = coin_sprite_frames.get_animation_speed(animation_name)
		if fps <= 0: fps = 10.0
		frame_duration = 1.0 / fps
		total_frames = coin_sprite_frames.get_frame_count(animation_name)

func update_mesh_shape() -> void:
	match target_shape:
		Shapes.SPHERE:
			mesh = SphereMesh.new()
		Shapes.CUBE:
			mesh = BoxMesh.new()
		Shapes.CONE:
			var cone = CylinderMesh.new()
			cone.top_radius = 0.0
			mesh = cone
		Shapes.CYLINDER:
			mesh = CylinderMesh.new()
		Shapes.PRISM:
			mesh = PrismMesh.new()
			
	# Re-apply the material to the brand new mesh geometry so the shader doesn't drop off
	if mat and mesh:
		material_override = mat


func _process(delta: float) -> void:
	# --- 1. IDLE BEHAVIOR (SPIN & FLOAT) ---
	# Spin the object around its Y axis uniformly
	rotate_y(spin_speed * delta)
	
	# Use a sine wave over the running total time to create a smooth hover effect
	position.y = start_y + (sin(elapsed_time * float_speed) * float_amplitude)

	# --- 2. TEXTURE FRAME UPDATES ---
	if not mat or total_frames <= 0: 
		return
	
	elapsed_time += delta
	var current_frame = int(elapsed_time / frame_duration) % total_frames
	
	if current_frame != last_frame_index:
		last_frame_index = current_frame
		var current_texture = coin_sprite_frames.get_frame_texture(animation_name, current_frame)
		mat.set_shader_parameter("albedo_texture", current_texture)
