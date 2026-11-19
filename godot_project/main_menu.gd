## Primary entry menu for Kaharan Simulation Core[cite: 22].
##
## Builds the programmatic dark-themed UI, verifies that the C++20 GDExtension
## SimulationBridge class is registered in ClassDB, and provides navigation to
## the interactive sandbox, benchmark hub, analytics view, and settings menu[cite: 22].
extends Control

const PLAYABLE_SCENE_PATH: String = "res://greybox_level.tscn"
const BENCHMARK_HUB_PATH: String = "res://benchmark_hub.tscn"
const RESULTS_SCENE_PATH: String = "res://benchmark_results.tscn"
const SETTINGS_SCENE_PATH: String = "res://settings_menu.tscn"

## Displays scene transition errors if a target scene cannot be found[cite: 22].
var status_label: Label


## Initializes the menu by resetting mouse capture and constructing the UI[cite: 22].
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for child in get_children():
		child.queue_free()
	_build_main_menu_ui()


## Constructs the centered menu card, status indicators, and navigation buttons[cite: 22].
func _build_main_menu_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.067, 0.09, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	style.border_color = Color(0.25, 0.55, 0.95, 1.0)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Application title and subtitle
	var title = Label.new()
	title.text = "KAHARAN SIMULATION CORE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0))
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Data-Oriented C++20 Simulation Engine & Godot 4 Benchmark Suite"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
	vbox.add_child(subtitle)

	# GDExtension and runtime build status badge
	var badge_panel = PanelContainer.new()
	var b_style = StyleBoxFlat.new()
	b_style.bg_color = Color(0.05, 0.07, 0.10, 0.9)
	b_style.set_corner_radius_all(4)
	b_style.set_content_margin_all(8)
	badge_panel.add_theme_stylebox_override("panel", b_style)
	vbox.add_child(badge_panel)

	var badge_lbl = RichTextLabel.new()
	badge_lbl.bbcode_enabled = true
	badge_lbl.fit_content = true
	var bridge_ok = ClassDB.class_exists("SimulationBridge")
	var bridge_str = "[color=#2ecc71]SimulationBridge C++20 Active[/color]" if bridge_ok else "[color=#e74c3c]SimulationBridge DLL Missing![/color]"
	var mode_str = "[color=#f39c12]Editor Build[/color]" if OS.has_feature("editor") else "[color=#2ecc71]Release Executable[/color]"
	badge_lbl.text = "[center]%s  |  %s[/center]" % [bridge_str, mode_str]
	badge_panel.add_child(badge_lbl)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Primary navigation buttons
	_add_menu_button(vbox, "Play Interactive 3-Room Sandbox", Color(0.20, 0.78, 0.52), _on_play_pressed)
	_add_menu_button(vbox, "Benchmark Suite Hub", Color(0.25, 0.55, 0.95), _on_benchmark_pressed)
	_add_menu_button(vbox, "View Results & Analytics", Color(0.68, 0.42, 0.96), _on_results_pressed)
	_add_menu_button(vbox, "Engine & Benchmark Settings", Color(0.95, 0.55, 0.15), _on_settings_pressed)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	_add_menu_button(vbox, "Quit Application", Color(0.75, 0.28, 0.32), func(): get_tree().quit())

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(status_label)


## Creates a styled menu button with a colored left accent border and connects its signal[cite: 22].
func _add_menu_button(parent: Control, label_text: String, accent: Color, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 42)
	btn.add_theme_font_size_override("font_size", 15)

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.14, 0.19, 1.0)
	normal.border_color = accent.darkened(0.25)
	normal.set_border_width_all(1)
	normal.border_width_left = 4
	normal.set_corner_radius_all(5)

	var hover = normal.duplicate()
	hover.bg_color = Color(0.16, 0.20, 0.27, 1.0)
	hover.border_color = accent

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(callback)
	parent.add_child(btn)


## Launches the 3-room level in interactive free-roam sandbox mode[cite: 22].
func _on_play_pressed() -> void:
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.is_running_full_suite = false
		GameSettings.force_greybox_benchmark = false
	_change_scene_safe(PLAYABLE_SCENE_PATH, "Interactive demo scene (greybox_level.tscn) not found.")


## Navigates to the Benchmark Suite Hub[cite: 22].
func _on_benchmark_pressed() -> void:
	_change_scene_safe(BENCHMARK_HUB_PATH, "Benchmark Hub scene not found.")


## Navigates to the Benchmark Results and Analytics dashboard[cite: 22].
func _on_results_pressed() -> void:
	_change_scene_safe(RESULTS_SCENE_PATH, "Results scene not found.")


## Navigates to the Engine & Benchmark Settings screen[cite: 22].
func _on_settings_pressed() -> void:
	_change_scene_safe(SETTINGS_SCENE_PATH, "Settings scene not found.")


## Safely transitions to [param target_path] if the scene resource exists[cite: 22].
func _change_scene_safe(target_path: String, fallback_msg: String) -> void:
	if ResourceLoader.exists(target_path):
		get_tree().change_scene_to_file(target_path)
	elif status_label:
		status_label.text = fallback_msg
