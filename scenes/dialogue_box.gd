extends CanvasLayer

# GMod-style chat/console prompt box.
# Bottom-left, no panel background, colored name tags, fast fade.
# Attach to a CanvasLayer node that lives in your level scene.
# Sound: keep an AudioStreamPlayer child named SFX with your stream set,
# or drop a sound into "Enter Sound" below.

@export var enter_sound: AudioStream
@export var font: Font                       # optional, engine default looks fine (GMod uses Tahoma-ish)
@export var font_size: int = 15
@export var bottom_margin: int = 220
@export var left_margin: int = 20
@export var line_spacing: int = 4
@export var fade_time: float = 0.2           # snappy fade, no PS1 stepping
@export var sub_delay: float = 0.8           # pause after the Chad line before the GAME line appears

@export var player_name: String = "Chad"
@export var player_name_color: Color = Color(0.4, 0.65, 1.0)     # light blue "team" tag
@export var console_name: String = "GAME"
@export var console_name_color: Color = Color(1.0, 0.65, 0.15)   # orange console tag
@export var message_color: Color = Color(1.0, 1.0, 1.0)
@export var shadow_color: Color = Color(0, 0, 0, 0.9)

var holder: MarginContainer
var vbox: VBoxContainer
var main_line: RichTextLabel
var sub_line: RichTextLabel
var sfx: AudioStreamPlayer
var main_tween: Tween
var sub_tween: Tween
var message_id: int = 0

func _ready() -> void:
	add_to_group("dialogue_box")

	# the old hand made Panel is not needed anymore
	if has_node("Panel"):
		get_node("Panel").queue_free()

	_build_ui()
	_setup_sfx()

func _build_ui() -> void:
	# full screen holder (like the old Panel setup) so it can actually size
	# and position the chat box inside it via margins + shrink flags
	holder = MarginContainer.new()
	holder.name = "ChatHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_left", left_margin)
	holder.add_theme_constant_override("margin_bottom", bottom_margin)

	vbox = VBoxContainer.new()
	vbox.name = "ChatLines"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", line_spacing)
	# hug the bottom-left corner of the margined area instead of stretching full screen
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_END
	holder.add_child(vbox)

	main_line = _make_line()
	vbox.add_child(main_line)

	sub_line = _make_line()
	vbox.add_child(sub_line)

	main_line.modulate.a = 0.0
	sub_line.modulate.a = 0.0

func _make_line() -> RichTextLabel:
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
	return l

func _setup_sfx() -> void:
	sfx = get_node_or_null("SFX") as AudioStreamPlayer
	if sfx == null:
		sfx = AudioStreamPlayer.new()
		sfx.name = "SFX"
		add_child(sfx)
	if enter_sound:
		sfx.stream = enter_sound

func _color_hex(c: Color) -> String:
	return "#" + c.to_html(false)

# --- PUBLIC API (unchanged signatures, so nothing else needs to change) ---

# main_text prints as "Chad: <main_text>"
# sub_text prints as "[GAME] <sub_text>" after sub_delay
func show_message(main_text: String, sub_text: String = "") -> void:
	message_id += 1
	var my_id := message_id

	main_line.text = "[b][color=%s]%s:[/color][/b] %s" % [_color_hex(player_name_color), player_name, main_text]
	sub_line.text = "[b][color=%s][%s][/color][/b] %s" % [_color_hex(console_name_color), console_name, sub_text]
	sub_line.visible = sub_text != ""
	sub_line.modulate.a = 0.0

	if sfx.stream:
		sfx.play()

	await _fade(main_line, main_tween, 1.0)
	if sub_text == "" or my_id != message_id:
		return

	await get_tree().create_timer(sub_delay).timeout
	if my_id != message_id:
		return

	await _fade(sub_line, sub_tween, 1.0)

func hide_message() -> void:
	message_id += 1
	if main_tween:
		main_tween.kill()
	if sub_tween:
		sub_tween.kill()
	await _fade(main_line, main_tween, 0.0)
	await _fade(sub_line, sub_tween, 0.0)

func _fade(line: RichTextLabel, tween_ref: Tween, to_alpha: float) -> void:
	if tween_ref:
		tween_ref.kill()
	var tw := create_tween()
	if line == main_line:
		main_tween = tw
	else:
		sub_tween = tw
	tw.tween_property(line, "modulate:a", to_alpha, fade_time)
	await tw.finished
