extends Area3D

@export_group("UI & Effects")
@export var win_label: RichTextLabel 
@export var proximity_label: RichTextLabel
@export var glitch_audio_player: AudioStreamPlayer
@export var camera: Camera3D

@export_group("Timing & Glitch Settings")
@export var glitch_duration: float = 3.0
@export var tick_tock_interval: float = 1.0
@export var shake_intensity: float = 0.2
@export var number_of_twentytwos: int = 18

@export_group("Proximity Settings")
@export var proximity_distance: float = 25.0  # Outer threshold set to 25 meters

@export_group("Spawn Settings")
@export var spawn_positions: Array[Vector3] = [
	Vector3(9.168, 339.4, -111.0),
	Vector3(121.7, 339.4, -247.0),
	Vector3(92.10, 339.4, -126.0),
	Vector3(-96.8, 339.4, -163.0),
]

@export_group("Level Transition Options")
@export_file("*.tscn") var next_level_path: String
@export var post_win_delay: float = 2.5

var _spawned_labels: Array[Control] = []
var _player: Node3D = null
var _has_triggered: bool = false

# --- Intro Text State Trackers ---
var _intro_phase: int = 0
var _intro_timer: float = 0.0
var _intro_fade_duration: float = 0.8
var _intro_hold_duration: float = 1.5


func _ready() -> void:
	if spawn_positions.size() > 0:
		global_position = spawn_positions.pick_random()
	
	body_entered.connect(_on_body_entered)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if camera == null:
		camera = get_viewport().get_camera_3d()
	
	if win_label == null:
		var labels = get_tree().get_nodes_in_group("WinLabel")
		if labels.size() > 0 and labels[0] is RichTextLabel:
			win_label = labels[0]
		else:
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_node("winlabel"):
				win_label = ui.get_node("winlabel") as RichTextLabel

	if win_label:
		win_label.visible = false


	if proximity_label:
		proximity_label.visible = false

	if proximity_label == null:
			var ui = get_tree().root.find_child("UI", true, false)
			if ui and ui.has_node("ProximityLabel"):
				proximity_label = ui.get_node("ProximityLabel") as RichTextLabel

func _process(delta: float) -> void:
	if _has_triggered:
		return

	if _player == null:
		var players = get_tree().get_nodes_in_group("PlayerGroup")
		if players.size() > 0:
			_player = players[0]
		else:
			return

	if proximity_label:
		var dist: float = global_position.distance_to(_player.global_position)
		
		if dist <= proximity_distance:
			proximity_label.visible = true

			if _intro_phase < 3:
				_process_intro_text(delta)
			else:
				_render_distance_display(dist)
		else:
			proximity_label.visible = false
			_intro_phase = 0
			_intro_timer = 0.0


func _process_intro_text(delta: float) -> void:
	_intro_timer += delta
	proximity_label.text = "[center][font_size=36][color=#F5F5DC][i]I CAN FEEL IT[/i][/color][/font_size][/center]"

	match _intro_phase:
		0:
			var progress: float = clamp(_intro_timer / _intro_fade_duration, 0.0, 1.0)
			proximity_label.modulate.a = snappedf(progress, 0.25)
			if progress >= 1.0:
				_intro_phase = 1
				_intro_timer = 0.0
		1:
			proximity_label.modulate.a = 1.0
			if _intro_timer >= _intro_hold_duration:
				_intro_phase = 2
				_intro_timer = 0.0
		2:
			var progress: float = clamp(_intro_timer / _intro_fade_duration, 0.0, 1.0)
			proximity_label.modulate.a = snappedf(1.0 - progress, 0.25)
			if progress >= 1.0:
				_intro_phase = 3
				_intro_timer = 0.0


func _render_distance_display(dist: float) -> void:
	var raw_fade: float = clamp((proximity_distance - dist) / 5.0, 0.0, 1.0)
	var choppy_alpha: float = maxf(snappedf(raw_fade, 0.25), 0.25)
	proximity_label.modulate.a = choppy_alpha

	var text_color: String = "red" if dist < 10.0 else "yellow"
	proximity_label.text = "[center][font_size=32][color=%s]%dM[/color][/font_size][/center]" % [text_color, int(dist)]


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("PlayerGroup") and not _has_triggered:
		_has_triggered = true
		print("🏆 Player reached the exit!")

		# --- NEW: GRAB TIME AND CALCULATE SCORE ---
		var timers = get_tree().get_nodes_in_group("MainTimer")
		var remaining_time = 0.0
		if timers.size() > 0:
			remaining_time = timers[0].timer.time_left # Read the clock
		
		ScoreManager.calculate_final_score(remaining_time)
		# ------------------------------------------

		get_tree().call_group("MainTimer", "hide_timer") # Your original code

		body_entered.disconnect(_on_body_entered)
		
		if proximity_label:
			proximity_label.visible = false

		_trigger_glitch_sequence(body)


