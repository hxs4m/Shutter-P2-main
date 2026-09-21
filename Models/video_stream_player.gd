extends VideoStreamPlayer

# Target scene to switch to after the video ends or is skipped
@export_file("*.tscn") var next_scene_path: String = "res://MainMenu.tscn"

func _ready() -> void:
	# Connect the video finished signal directly on this node
	finished.connect(_on_video_finished)

func _input(event: InputEvent) -> void:
	# Allow skipping the video on key or mouse press
	if event.is_pressed() and not event.is_echo():
		_change_to_next_scene()

func _on_video_finished() -> void:
	_change_to_next_scene()

func _change_to_next_scene() -> void:
	get_tree().change_scene_to_file(next_scene_path)
