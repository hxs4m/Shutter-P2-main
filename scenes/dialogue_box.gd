extends CanvasLayer

@export_group("Audio")
@export var enter_sound: AudioStream
@export_range(0.0, 1.0) var sfx_volume: float = 1.0

@export_group("Chat Appearance")
@export var font: Font
@export var font_size: int = 15
@export var bottom_margin: int = 220
@export var left_margin: int = 20
@export var line_spacing: int = 4
@export var fade_time: float = 0.2
@export var sub_delay: float = 0.8

@export_group("Speakers & Colors")
@export var player_name: String = "Chad"
@export var player_name_color: Color = Color(0.4, 0.65, 1.0)
@export var console_name: String = "GAME"
@export var console_name_color: Color = Color(1.0, 0.65, 0.15)
@export var message_color: Color = Color(1.0, 1.0, 1.0)
@export var shadow_color: Color = Color(0, 0, 0, 0.9)

var vbox: VBoxContainer
var sfx_player: AudioStreamPlayer
var _is_dismissed: bool = false


func _ready() -> void:
	add_to_group("dialogue_box")
	_build_ui()
	_setup_audio()
	
	# Play Level 4 sequence on start
	_play_level_4_sequence()


func _input(event: InputEvent) -> void:
	if _is_dismissed:
		return

	# Dismiss chat when player presses 'C'
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_C:
			dismiss_dialogue()


func _play_level_4_sequence() -> void:
	# 1. Chad speaks
	_add_chat_line(player_name, player_name_color, "Wow...")
	_play_sound()

	# 2. Wait delay before prompt
	await get_tree().create_timer(sub_delay, false).timeout
	if _is_dismissed:
		return

	# 3. Console prompt appears
	_add_chat_line(console_name, console_name_color, "Press C to lower camera", true)
	_play_sound()


func _add_chat_line(speaker: String, color: Color, text: String, is_console: bool = false) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

	l.add_theme_font_size_override("normal_font_size", font_size)
	l.add_theme_font_size_override("bold_font_size", font_size)
	l.add_theme_color_override("default_color", message_color)
	l.add_theme_color_override("font_shadow_color", shadow_color)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)

	if font:
		l.add_theme_font_override("normal_font", font)
		l.add_theme_font_override("bold_font", font)

	if is_console:
		l.text = "[b][color=%s][%s][/color][/b] %s" % [_color_hex(color), speaker, text]
	else:
		l.text = "[b][color=%s]%s:[/color][/b] %s" % [_color_hex(color), speaker, text]

	l.modulate.a = 0.0
	vbox.add_child(l)

	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, fade_time)


func dismiss_dialogue() -> void:
	if _is_dismissed:
		return
	_is_dismissed = true

	var tw := create_tween()
	tw.tween_property(vbox, "modulate:a", 0.0, fade_time)
	await tw.finished
	queue_free()


func _play_sound() -> void:
	if enter_sound and sfx_player:
		sfx_player.stream = enter_sound
		sfx_player.volume_db = linear_to_db(clampf(sfx_volume, 0.0001, 1.0))
		sfx_player.play()


# --- Public API Compatibility ---

func show_message(main_text: String, sub_text: String = "") -> void:
	for child in vbox.get_children():
		child.queue_free()
	_is_dismissed = false
	vbox.modulate.a = 1.0

	_add_chat_line(player_name, player_name_color, main_text)
	_play_sound()

	if sub_text != "":
		await get_tree().create_timer(sub_delay, false).timeout
		if not _is_dismissed:
			_add_chat_line(console_name, console_name_color, sub_text, true)
			_play_sound()


func hide_message() -> void:
	dismiss_dialogue()


# --- UI Setup ---

func _build_ui() -> void:
	var holder := MarginContainer.new()
	holder.name = "ChatHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_left", left_margin)
	holder.add_theme_constant_override("margin_bottom", bottom_margin)
	add_child(holder)

	vbox = VBoxContainer.new()
	vbox.name = "ChatLines"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", line_spacing)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_END
	holder.add_child(vbox)


func _setup_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SFX"
	add_child(sfx_player)


func _color_hex(c: Color) -> String:
	return "#" + c.to_html(false)
