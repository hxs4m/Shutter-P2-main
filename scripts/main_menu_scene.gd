extends Control

# Direct path to your main game level
@export_file("*.tscn") var main_level_scene: String = "res://MainLevel.tscn"

# Main Menu Background Music (Assign your AudioStreamPlayer in the Inspector)
@export var menu_music: AudioStreamPlayer

# Retro Audio Streams (Drag audio files into these slots in the Inspector)
@export var hover_sound: AudioStream
@export var click_sound: AudioStream

@export_group("Typography")
@export var custom_font: Font

# Headphone Icon for Disclaimer 1
@export_group("Disclaimer Assets")
@export var headphone_texture: Texture2D
@export var headphone_icon_size: Vector2 = Vector2(128, 128)
@export var headphone_vertical_offset: float = -140.0 # Height relative to Disclaimer 1 text

# Customizable Text Content
@export_group("Text Configuration")
@export_multiline var disclaimer_1_text: String = "The Usage Of Headphones Is Advised."
@export_multiline var disclaimer_2_text: String = "WARNING:\nThis game contains disturbing imagery and loud noises."
@export_multiline var controls_text: String = "CONTROLS:\nWASD - Movement\nShift - Sprint\nSpace - Jump\n* Note: Timed jumps result in bhopping\nLClick - Snap Picture\nRClick - Zoom\nQ & E - Cycle Modes\nC - Lower Camera\n"

@export_subgroup("Button Text")
@export var play_button_text: String = "PLAY"
@export var settings_button_text: String = "SETTINGS"
@export var credits_button_text: String = "CREDITS"
@export var controls_button_text: String = "CONTROLS"
@export var exit_button_text: String = "EXIT"

# Disclaimers & Transition config
@export_group("Disclaimer Settings")
@export var disclaimer_display_time: float = 2.5
@export var disclaimer_fade_time: float = 0.6
@export var scene_transition_fade_time: float = 1.5 # Duration of slow transition fade
@export var scene_transition_fade_steps: int = 8    # Number of discrete steps for PLAY transition
@export var fade_steps: int = 4                      # Steps used during disclaimer text fades
@export var disclaimer_1_vertical_offset: float = 60.0 # Push Disclaimer 1 + Headphone down/up
@export var disclaimer_2_vertical_offset: float = 0.0  # Move Disclaimer 2 independently

@export_group("Credits Settings")
@export_range(0.0, 1.0) var credits_overlay_opacity: float = 0.85
@export_multiline var credits_text: String = "CREDITS\n\nPut your names here\nThanks for playing"

# Accessing nodes uniquely using % prevents path mismatch errors
@onready var disclaimer_layer: Control = %DisclaimerLayer
@onready var disclaimer_bg: ColorRect = %DisclaimerBackground
@onready var disclaimer_label: Label = %DisclaimerLabel

@onready var menu_layer: Control = %MenuLayer
@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var credits_button: Button = %CreditsButton
@onready var controls_button: Button = %ControlsButton
@onready var exit_button: Button = %ExitButton

@onready var settings_menu: Control = %SettingsMenu
@onready var credits_menu: Control = %CreditsMenu

# Internal Audio Player & Controls Reference
var _audio_player: AudioStreamPlayer
var controls_label: Label
var headphone_rect: TextureRect
var _is_transitioning: bool = false
var _in_disclaimer_sequence: bool = false
var _skipped_disclaimers: bool = false


func _ready() -> void:
	# Setup internal audio player for button SFX
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	# Hide menu & show disclaimers initially
	menu_layer.visible = false
	disclaimer_layer.visible = true
	
	if settings_menu:
		settings_menu.visible = false
	if credits_menu:
		credits_menu.visible = false
	
	# Apply global font to pre-existing disclaimer label if set
	if custom_font:
		disclaimer_label.add_theme_font_override("font", custom_font)
	
	# Initial label anchor setup
	_setup_disclaimer_label_anchors()
	
	# Create programmatic UI elements
	_create_headphone_icon()
	_create_controls_label()
	_setup_credits_ui()
	
	# Assign retro button styles and connect sound signals
	_style_buttons_retro()
	
	disclaimer_label.add_theme_font_size_override("font_size", 36)
	
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	# Automatically hook up the settings Back button to return to Main Menu
	if settings_menu:
		var back_btn = settings_menu.find_child("BackButton", true, false)
		if back_btn:
			back_btn.pressed.connect(_on_settings_closed)

	_run_disclaimer_sequence()


