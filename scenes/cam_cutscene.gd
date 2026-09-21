extends CanvasLayer

@export_group("Timing & Delays")
@export var initial_delay: float = 0.5     # Delay before the first message appears
@export var line_delay: float = 0.8        # Delay between subsequent messages appearing

@export_group("Fade Settings")
@export var fade_duration: float = 0.8
@export var fade_steps: int = 4            # Stepped PS1-style increments (e.g. 4 steps = 100%, 75%, 50%, 25%, 0%)

@export_group("Audio")
@export var chad_sfx: AudioStream
@export var system_sfx: AudioStream
@export_range(0.0, 1.0) var sfx_volume: float = 1.0

@export_group("Chat Appearance")
@export var font: Font
@export var font_size: int = 15
@export var bottom_margin: int = 220
@export var left_margin: int = 20
@export var line_spacing: int = 4
@export var text_fade_time: float = 0.2

@export_group("Colors")
@export var chad_color: Color = Color(0.4, 0.65, 1.0)
@export var system_color: Color = Color(1.0, 0.65, 0.15)
@export var message_color: Color = Color(1.0, 1.0, 1.0)
@export var shadow_color: Color = Color(0, 0, 0, 0.9)

var vbox: VBoxContainer
var chad_player: AudioStreamPlayer
var system_player: AudioStreamPlayer
var _waiting_for_c: bool = false
var _is_dismissing: bool = false


func _ready() -> void:
	add_to_group("dialogue_box")
	_build_ui()
	_setup_audio()
	_play_sequence()


func _input(event: InputEvent) -> void:
	if _waiting_for_c and not _is_dismissing:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_C:
				_stepped_fade_out()


func _play_sequence() -> void:
	# 1. Initial delay before Chad speaks
	if initial_delay > 0.0:
		await get_tree().create_timer(initial_delay, false).timeout
		if _is_dismissing:
			return

	# 2. Chad says "Wow..."
	_add_chat_line("Chad", "Wow...")
	
	# 3. Delay before showing the system prompt
	if line_delay > 0.0:
		await get_tree().create_timer(line_delay, false).timeout
		if _is_dismissing:
			return

	# 4. SYSTEM line appears
	_add_chat_line("SYSTEM", "Press C to lower camera.")
	
	# 5. Wait for player input
	_waiting_for_c = true


func _add_chat_line(speaker: String, text: String) -> void:
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

	if speaker == "Chad":
		l.text = "[b][color=%s]Chad:[/color][/b] %s" % [_color_hex(chad_color), text]
		_play_sound(chad_sfx, chad_player)
	else:
		l.text = "[b][color=%s][%s][/color][/b] %s" % [_color_hex(system_color), speaker, text]
		_play_sound(system_sfx, system_player)

	l.modulate.a = 0.0
	vbox.add_child(l)

	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, text_fade_time)


func _stepped_fade_out() -> void:
	_is_dismissing = true
	_waiting_for_c = false

	var steps := maxi(1, fade_steps)
	var step_delay := fade_duration / float(steps)

	for i in range(steps, -1, -1):
		vbox.modulate.a = float(i) / float(steps)
		await get_tree().create_timer(step_delay, true, false, true).timeout

	queue_free()


func _play_sound(stream: AudioStream, player: AudioStreamPlayer) -> void:
	if stream == null or player == null:
		return
	player.volume_db = linear_to_db(clampf(sfx_volume, 0.0001, 1.0))
	player.play()


func _build_ui() -> void:
	var holder := MarginContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_left", left_margin)
	holder.add_theme_constant_override("margin_bottom", bottom_margin)
	add_child(holder)

	vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", line_spacing)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_END
	holder.add_child(vbox)


func _setup_audio() -> void:
	chad_player = AudioStreamPlayer.new()
	chad_player.stream = chad_sfx
	add_child(chad_player)

	system_player = AudioStreamPlayer.new()
	system_player.stream = system_sfx
	add_child(system_player)


func _color_hex(c: Color) -> String:
	return "#" + c.to_html(false)
