extends Control

# Direct path to your main game level
@export_file("*.tscn") var main_level_scene: String = "res://MainLevel.tscn"

# Retro Audio Streams (Drag audio files into these slots in the Inspector)
@export var hover_sound: AudioStream
@export var click_sound: AudioStream

# Disclaimers & Transition config
@export var disclaimer_display_time: float = 2.5
@export var disclaimer_fade_time: float = 0.6
@export var scene_transition_fade_time: float = 1.0  # Slow fade out duration when PLAY is clicked
@export var fade_steps: int = 4  # Lower steps = choppier retro fade (PS1 style)

const DISCLAIMER_1 := "All features of this build are subject to change.\nThis is a prototype."
const DISCLAIMER_2 := "WARNING:\nThis game contains disturbing imagery and loud noises."
const CONTROLS_TEXT := "CONTROLS:\nWASD - Movement\nShift - Sprint\nLeft Click - Snap\nSpace - Jump\n* Note: Timed jumps result in bhopping"

# Accessing nodes uniquely using % prevents path mismatch errors
@onready var disclaimer_layer: Control = %DisclaimerLayer
@onready var disclaimer_bg: ColorRect = %DisclaimerBackground
@onready var disclaimer_label: Label = %DisclaimerLabel

@onready var menu_layer: Control = %MenuLayer
@onready var play_button: Button = %PlayButton
@onready var exit_button: Button = %ExitButton

# Internal Audio Player & Controls Reference
var _audio_player: AudioStreamPlayer
var controls_label: Label
var _is_transitioning: bool = false


func _ready() -> void:
	# Setup internal audio player
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	# Hide menu & show disclaimers initially
	menu_layer.visible = false
	disclaimer_layer.visible = true
	
	# Create controls label programmatically inside MenuLayer
	_create_controls_label()
	
	# Assign retro button styles and connect sound signals
	_style_buttons_retro()
	
	disclaimer_label.add_theme_font_size_override("font_size", 36)
	
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	_run_disclaimer_sequence()


func _run_disclaimer_sequence() -> void:
	disclaimer_label.modulate.a = 0.0

	# --- Disclaimer 1 ---
	disclaimer_label.text = DISCLAIMER_1
	await _stepped_fade(disclaimer_label, 0.0, 1.0)
	await get_tree().create_timer(disclaimer_display_time).timeout
	await _stepped_fade(disclaimer_label, 1.0, 0.0)

	# --- Disclaimer 2 ---
	disclaimer_label.text = DISCLAIMER_2
	await _stepped_fade(disclaimer_label, 0.0, 1.0)
	await get_tree().create_timer(disclaimer_display_time).timeout
	await _stepped_fade(disclaimer_label, 1.0, 0.0)

	# --- Stepped Fade Out Background ---
	await _stepped_fade_bg(disclaimer_bg, 1.0, 0.0)

	# Disclaimers done: show full menu layer (buttons + controls text)
	disclaimer_layer.visible = false
	menu_layer.visible = true


# Dynamically creates a bold, CRT-shader resistant controls display anchored strictly to bottom-left
func _create_controls_label() -> void:
	controls_label = Label.new()
	controls_label.text = CONTROLS_TEXT
	
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	controls_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	
	# Enable text wrapping and set minimum width box to prevent squishing text
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.custom_minimum_size = Vector2(450, 0)
	
	# Heavy font weighting for CRT legibility (900 = Heavy/Black)
	var bold_font := SystemFont.new()
	bold_font.font_weight = 900
	controls_label.add_theme_font_override("font", bold_font)
	controls_label.add_theme_font_size_override("font_size", 20)
	controls_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Thick black outline for sharp legibility through CRT scanlines
	controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	controls_label.add_theme_constant_override("outline_size", 6)
	
	menu_layer.add_child(controls_label)
	
	# Lock anchors strictly to Bottom-Left
	controls_label.anchor_left = 0.0
	controls_label.anchor_top = 1.0
	controls_label.anchor_right = 0.0
	controls_label.anchor_bottom = 1.0
	
	# Position with a 30px padding from the bottom-left edge
	controls_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_label.position = Vector2(30, get_viewport_rect().size.y - 30 - controls_label.get_minimum_size().y)


# Creates sharp, unrounded buttons with extra bold white text and a subtle dark hover effect
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

	var bold_font := SystemFont.new()
	bold_font.font_weight = 900 

	play_button.text = "PLAY"
	exit_button.text = "EXIT"

	var buttons: Array[Button] = [play_button, exit_button]
	
	for btn in buttons:
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("focus", style_focus)
		
		btn.add_theme_font_override("font", bold_font)
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


# Custom stepped opacity animation for retro PS1 look
func _stepped_fade(node: CanvasItem, start_alpha: float, end_alpha: float, duration: float = disclaimer_fade_time) -> void:
	var step_delay := duration / float(fade_steps)
	for i in range(fade_steps + 1):
		var t := float(i) / float(fade_steps)
		node.modulate.a = lerp(start_alpha, end_alpha, t)
		await get_tree().create_timer(step_delay).timeout


func _stepped_fade_bg(rect: ColorRect, start_alpha: float, end_alpha: float, duration: float = disclaimer_fade_time) -> void:
	var step_delay := duration / float(fade_steps)
	var current_color := rect.color
	for i in range(fade_steps + 1):
		var t := float(i) / float(fade_steps)
		current_color.a = lerp(start_alpha, end_alpha, t)
		rect.color = current_color
		await get_tree().create_timer(step_delay).timeout


# ============================================================
# BUTTON CALLBACKS
# ============================================================
func _on_play_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	if main_level_scene != "":
		# Slow stepped fade out of the entire menu layer before changing scene
		await _stepped_fade(menu_layer, 1.0, 0.0, scene_transition_fade_time)
		get_tree().change_scene_to_file(main_level_scene)
	else:
		push_error("Main Menu: Main level scene file path is missing!")


func _on_exit_pressed() -> void:
	if _is_transitioning:
		return
	get_tree().quit()
