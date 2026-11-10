extends Control

var timer: float = 0.0
const DUMMY_WAIT: float = 1.5

@onready var label: Label = Label.new()

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	label.text = "REAL-WORLD FLY-THROUGH & INTERACTIVE LEVEL\n(Under Construction - Advancing in 1.5 s...)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(label)

func _process(delta: float) -> void:
	timer += delta
	if timer >= DUMMY_WAIT:
		set_process(false)
		if typeof(GameSettings) != TYPE_NIL:
			GameSettings.finish_current_benchmark()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			GameSettings.is_running_full_suite = false
			get_tree().change_scene_to_file("res://benchmark_hub.tscn")