# Base centering setup for disclaimer label
func _setup_disclaimer_label_anchors() -> void:
	disclaimer_label.set_anchors_preset(Control.PRESET_CENTER)
	disclaimer_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	disclaimer_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	disclaimer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disclaimer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# Updates the label's vertical position based on active offset
func _set_disclaimer_vertical_offset(offset: float) -> void:
	disclaimer_label.offset_top = offset
	disclaimer_label.offset_bottom = offset


# Detect double clicks on any mouse button to skip disclaimers
func _input(event: InputEvent) -> void:
	if _in_disclaimer_sequence and not _skipped_disclaimers:
		if event is InputEventMouseButton and event.pressed and event.double_click:
			_skip_disclaimers()


# Instantly cancels disclaimers and displays the main menu
func _skip_disclaimers() -> void:
	_skipped_disclaimers = true
	_in_disclaimer_sequence = false
	
	disclaimer_layer.visible = false
	if headphone_rect:
		headphone_rect.visible = false
		headphone_rect.modulate.a = 0.0
		
	disclaimer_bg.color.a = 0.0
	
	menu_layer.visible = true
	menu_layer.modulate.a = 1.0


func _run_disclaimer_sequence() -> void:
	_in_disclaimer_sequence = true
	disclaimer_label.modulate.a = 0.0

	# --- Disclaimer 1 ---
	_set_disclaimer_vertical_offset(disclaimer_1_vertical_offset)
	disclaimer_label.text = disclaimer_1_text
	
	if headphone_rect and headphone_texture:
		headphone_rect.visible = true
		headphone_rect.modulate.a = 0.0

	await _stepped_fade_multi([disclaimer_label, headphone_rect], 0.0, 1.0)
	if _skipped_disclaimers: return
	
	await get_tree().create_timer(disclaimer_display_time).timeout
	if _skipped_disclaimers: return
	
	await _stepped_fade_multi([disclaimer_label, headphone_rect], 1.0, 0.0)
	if _skipped_disclaimers: return

	if headphone_rect:
		headphone_rect.visible = false

	# --- Disclaimer 2 ---
	_set_disclaimer_vertical_offset(disclaimer_2_vertical_offset)
	disclaimer_label.text = disclaimer_2_text
	await _stepped_fade(disclaimer_label, 0.0, 1.0)
	if _skipped_disclaimers: return
	
	await get_tree().create_timer(disclaimer_display_time).timeout
	if _skipped_disclaimers: return
	
	await _stepped_fade(disclaimer_label, 1.0, 0.0)
	if _skipped_disclaimers: return

	# --- Stepped Fade Out Background ---
	await _stepped_fade_bg(disclaimer_bg, 1.0, 0.0)
	if _skipped_disclaimers: return

	# Disclaimers done: show full menu layer
	_in_disclaimer_sequence = false
	disclaimer_layer.visible = false
	menu_layer.visible = true


# Dynamically creates a headphone TextureRect relative to Disclaimer 1 offset
func _create_headphone_icon() -> void:
	if not headphone_texture:
		return
		
	headphone_rect = TextureRect.new()
	headphone_rect.name = "HeadphoneIcon"
	headphone_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	headphone_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	headphone_rect.custom_minimum_size = headphone_icon_size
	headphone_rect.texture = headphone_texture
		
	disclaimer_layer.add_child(headphone_rect)
	
	headphone_rect.set_anchors_preset(Control.PRESET_CENTER)
	headphone_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	headphone_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var half_w := headphone_icon_size.x / 2.0
	var half_h := headphone_icon_size.y / 2.0
	var total_vertical_offset := disclaimer_1_vertical_offset + headphone_vertical_offset
	
	headphone_rect.offset_left = -half_w
	headphone_rect.offset_right = half_w
	headphone_rect.offset_top = total_vertical_offset - half_h
	headphone_rect.offset_bottom = total_vertical_offset + half_h
	
	headphone_rect.modulate.a = 0.0
	headphone_rect.visible = false


