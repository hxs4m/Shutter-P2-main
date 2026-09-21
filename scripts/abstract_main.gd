extends Area3D

enum Shapes { SPHERE, CUBE, CONE }

@export_group("Shape Settings")
@export var target_shape: Shapes = Shapes.SPHERE:
	set(value):
		target_shape = value
		if is_node_ready():
			_update_everything()

@export_group("Time Rewards")
@export var sphere_time: float = 10.0
@export var cube_time: float = 20.0
@export var cone_time: float = 35.0

@export_group("Lighting Tweaks")
@export var custom_light_energy: float = 0.1

@export_group("Coin Animation Settings")
@export var coin_sprite_frames: SpriteFrames
@export var animation_name: String = "abstract"

@export_group("Floating & Spinning")
@export var spin_speed: float = 2.0
@export var float_amplitude: float = 0.15
@export var float_speed: float = 3.0

const COLOR_RED = Color(1.0, 0.1, 0.1)
const COLOR_GREEN = Color(0.1, 1.0, 0.1)
const COLOR_BLUE = Color(0.1, 0.4, 1.0)

var mat: ShaderMaterial
var total_frames: int = 0
var fps: float = 10.0
var frame_duration: float = 0.1
var elapsed_time: float = 0.0
var last_frame_index: int = -1
var start_y: float = 0.0
var has_been_photographed: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("abstracts")
	start_y = position.y
	_make_systems_unique()
	_update_everything()
	
	if coin_sprite_frames and coin_sprite_frames.has_animation(animation_name):
		fps = coin_sprite_frames.get_animation_speed(animation_name)
		if fps <= 0:
			fps = 10.0
		frame_duration = 1.0 / fps
		total_frames = coin_sprite_frames.get_frame_count(animation_name)

func _make_systems_unique() -> void:
	if mesh_instance and mesh_instance.material_override:
		mesh_instance.material_override = mesh_instance.material_override.duplicate()
		if mesh_instance.material_override is ShaderMaterial:
			mat = mesh_instance.material_override as ShaderMaterial

	for particle_name in ["GPUParticles3D", "GPUParticles3D2"]:
		if has_node(particle_name):
			var p = get_node(particle_name) as GPUParticles3D
			if p.process_material:
				p.process_material = p.process_material.duplicate()
			if p.draw_pass_1:
				p.draw_pass_1 = p.draw_pass_1.duplicate()
				if p.draw_pass_1.material:
					p.draw_pass_1.material = p.draw_pass_1.material.duplicate()

func _update_everything() -> void:
	var choice_color: Color
	
	match target_shape:
		Shapes.SPHERE:
			mesh_instance.mesh = SphereMesh.new()
			collision_shape.shape = SphereShape3D.new()
			choice_color = COLOR_GREEN
		Shapes.CUBE:
			mesh_instance.mesh = BoxMesh.new()
			collision_shape.shape = BoxShape3D.new()
			choice_color = COLOR_RED
		Shapes.CONE:
			var cone = CylinderMesh.new()
			cone.top_radius = 0.0
			mesh_instance.mesh = cone
			var c_shape = CylinderShape3D.new()
			c_shape.radius = cone.bottom_radius
			collision_shape.shape = c_shape
			choice_color = COLOR_BLUE

	if mat and mesh_instance.mesh:
		mesh_instance.material_override = mat

	for particle_name in ["GPUParticles3D", "GPUParticles3D2"]:
		if has_node(particle_name):
			var p = get_node(particle_name) as GPUParticles3D
			if p.draw_pass_1 and p.draw_pass_1.material is StandardMaterial3D:
				var draw_mat = p.draw_pass_1.material as StandardMaterial3D
				draw_mat.albedo_color = choice_color

	if light:
		light.light_color = choice_color
		light.light_energy = custom_light_energy

func _process(delta: float) -> void:
	elapsed_time += delta
	rotate_y(spin_speed * delta)
	position.y = start_y + (sin(elapsed_time * float_speed) * float_amplitude)

	if mat and total_frames > 0:
		var current_frame = int(elapsed_time / frame_duration) % total_frames
		if current_frame != last_frame_index:
			last_frame_index = current_frame
			var current_texture = coin_sprite_frames.get_frame_texture(animation_name, current_frame)
			mat.set_shader_parameter("albedo_texture", current_texture)

func disappear_from_photo() -> float:
	if has_been_photographed:
		return 1.0 # Stops the function if it already ran this frame
	has_been_photographed = true
	
	var reward_seconds: float = 0.0
	var sound_pitch: float = 1.0

	match target_shape:
		Shapes.SPHERE:
			reward_seconds = sphere_time
			sound_pitch = 0.9
			ScoreManager.spheres_collected += 1
		Shapes.CUBE:
			reward_seconds = cube_time
			sound_pitch = 1.2
			ScoreManager.cubes_collected += 1
		Shapes.CONE:
			reward_seconds = cone_time
			sound_pitch = 1.5
			ScoreManager.cones_collected += 1

	var active_timers = get_tree().get_nodes_in_group("MainTimer")
	if active_timers.size() > 0:
		active_timers[0].add_time(reward_seconds)

	queue_free()
	return sound_pitch
