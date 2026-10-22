extends Control

const BENCHMARK_SCENE_PATH = "res://test_scene.tscn"
const INTERACTIVE_SCENE_PATH = "res://interactive_demo.tscn"

@onready var vsync_check: CheckButton = find_child("VSyncCheck", true, false) as CheckButton
@onready var results_label: RichTextLabel = find_child("ResultsLabel", true, false) as RichTextLabel

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if vsync_check:
		# Asetetaan kytkimen tila ilman että signaali laukeaa turhaan
		vsync_check.set_pressed_no_signal(GameSettings.vsync_enabled)
		
	_load_benchmark_summary()

func _on_btn_interactive_pressed() -> void:
	if ResourceLoader.exists(INTERACTIVE_SCENE_PATH):
		get_tree().change_scene_to_file(INTERACTIVE_SCENE_PATH)
	else:
		if results_label:
			results_label.text = "[color=orange]Interactive demo scene not created yet. Coming in Phase 2![/color]"

func _on_btn_benchmark_pressed() -> void:
	get_tree().change_scene_to_file(BENCHMARK_SCENE_PATH)

func _on_v_sync_check_toggled(toggled_on: bool) -> void:
	GameSettings.set_vsync(toggled_on)
	print("[MainMenu] V-Sync saved & set to: ", toggled_on)

func _on_vsync_check_toggled(toggled_on: bool) -> void:
	_on_v_sync_check_toggled(toggled_on)

func _on_btn_quit_pressed() -> void:
	get_tree().quit()

func _load_benchmark_summary() -> void:
	if not results_label:
		return
		
	results_label.bbcode_enabled = true
	results_label.custom_minimum_size = Vector2(560, 220)
		
	var path = "res://user_files/benchmark_summary.dat"
	if not FileAccess.file_exists(path):
		results_label.text = "[color=gray]No benchmark results found yet. Click 'Run Automated A/B Benchmark' to start.[/color]"
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return

	var _header = file.get_line()
	
	var out_text = "[b]LATEST BENCHMARK RESULTS (1-Mesh vs 5-Mesh DOD vs OOP):[/b]\n[code]"
	out_text += "%-15s | %-7s | %-9s | %-11s | %-11s\n" % ["CONFIG", "COUNT", "AVG FPS", "LOGIC (us)", "TOTAL (us)"]
	out_text += "-----------------------------------------------------------------\n"
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line == "":
			continue
		var parts = line.split(",")
		if parts.size() >= 10:
			out_text += "%-15s | %-7s | %-9s | %-11s | %-11s\n" % [
				parts[0], parts[1], parts[3], parts[5] + " us", parts[9] + " us"
			]
			
	out_text += "[/code]"
	file.close()
	results_label.text = out_text