# Dynamically creates a bold controls display anchored strictly to bottom-left
func _create_controls_label() -> void:
	controls_label = Label.new()
	controls_label.text = controls_text
	
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	controls_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.custom_minimum_size = Vector2(450, 0)
	
	var font_to_use: Font = custom_font if custom_font else SystemFont.new()
	if font_to_use is SystemFont:
		font_to_use.font_weight = 900
		
	controls_label.add_theme_font_override("font", font_to_use)
	controls_label.add_theme_font_size_override("font_size", 20)
	controls_label.add_theme_color_override("font_color", Color.WHITE)
	
	controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	controls_label.add_theme_constant_override("outline_size", 6)
	
	menu_layer.add_child(controls_label)
	
	controls_label.anchor_left = 0.0
	controls_label.anchor_top = 1.0
	controls_label.anchor_right = 0.0
	controls_label.anchor_bottom = 1.0
	
	controls_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_label.position = Vector2(30, get_viewport_rect().size.y - 30 - controls_label.get_minimum_size().y)
	
	controls_label.visible = false


func _setup_credits_ui() -> void:
	if not credits_menu:
		return
		
	credits_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
	var dark_overlay := ColorRect.new()
	dark_overlay.color = Color(0, 0, 0, credits_overlay_opacity)
	dark_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	credits_menu.add_child(dark_overlay)
	credits_menu.move_child(dark_overlay, 0)
	
	var credits_label := Label.new()
	credits_label.text = credits_text
	credits_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	var reg_font: Font = custom_font if custom_font else SystemFont.new()
	if reg_font is SystemFont:
		reg_font.font_weight = 400
		
	credits_label.add_theme_font_override("font", reg_font)
	credits_label.add_theme_font_size_override("font_size", 32)
	credits_label.add_theme_color_override("font_color", Color.WHITE)
	
	credits_menu.add_child(credits_label)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	close_btn.position = Vector2(30, 30)
	
	var style_empty := StyleBoxEmpty.new()
	var bold_font: Font = custom_font if custom_font else SystemFont.new()
	if bold_font is SystemFont:
		bold_font.font_weight = 900
	
	close_btn.add_theme_stylebox_override("normal", style_empty)
	close_btn.add_theme_stylebox_override("hover", style_empty)
	close_btn.add_theme_stylebox_override("pressed", style_empty)
	close_btn.add_theme_stylebox_override("focus", style_empty)
	
	close_btn.add_theme_font_override("font", bold_font)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.add_theme_color_override("font_hover_color", Color.RED)
	close_btn.add_theme_color_override("font_pressed_color", Color.DARK_RED)
	close_btn.add_theme_font_size_override("font_size", 48)
	
	close_btn.mouse_entered.connect(_play_sound.bind(hover_sound))
	close_btn.pressed.connect(_play_sound.bind(click_sound))
	close_btn.pressed.connect(_on_credits_closed)
	
	credits_menu.add_child(close_btn)


func _style_buttons_retro() -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0.0)
	style_normal.set_corner_radius_all(0)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0, 0, 0, 0.4)
	style_hover.set_corner_radius_all(0)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0, 0, 0, 0.7)
	style_pressed.set_corner_radius_all(0)

	var style_focus := StyleBoxEmpty.new()

	var btn_font: Font = custom_font if custom_font else SystemFont.new()
	if btn_font is SystemFont:
		btn_font.font_weight = 900

	play_button.text = play_button_text
	settings_button.text = settings_button_text
	credits_button.text = credits_button_text
	controls_button.text = controls_button_text
	exit_button.text = exit_button_text

	var buttons: Array[Button] = [play_button, settings_button, credits_button, controls_button, exit_button]
	
	for btn in buttons:
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("focus", style_focus)
		
		btn.add_theme_font_override("font", btn_font)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.LIGHT_GRAY)
		btn.add_theme_font_size_override("font_size", 36)

		# Sound triggers
		btn.mouse_entered.connect(_play_sound.bind(hover_sound))
		btn.pressed.connect(_play_sound.bind(click_sound))


