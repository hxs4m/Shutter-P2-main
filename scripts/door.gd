extends Area3D

@export_group("UI & Effects")
@export var win_label: RichTextLabel 
@export var proximity_label: RichTextLabel
@export var glitch_audio_player: AudioStreamPlayer
@export var camera: Camera3D

@export_group("Glitch Settings")
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
@export var next_level_scene: PackedScene  # Drag & drop scene file directly here
@export_file("*.tscn") var next_level_path: String  # Or pick scene file path here
@export var show_score_menu: bool = true  # Toggle score menu on/off for this door
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

	if proximity_label == null:
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_node("ProximityLabel"):
			proximity_label = ui.get_node("ProximityLabel") as RichTextLabel

	if proximity_label:
		proximity_label.visible = false


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

		# --- GRAB TIME AND CALCULATE SCORE ---
		var timers = get_tree().get_nodes_in_group("MainTimer")
		var remaining_time = 0.0
		if timers.size() > 0:
			remaining_time = timers[0].timer.time_left
		
		ScoreManager.calculate_final_score(remaining_time)

		get_tree().call_group("MainTimer", "hide_timer")

		body_entered.disconnect(_on_body_entered)
		
		if proximity_label:
			proximity_label.visible = false

		_trigger_glitch_sequence()


func _trigger_glitch_sequence() -> void:
	if glitch_audio_player:
		glitch_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		glitch_audio_player.play()

	get_tree().paused = true

	if win_label:
		win_label.process_mode = Node.PROCESS_MODE_ALWAYS
		win_label.visible = true
		win_label.text = "[center][font_size=80][shake rate=50.0 level=20][color=beige]Y O U  W I N[/color][/shake][/font_size][/center]"

	_spawn_haphazard_twentytwos()

	# Pause momentarily on win text
	await get_tree().create_timer(post_win_delay, true, false, true).timeout
	
	# --- OPTIONAL SCORE MENU ---
	if show_score_menu:
		var ui = get_tree().root.find_child("UI", true, false)
		if ui and ui.has_node("ScoreMenu"):
			var score_menu = ui.get_node("ScoreMenu")
			score_menu.show_score()
			
			# Wait until player presses "Proceed"
			await score_menu.next_level_button.pressed 

	# Carry out scene swap
	_cleanup_and_swap_scenes()


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


func _cleanup_and_swap_scenes() -> void:
	# 1. Clean up glitched labels from current UI
	for lbl in _spawned_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_spawned_labels.clear()

	if win_label:
		win_label.visible = false
		win_label.text = ""

	# 2. Unpause engine before loading the new scene
	get_tree().paused = false

	# 3. Load the new scene directly (destroys current scene & player)
	if next_level_scene:
		var err = get_tree().change_scene_to_packed(next_level_scene)
		if err != OK:
			push_error("Transition Failed: Could not load assigned PackedScene. Error code: %d" % err)
	elif next_level_path != "":
		var err = get_tree().change_scene_to_file(next_level_path)
		if err != OK:
			push_error("Transition Failed: Could not load scene at path '%s'. Error code: %d" % [next_level_path, err])
	else:
		push_error("Transition Failed: No 'next_level_scene' or 'next_level_path' configured in Inspector!")
