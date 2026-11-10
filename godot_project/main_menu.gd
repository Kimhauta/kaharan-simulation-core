extends Control

const PLAYABLE_SCENE_PATH = "res://greybox_level.tscn"
const BENCHMARK_HUB_PATH = "res://benchmark_hub.tscn"
const RESULTS_SCENE_PATH = "res://benchmark_results.tscn"
const SETTINGS_SCENE_PATH = "res://settings_menu.tscn"

@onready var btn_play: Button = find_child("BtnPlay", true, false) as Button
@onready var btn_benchmark: Button = find_child("BtnBenchmark", true, false) as Button
@onready var btn_results: Button = find_child("BtnResults", true, false) as Button
@onready var btn_settings: Button = find_child("BtnSettings", true, false) as Button
@onready var btn_quit: Button = find_child("BtnQuit", true, false) as Button
@onready var status_label: Label = find_child("StatusLabel", true, false) as Label

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if btn_play and not btn_play.pressed.is_connected(_on_btn_play_pressed):
		btn_play.pressed.connect(_on_btn_play_pressed)
	if btn_benchmark and not btn_benchmark.pressed.is_connected(_on_btn_benchmark_pressed):
		btn_benchmark.pressed.connect(_on_btn_benchmark_pressed)
	if btn_results and not btn_results.pressed.is_connected(_on_btn_results_pressed):
		btn_results.pressed.connect(_on_btn_results_pressed)
	if btn_settings and not btn_settings.pressed.is_connected(_on_btn_settings_pressed):
		btn_settings.pressed.connect(_on_btn_settings_pressed)
	if btn_quit and not btn_quit.pressed.is_connected(_on_btn_quit_pressed):
		btn_quit.pressed.connect(_on_btn_quit_pressed)

func _on_btn_play_pressed() -> void:
	_change_scene_safe(PLAYABLE_SCENE_PATH, "Interactive demo scene (greybox_level.tscn) not created yet.")

func _on_btn_benchmark_pressed() -> void:
	_change_scene_safe(BENCHMARK_HUB_PATH, "Benchmark scene not found.")

func _on_btn_results_pressed() -> void:
	_change_scene_safe(RESULTS_SCENE_PATH, "Results scene (benchmark_results.tscn) not created yet.")

func _on_btn_settings_pressed() -> void:
	_change_scene_safe(SETTINGS_SCENE_PATH, "Settings scene (settings_menu.tscn) not created yet.")

func _on_btn_quit_pressed() -> void:
	get_tree().quit()

func _change_scene_safe(target_path: String, fallback_msg: String) -> void:
	if ResourceLoader.exists(target_path):
		get_tree().change_scene_to_file(target_path)
	else:
		if status_label:
			status_label.text = fallback_msg
		print("[MainMenu] Warning: ", fallback_msg)