func _trigger_glitch_sequence(player: Node3D) -> void:
	if glitch_audio_player:
		glitch_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		glitch_audio_player.play()

	if win_label:
		win_label.process_mode = Node.PROCESS_MODE_ALWAYS
		win_label.visible = true

	get_tree().paused = true
	
	var elapsed: float = 0.0
	var toggle_tick_tock: bool = false
	
	var original_cam_h_offset: float = camera.h_offset if camera else 0.0
	var original_cam_v_offset: float = camera.v_offset if camera else 0.0
	
	var stuck_h_offset: float = shake_intensity if randf() > 0.5 else -shake_intensity
	var stuck_v_offset: float = shake_intensity if randf() > 0.5 else -shake_intensity

	while elapsed < glitch_duration:
		toggle_tick_tock = !toggle_tick_tock
		
		if win_label:
			if toggle_tick_tock:
				win_label.text = "[center][font_size=64][shake rate=40.0 level=25][color=red]T I C K[/color][/shake][/font_size][/center]"
			else:
				win_label.text = "[center][font_size=64][shake rate=40.0 level=25][color=red]T O C K[/color][/shake][/font_size][/center]"

		if camera:
			camera.h_offset = original_cam_h_offset + stuck_h_offset
			camera.v_offset = original_cam_v_offset + stuck_v_offset

		await get_tree().create_timer(tick_tock_interval, true, false, true).timeout
		elapsed += tick_tock_interval

	if camera:
		camera.h_offset = original_cam_h_offset
		camera.v_offset = original_cam_v_offset

	# --- MODIFIED: Replaced '22' text loop with a glitched Win State text ---
	if win_label:
		win_label.text = "[center][font_size=80][shake rate=50.0 level=20][color=beige]Y O U  W I N[/color][/shake][/font_size][/center]"

	_spawn_haphazard_twentytwos()

# Pause momentarily on the glitched win text
	await get_tree().create_timer(post_win_delay, true, false, true).timeout
	
	# --- NEW: SHOW SCORE MENU AND WAIT ---
	# (Assuming you put your ScoreMenu inside your UI node)
	var ui = get_tree().root.find_child("UI", true, false)
	if ui and ui.has_node("ScoreMenu"):
		var score_menu = ui.get_node("ScoreMenu")
		score_menu.show_score()
		
		# Wait right here until the player clicks the "Proceed" button!
		await score_menu.next_level_button.pressed 
	# -------------------------------------

	# After they click proceed, carry out the world scene swap
	_cleanup_and_swap_scenes(player)


func _spawn_haphazard_twentytwos() -> void:
	if win_label == null:
		return
		
	var parent_ui = win_label.get_parent()
	var viewport_size = get_viewport().get_visible_rect().size

	for i in range(number_of_twentytwos):
		var lbl = Label.new()
		lbl.text = "22"
		lbl.process_mode = Node.PROCESS_MODE_ALWAYS
		
		var font_size = randi_range(24, 96)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", Color(1.0, randf_range(0.0, 0.2), randf_range(0.0, 0.2), randf_range(0.6, 1.0)))
		
		lbl.position = Vector2(
			randf_range(50.0, viewport_size.x - 100.0),
			randf_range(50.0, viewport_size.y - 100.0)
		)
		lbl.rotation = randf_range(-0.5, 0.5)
		lbl.pivot_offset = lbl.size / 2.0
		
		parent_ui.add_child(lbl)
		_spawned_labels.append(lbl)

# --- Performs clean swap on the world tree nodes while preserving UI/Shaders ---
func _cleanup_and_swap_scenes(player: Node3D) -> void:
	# 1. Strip out the glitched label elements from the screen
	for lbl in _spawned_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_spawned_labels.clear()

	if win_label:
		win_label.visible = false
		win_label.text = ""

	# 2. Unpause the engine so the new map elements can initialize safely
	get_tree().paused = false

	# 3. Find the master world root node scene
	var world_root = get_tree().current_scene
	if not world_root:
		push_error("Transition Failed: Current active scene tree root could not be located.")
		return

	# 4. Wipe out the old level node layout cleanly
	var old_level = world_root.get_node_or_null("lvl0fn")
	if old_level:
		old_level.queue_free()

	# 5. Bring in and instance the second map layout data structure
	if next_level_path == "":
		push_error("Transition Failed: No map file path assigned in Next Level Path export slot!")
		return
		
	var target_scene_resource = load(next_level_path)
	if target_scene_resource:
		var new_map_instance = target_scene_resource.instantiate()
		new_map_instance.name = "lvl0fn"
		world_root.add_child(new_map_instance)

		# 6. Teleport the player node to the spawn destination marker setup inside Map 2
		var target_marker = new_map_instance.get_node_or_null("SpawnPoint")
		if target_marker:
			player.global_transform = target_marker.global_transform
		else:
			player.global_position = Vector3.ZERO
			push_warning("Transition Notice: No 'SpawnPoint' Marker3D node found inside map file.")

		# --- FIXED: CHECK TRUE FILE PATH USING THE LOADED RESOURCE ---
		var true_path: String = target_scene_resource.resource_path
		print("True target file path resolved: ", true_path)
		
		if "lvl_2" in true_path or "lvl2" in true_path or "level_2" in true_path or "level2" in true_path:
			print(">> Level 2 matched via true path. Hiding dither shader container.")
			var dither_node = world_root.find_child("dithershader", true, false)
			if dither_node:
				if "visible" in dither_node:
					dither_node.visible = false
				for child in dither_node.get_children():
					if "visible" in child:
						child.visible = false
		else:
			# Fallback: Turn it back on if transitioning to any other levels that need it
			var dither_node = world_root.find_child("dithershader", true, false)
			if dither_node:
				if "visible" in dither_node:
					dither_node.visible = true
				for child in dither_node.get_children():
					if "visible" in child:
						child.visible = true

	# 7. Locate and kickstart your MainTimer script system to start counting fresh
	var timer_node = world_root.get_node_or_null("UI/MainTimer")
	if timer_node and timer_node.has_method("reset_for_next_level"):
		timer_node.reset_for_next_level()
