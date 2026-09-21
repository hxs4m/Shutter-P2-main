extends CanvasLayer

@export_group("Pause Restrictions")
## File paths for scenes where pausing is disabled (e.g., res://scenes/MainMenuScene.tscn)
@export var disabled_scenes: Array[String] = [
	"res://scenes/MainMenuScene.tscn"
]

## Enable if you prefer Whitelist mode (only scenes listed in allowed_scenes can be paused)
@export var use_whitelist_mode: bool = false
@export var allowed_scenes: Array[String] = []

@onready var continue_btn: Button = $MarginContainer/VBoxContainer/ContinueButton
@onready var settings_btn: Button = $MarginContainer/VBoxContainer/SettingsButton
@onready var back_btn: Button = $MarginContainer/VBoxContainer/BackToMenuButton
@onready var quit_btn: Button = $MarginContainer/VBoxContainer/QuitGameButton

# Reference to the instantiated SettingsMenu scene
@onready var settings_menu: Control = $SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	
	continue_btn.pressed.connect(_on_continue_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	back_btn.pressed.connect(_on_back_to_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Block input if the current active scene is not allowed to pause
		if not is_pause_allowed():
			return

		get_viewport().set_input_as_handled()
		
		# If the settings menu is open, close settings first
		if is_instance_valid(settings_menu) and settings_menu.visible:
			if settings_menu.has_method("close_menu"):
				settings_menu.close_menu()
			else:
				settings_menu.hide()
		else:
			toggle_pause()


func is_pause_allowed() -> bool:
	var current_scene = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return false

	# 1. Group check: Adding the root node of any scene to the "no_pause" group will block pausing
	if current_scene.is_in_group("no_pause"):
		return false

	# 2. Path-based check
	var current_path = current_scene.scene_file_path

	if use_whitelist_mode:
		return current_path in allowed_scenes
	else:
		return not (current_path in disabled_scenes)


func toggle_pause() -> void:
	# Prevent pausing if called directly via code in an unpauseable scene
	if not get_tree().paused and not is_pause_allowed():
		return

	var is_paused = not get_tree().paused
	get_tree().paused = is_paused
	
	if is_paused:
		show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if is_instance_valid(settings_menu) and settings_menu.visible:
			settings_menu.hide()
		hide()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_continue_pressed() -> void:
	toggle_pause()


func _on_settings_pressed() -> void:
	if is_instance_valid(settings_menu):
		if settings_menu.has_method("open_menu"):
			settings_menu.open_menu()
		else:
			settings_menu.show()


func _on_back_to_menu_pressed() -> void:
	get_tree().paused = false
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/MainMenuScene.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
