extends CanvasLayer

@export_group("Scene Transition")
@export var next_level_scene: PackedScene
@export_file("*.tscn") var next_level_path: String
@export var fade_duration: float = 1.2
@export var fade_steps: int = 6

@export_group("Audio")
@export var chad_sfx: AudioStream
@export var janitor_sfx: AudioStream
@export var laughing_cat_sfx: AudioStream
@export_range(0.0, 1.0) var cat_sfx_volume: float = 1.0  # Slider exclusively for the laughing cat sound

@export_group("Special Attachments")
@export var cat_emoji_texture: Texture2D
@export var emoji_size: int = 32

@export_group("Chat Appearance")
@export var font: Font
@export var font_size: int = 15
@export var bottom_margin: int = 220
@export var left_margin: int = 20
@export var line_spacing: int = 4
@export var text_fade_time: float = 0.2

@export_group("Colors")
@export var chad_color: Color = Color(0.4, 0.65, 1.0)
@export var janitor_color: Color = Color(0.3, 0.8, 0.4)
@export var message_color: Color = Color(1.0, 1.0, 1.0)
@export var shadow_color: Color = Color(0, 0, 0, 0.9)

var dialogue_sequence: Array = []

var vbox: VBoxContainer
var chad_player: AudioStreamPlayer
var janitor_player: AudioStreamPlayer
var fade_rect: ColorRect
var skip_label: Label
var _is_transitioning: bool = false


func _ready() -> void:
	_setup_sequence_data()
	_build_ui()
	_setup_audio()
	_play_sequence()


func _setup_sequence_data() -> void:
	dialogue_sequence = [
		{"speaker": "Chad", "text": "*Heavy Breathing*", "delay": 2.5},
		{"speaker": "Janitor", "text": "You alright?", "delay": 2.0},
		{"speaker": "Chad", "text": "Yeah I'm fine, did the photoshoot start yet?", "delay": 3.0},
		{"speaker": "Janitor", "text": "Photoshoot?", "delay": 2.0},
		{"speaker": "Chad", "text": "Yeah the photoshoot schedueled for Sunday", "delay": 3.0},
		{"speaker": "Janitor", "text": "Today's Saturday", "delay": 2.5},
		{"speaker": "Chad", "text": "...", "delay": 2.0},
		{
			"speaker": "Janitor", 
			"text": "", 
			"attach_cat_emoji": true, 
			"custom_sfx": laughing_cat_sfx, 
			"delay": 3.0
		}
	]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if not _is_transitioning:
			_end_cutscene()


func _play_sequence() -> void:
	for line in dialogue_sequence:
		if _is_transitioning:
			break
			
		_add_chat_line(line)
		await get_tree().create_timer(line["delay"], false).timeout

	if not _is_transitioning:
		_end_cutscene()


func _add_chat_line(line_data: Dictionary) -> void:
	var speaker: String = line_data.get("speaker", "")
	var text: String = line_data.get("text", "")
	var custom_sfx: AudioStream = line_data.get("custom_sfx", null)
	var attach_cat_emoji: bool = line_data.get("attach_cat_emoji", false)

	if attach_cat_emoji and cat_emoji_texture != null:
		var img_tag := "[img=%dx%d]%s[/img]" % [emoji_size, emoji_size, cat_emoji_texture.resource_path]
		text = img_tag if text.is_empty() else text + " " + img_tag

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
		_play_sound(custom_sfx if custom_sfx else chad_sfx, chad_player, custom_sfx != null)
	else:
		l.text = "[b][color=%s]Janitor:[/color][/b] %s" % [_color_hex(janitor_color), text]
		_play_sound(custom_sfx if custom_sfx else janitor_sfx, janitor_player, custom_sfx != null)

	l.modulate.a = 0.0
	vbox.add_child(l)

	var tw = create_tween()
	tw.tween_property(l, "modulate:a", 1.0, text_fade_time)


func _play_sound(stream: AudioStream, default_player: AudioStreamPlayer, is_custom: bool) -> void:
	if stream == null:
		return

	if is_custom:
		# Dynamic player for the cat laugh using the custom volume slider
		var temp_player := AudioStreamPlayer.new()
		temp_player.stream = stream
		temp_player.volume_db = linear_to_db(clampf(cat_sfx_volume, 0.0001, 1.0))
		add_child(temp_player)
		temp_player.play()
		temp_player.finished.connect(temp_player.queue_free)
	else:
		# Standard character blip played at default volume (0 dB)
		default_player.volume_db = 0.0
		default_player.play()


func _end_cutscene() -> void:
	_is_transitioning = true
	
	if is_instance_valid(skip_label):
		skip_label.visible = false

	var steps := maxi(1, fade_steps)
	var step_delay := fade_duration / float(steps)

	for i in range(steps + 1):
		fade_rect.modulate.a = float(i) / float(steps)
		await get_tree().create_timer(step_delay, true, false, true).timeout

	if next_level_scene:
		get_tree().change_scene_to_packed(next_level_scene)
	elif next_level_path != "":
		get_tree().change_scene_to_file(next_level_path)
	else:
		push_error("Dialogue Transition Failed: No 'next_level_scene' or 'next_level_path' assigned.")


func _build_ui() -> void:
	var holder = MarginContainer.new()
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

	skip_label = Label.new()
	skip_label.text = "Press [SPACE] to Skip"
	skip_label.add_theme_font_size_override("font_size", 14)
	skip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.4))
	skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_label.anchor_left = 1.0
	skip_label.anchor_right = 1.0
	skip_label.anchor_top = 1.0
	skip_label.anchor_bottom = 1.0
	skip_label.offset_left = -220
	skip_label.offset_top = -40
	skip_label.offset_right = -20
	skip_label.offset_bottom = -20
	add_child(skip_label)

	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade_rect)


func _setup_audio() -> void:
	chad_player = AudioStreamPlayer.new()
	chad_player.stream = chad_sfx
	add_child(chad_player)

	janitor_player = AudioStreamPlayer.new()
	janitor_player.stream = janitor_sfx
	add_child(janitor_player)


func _color_hex(c: Color) -> String:
	return "#" + c.to_html(false)