func _play_sound(stream: AudioStream) -> void:
	if stream:
		_audio_player.stream = stream
		_audio_player.play()


# Custom stepped opacity animation using strict float interpolation lerpf()
func _stepped_fade(node: CanvasItem, start_alpha: float, end_alpha: float, duration: float = disclaimer_fade_time) -> void:
	var step_delay := duration / float(fade_steps)
	for i in range(fade_steps + 1):
		if _skipped_disclaimers: return
		var t := float(i) / float(fade_steps)
		node.modulate.a = lerpf(start_alpha, end_alpha, t)
		await get_tree().create_timer(step_delay).timeout


# Fades multiple nodes simultaneously
func _stepped_fade_multi(nodes: Array[CanvasItem], start_alpha: float, end_alpha: float, duration: float = disclaimer_fade_time) -> void:
	var step_delay := duration / float(fade_steps)
	for i in range(fade_steps + 1):
		if _skipped_disclaimers: return
		var t := float(i) / float(fade_steps)
		for node in nodes:
			if is_instance_valid(node):
				node.modulate.a = lerpf(start_alpha, end_alpha, t)
		await get_tree().create_timer(step_delay).timeout


func _stepped_fade_bg(rect: ColorRect, start_alpha: float, end_alpha: float, duration: float = disclaimer_fade_time) -> void:
	var step_delay := duration / float(fade_steps)
	var current_color := rect.color
	for i in range(fade_steps + 1):
		if _skipped_disclaimers: return
		var t := float(i) / float(fade_steps)
		current_color.a = lerpf(start_alpha, end_alpha, t)
		rect.color = current_color
		await get_tree().create_timer(step_delay).timeout


# Executes slow, stepped fade-out for UI elements and audio simultaneously
func _fade_out_scene_elements_stepped(ui_nodes: Array[CanvasItem], audio_node: AudioStreamPlayer, duration: float, steps: int) -> void:
	var step_delay := duration / float(steps)
	
	# Capture initial audio linear volume
	var start_volume_db := audio_node.volume_db if is_instance_valid(audio_node) else 0.0
	var start_linear := db_to_linear(start_volume_db)

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var current_alpha := lerpf(1.0, 0.0, t)

		# Stepped UI Opacity
		for node in ui_nodes:
			if is_instance_valid(node):
				node.modulate.a = current_alpha

		# Stepped Audio Decibel Fade
		if is_instance_valid(audio_node):
			var current_linear := lerpf(start_linear, 0.0, t)
			audio_node.volume_db = linear_to_db(current_linear)

		await get_tree().create_timer(step_delay).timeout


# ============================================================
# BUTTON CALLBACKS
# ============================================================
func _on_play_pressed() -> void:
	ScoreManager.total_overall_score = 0
	ScoreManager.level_score = 0
	ScoreManager.reset_level_stats()
	if _is_transitioning:
		return
	_is_transitioning = true

	if main_level_scene != "":
		# Gather active menu UI components
		var elements_to_fade: Array[CanvasItem] = [menu_layer]
		if is_instance_valid(controls_label):
			elements_to_fade.append(controls_label)

		# Perform slow stepped fade out for both UI and audio
		await _fade_out_scene_elements_stepped(
			elements_to_fade, 
			menu_music, 
			scene_transition_fade_time, 
			scene_transition_fade_steps
		)
		
		get_tree().change_scene_to_file(main_level_scene)
	else:
		push_error("Main Menu: Main level scene file path is missing!")


func _on_settings_pressed() -> void:
	if _is_transitioning:
		return
	
	menu_layer.visible = false
	settings_menu.visible = true
	if settings_menu.has_method("open_menu"):
		settings_menu.open_menu()


func _on_settings_closed() -> void:
	settings_menu.visible = false
	menu_layer.visible = true


func _on_credits_pressed() -> void:
	if _is_transitioning:
		return
	menu_layer.visible = false
	credits_menu.visible = true


func _on_credits_closed() -> void:
	credits_menu.visible = false
	menu_layer.visible = true


func _on_controls_pressed() -> void:
	if controls_label:
		controls_label.visible = !controls_label.visible


func _on_exit_pressed() -> void:
	if _is_transitioning:
		return
	get_tree().quit()
