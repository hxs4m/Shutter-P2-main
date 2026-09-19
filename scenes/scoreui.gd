extends CanvasLayer

# --- Node References ---
@onready var background = $Background
@onready var title_label = $Background/CenterContainer/MainColumn/TitleLabel
@onready var divider1 = $Background/CenterContainer/MainColumn/Divider1
@onready var grid = $Background/CenterContainer/MainColumn/ScoreGrid
@onready var divider2 = $Background/CenterContainer/MainColumn/Divider2
@onready var level_total_label = $Background/CenterContainer/MainColumn/LevelTotalLabel
@onready var overall_total_label = $Background/CenterContainer/MainColumn/OverallTotalLabel
@onready var next_level_button = $Background/CenterContainer/MainColumn/NextLevelButton

# --- BBCode Templates ---
# connected=1 ensures the wave flows smoothly across the whole sentence
const WAVE_TAG = "[wave amp=10.0 freq=4.0 connected=1]"
const END_WAVE = "[/wave]"

func _ready() -> void:
	visible = false
	next_level_button.pressed.connect(_on_next_level_pressed)

func show_score() -> void:
	visible = true
	get_tree().paused = true # Freezes the 3D world
	
	# Unlock the mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
# Smoothly fade CRT ColorRect down to 25% opacity
	var crt = get_tree().root.find_child("crtshader", true, false)
	if crt:
		crt.visible = true
		var crt_rect = crt.find_child("ColorRect", true, false)
		if crt_rect:
			# 1. Create a tween specifically for the CRT fade
			var crt_tween = create_tween()
			
			# 2. IMPORTANT: Tell it to run even though the game is paused!
			crt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			
			# 3. Fade the alpha from whatever it is right now down to 0.25 over 0.5 seconds
			crt_tween.tween_property(crt_rect, "modulate:a", 0.55, 0.5)
	
	# 1. Reset Opacities for Animation
	_reset_opacities()
	
	# 2. Clear out any old rows from previous levels
	for child in grid.get_children():
		child.queue_free()
		
	# 3. Create the Headers
	_add_grid_row("ACTION", "FREQ", "SCORE")
	
	# 4. Dynamically add rows based on player performance
	if ScoreManager.cones_collected > 0:
		_add_grid_row("Cones Collected", str(ScoreManager.cones_collected), str(ScoreManager.cones_collected * ScoreManager.CONE_VAL))
	if ScoreManager.cubes_collected > 0:
		_add_grid_row("Cubes Collected", str(ScoreManager.cubes_collected), str(ScoreManager.cubes_collected * ScoreManager.CUBE_VAL))
	if ScoreManager.spheres_collected > 0:
		_add_grid_row("Spheres Collected", str(ScoreManager.spheres_collected), str(ScoreManager.spheres_collected * ScoreManager.SPHERE_VAL))
	if ScoreManager.enemies_stunned > 0:
		_add_grid_row("Enemies Stunned", str(ScoreManager.enemies_stunned), str(ScoreManager.enemies_stunned * ScoreManager.STUN_VAL))
	if ScoreManager.times_caught > 0:
		# Adding a red color tag specifically for penalties
		_add_grid_row("[color=red]Times Caught[/color]", str(ScoreManager.times_caught), "[color=red]" + str(ScoreManager.times_caught * ScoreManager.CAUGHT_VAL) + "[/color]")
	if ScoreManager.time_left > 0:
		_add_grid_row("Time Bonus", str(ScoreManager.time_left) + "s", str(ScoreManager.time_left))
		
	# 5. Set the Static Titles/Totals with Wave BBCode
	title_label.text = "[center]" + WAVE_TAG + "LEVEL COMPLETE" + END_WAVE + "[/center]"
	level_total_label.text = "[center]" + WAVE_TAG + "LEVEL SCORE: " + str(ScoreManager.level_score) + END_WAVE + "[/center]"
	overall_total_label.text = "[center]" + WAVE_TAG + "TOTAL OVERALL SCORE: " + str(ScoreManager.total_overall_score) + END_WAVE + "[/center]"
	
	# 6. Kick off the staggered animation sequence
	play_entrance_animations()
	
	# 7. Wipe the level stats clean for the next map
	ScoreManager.reset_level_stats()


# --- Helper: Dynamically builds RichTextLabels with BBCode ---
func _add_grid_row(col1_text: String, col2_text: String, col3_text: String) -> void:
	var texts = [col1_text, col2_text, col3_text]
	
	for i in range(3):
		var r_label = RichTextLabel.new()
		r_label.bbcode_enabled = true
		r_label.fit_content = true
		r_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		r_label.custom_minimum_size.x = 180 # Ensures neat columns
		
		# Start fully transparent for the animation
		r_label.modulate.a = 0.0 
		
		# Apply formatting: Left-align the first column, Right-align the numbers
		var align_start = "[left]" if i == 0 else "[right]"
		var align_end = "[/left]" if i == 0 else "[/right]"
		
		r_label.text = align_start + WAVE_TAG + texts[i] + END_WAVE + align_end
		grid.add_child(r_label)


# --- Animation Logic ---
func _reset_opacities() -> void:
	# Hide everything before the animation starts
	background.modulate.a = 0.0
	title_label.modulate.a = 0.0
	divider1.modulate.a = 0.0
	divider2.modulate.a = 0.0
	level_total_label.modulate.a = 0.0
	overall_total_label.modulate.a = 0.0
	next_level_button.modulate.a = 0.0
	next_level_button.disabled = true

func play_entrance_animations() -> void:
	var tween = create_tween()
	# IMPORTANT: Tell the tween it is allowed to run while the game is paused
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
	
	# 1. Fade in the background first
	tween.tween_property(background, "modulate:a", 1.0, 0.4)
	
	# 2. Fade in Title and Top Divider
	tween.tween_property(title_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(divider1, "modulate:a", 1.0, 0.2)
	
	# 3. Fade in Grid Rows sequentially (staggered by row)
	var children = grid.get_children()
	for i in range(0, children.size(), 3):
		# tween.parallel() makes the 3 columns of the current row fade in together
		tween.parallel().tween_property(children[i], "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(children[i+1], "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(children[i+2], "modulate:a", 1.0, 0.2)
		# tween.chain() waits for the row to finish, then adds a tiny delay before the next row
		tween.chain().tween_interval(0.1)
		
	# 4. Fade Bottom Elements
	tween.tween_property(divider2, "modulate:a", 1.0, 0.2)
	tween.tween_property(level_total_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(overall_total_label, "modulate:a", 1.0, 0.3)
	
	# 5. Fade Button
	tween.tween_interval(0.2)
	tween.tween_property(next_level_button, "modulate:a", 1.0, 0.4)
	
	# 6. Unlock the button ONLY when everything is done
	tween.finished.connect(_on_animations_finished)

func _on_animations_finished() -> void:
	next_level_button.disabled = false


# --- Button Press ---
func _on_next_level_pressed() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Restore CRT overlay back to 100% strength
	var crt = get_tree().root.find_child("crtshader", true, false)
	if crt:
		crt.visible = true
		var crt_rect = crt.find_child("ColorRect", true, false)
		if crt_rect:
			crt_rect.modulate.a = 1.0
		
	get_tree().paused = false
