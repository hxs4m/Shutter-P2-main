extends Control

# --- Custom Font Export ---
@export var custom_font: Font

# --- Default Values ---
const DEFAULT_FOV: float = 75.0
const DEFAULT_SENS: float = 0.004
const DEFAULT_AUDIO: float = 1.0 # 100% volume

# --- Node Mapping ---
@onready var fov_slider: HSlider = $MarginContainer/MainVBox/TabContainer/GamePlay/FovRow/HSlider
@onready var fov_value_label: Label = $MarginContainer/MainVBox/TabContainer/GamePlay/FovRow/ValueLabel

@onready var sens_slider: HSlider = $MarginContainer/MainVBox/TabContainer/GamePlay/SenstivityRow/HSlider
@onready var sens_value_label: Label = $MarginContainer/MainVBox/TabContainer/GamePlay/SenstivityRow/ValueLabel

@onready var audio_slider: HSlider = $MarginContainer/MainVBox/TabContainer/Audio/VolumeRow/Master
@onready var audio_value_label: Label = $MarginContainer/MainVBox/TabContainer/Audio/VolumeRow/ValueLabel

@onready var display_option: OptionButton = $MarginContainer/MainVBox/TabContainer/Video/DisplayModeRow/OptionButton
@onready var res_option: OptionButton = $MarginContainer/MainVBox/TabContainer/Video/ResolutionRow/OptionButton
@onready var vsync_check: CheckBox = $MarginContainer/MainVBox/TabContainer/Video/VsyncRow/CheckBox

@onready var reset_button: Button = $MarginContainer/MainVBox/ResetButton
@onready var back_button: Button = $MarginContainer/MainVBox/BackButton


func _ready() -> void:
	pivot_offset = size / 2.0
	modulate.a = 0.0
	scale = Vector2(0.95, 0.95)
	hide()
	
	if custom_font:
		_apply_custom_font_recursive(self)
	
	if reset_button:
		reset_button.pressed.connect(_on_reset_defaults_pressed)
	if back_button:
		back_button.pressed.connect(close_menu)


# Traverses the entire node tree of this menu and applies custom_font to all UI elements
func _apply_custom_font_recursive(node: Node) -> void:
	if not custom_font:
		return

	if node is Control:
		node.add_theme_font_override("font", custom_font)

	# Handle OptionButton dropdown popups separately as they exist as external PopupMenus
	if node is OptionButton:
		var popup = node.get_popup()
		if popup:
			popup.add_theme_font_override("font", custom_font)

	for child in node.get_children():
		_apply_custom_font_recursive(child)


func _get_player() -> Node:
	var players = get_tree().get_nodes_in_group("PlayerGroup")
	return players[0] if players.size() > 0 else null


func open_menu() -> void:
	_sync_ui_to_current_settings()
	show()
	var tween = create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func close_menu() -> void:
	var tween = create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.2).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(hide)


func _sync_ui_to_current_settings() -> void:
	# 1. Sync Gameplay
	var player = _get_player()
	if player:
		_update_fov(player.BASE_FOV)
		_update_sens(player.SENSITIVITY)

	# 2. Sync Audio
	var master_idx = AudioServer.get_bus_index("Master")
	var current_db = AudioServer.get_bus_volume_db(master_idx)
	var linear_vol = db_to_linear(current_db)
	_update_audio(linear_vol)

	# 3. Sync Video
	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		display_option.select(0)
	elif current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		display_option.select(1)
	elif current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		display_option.select(2)

	var vsync_mode = DisplayServer.window_get_vsync_mode()
	vsync_check.set_pressed_no_signal(vsync_mode == DisplayServer.VSYNC_ENABLED)


# --- Dynamic Updates & Label Formatters ---
func _update_fov(val: float) -> void:
	fov_slider.set_value_no_signal(val)
	fov_value_label.text = str(round(val))
	var player = _get_player()
	if player:
		player.BASE_FOV = val


func _update_sens(val: float) -> void:
	sens_slider.set_value_no_signal(val)
	sens_value_label.text = str(snapped(val, 0.0001))
	var player = _get_player()
	if player:
		player.SENSITIVITY = val


func _update_audio(val: float) -> void:
	audio_slider.set_value_no_signal(val)
	audio_value_label.text = str(round(val * 100)) + "%"
	
	var master_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_idx, linear_to_db(val))
	AudioServer.set_bus_mute(master_idx, val < 0.01)


# --- Signal Connections ---
func _on_fov_slider_value_changed(value: float) -> void:
	_update_fov(value)


func _on_sensitivity_slider_value_changed(value: float) -> void:
	_update_sens(value)


func _on_master_volume_slider_value_changed(value: float) -> void:
	_update_audio(value)


func _on_display_mode_option_item_selected(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_resolution_option_item_selected(index: int) -> void:
	var new_size = Vector2i(1920, 1080)
	match index:
		0: new_size = Vector2i(1280, 720)
		1: new_size = Vector2i(1920, 1080)
		2: new_size = Vector2i(2560, 1440)
		3: new_size = Vector2i(3840, 2160)

	DisplayServer.window_set_size(new_size)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var current_screen = DisplayServer.window_get_current_screen()
		var screen_size = DisplayServer.screen_get_size(current_screen)
		var screen_pos = DisplayServer.screen_get_position(current_screen)
		DisplayServer.window_set_position(screen_pos + (screen_size / 2) - (new_size / 2))


func _on_vsync_checkbox_toggled(button_pressed: bool) -> void:
	var mode = DisplayServer.VSYNC_ENABLED if button_pressed else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


# --- Full Reset to Defaults ---
func _on_reset_defaults_pressed() -> void:
	# Reset Gameplay
	_update_fov(DEFAULT_FOV)
	_update_sens(DEFAULT_SENS)
	
	# Reset Audio
	_update_audio(DEFAULT_AUDIO)
	
	# Reset Video
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	
	display_option.select(0)
	res_option.select(1)
	vsync_check.set_pressed_no_signal(false)
