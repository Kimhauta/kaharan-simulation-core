## Configuration screen for display, synthetic A/B, and dynamic Ramp-Up parameters.
##
## Programmatically builds a three-column settings interface bound to the global
## [GameSettings] singleton and persists user choices to [code]user://settings.cfg[/code].
extends Control

const MAIN_MENU_PATH: String = "res://main_menu.tscn"

# Display and execution controls
var chk_vsync: CheckButton
var opt_window_mode: OptionButton
var opt_max_fps: OptionButton
var opt_profile: OptionButton

# Synthetic A/B parameter controls
var opt_mesh_mode: OptionButton
var opt_workload: OptionButton

# Dynamic Ramp-Up emitter controls
var opt_ramp_mode: OptionButton
var spin_base_rate: SpinBox
var spin_accel_factor: SpinBox

## Footer feedback label confirming save/reset operations.
var status_label: Label


## Constructs the settings UI and populates controls from [GameSettings].
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for child in get_children():
		child.queue_free()
	_build_settings_ui()
	_load_from_game_settings()


## Returns to the main menu when Escape is pressed.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MAIN_MENU_PATH)


## Builds the header, three parameter columns, and action footer.
func _build_settings_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.067, 0.09, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	# Top header bar
	var header = HBoxContainer.new()
	root_vbox.add_child(header)

	var title = Label.new()
	title.text = "ENGINE & BENCHMARK CONFIGURATION"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.55, 0.15))
	header.add_child(title)

	var sp = Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(sp)

	var btn_back = Button.new()
	btn_back.text = "Back to Menu (ESC)"
	btn_back.custom_minimum_size = Vector2(180, 36)
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_PATH))
	header.add_child(btn_back)

	# Main configuration area (3 parameter columns)
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	root_vbox.add_child(columns)

	# --- COLUMN 1: Display & Engine ---
	var sec1 = _create_section_panel(columns, "1. Display & Execution Profile", Color(0.25, 0.55, 0.95))

	chk_vsync = CheckButton.new()
	chk_vsync.text = "Enable V-Sync (Recommended: OFF for benchmarks)"
	sec1.add_child(chk_vsync)

	opt_window_mode = OptionButton.new()
	opt_window_mode.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	opt_window_mode.add_item("Borderless Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	opt_window_mode.add_item("Exclusive Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	_add_labeled_row(sec1, "Window Mode:", opt_window_mode)

	opt_max_fps = OptionButton.new()
	opt_max_fps.add_item("Unlimited (0)", 0)
	opt_max_fps.add_item("60 FPS", 60)
	opt_max_fps.add_item("120 FPS", 120)
	opt_max_fps.add_item("144 FPS", 144)
	opt_max_fps.add_item("240 FPS", 240)
	_add_labeled_row(sec1, "Max FPS Cap:", opt_max_fps)

	opt_profile = OptionButton.new()
	opt_profile.add_item("Quick (4s step / 25s tour)", 0)
	opt_profile.add_item("Standard (10s step / 45s tour)", 1)
	opt_profile.add_item("Soak / Endurance (300s step / 75s tour)", 2)
	_add_labeled_row(sec1, "Benchmark Profile:", opt_profile)

	# --- COLUMN 2: Synthetic A/B Matrix ---
	var sec2 = _create_section_panel(columns, "2. Synthetic A/B Parameters", Color(0.20, 0.78, 0.52))

	opt_workload = OptionButton.new()
	opt_workload.add_item("Standard (1k, 5k, 10k)", 0)
	opt_workload.add_item("Lightweight (500, 1k, 2.5k)", 1)
	opt_workload.add_item("Extreme (5k, 10k, 25k)", 2)
	_add_labeled_row(sec2, "Entity Workload Tier:", opt_workload)

	opt_mesh_mode = OptionButton.new()
	opt_mesh_mode.add_item("Full Matrix (1 & 5 Meshes)", 0)
	opt_mesh_mode.add_item("Single-Mesh Only (1 Draw Call)", 1)
	opt_mesh_mode.add_item("Multi-Mesh Only (5 Draw Calls)", 2)
	_add_labeled_row(sec2, "Batching Mode:", opt_mesh_mode)

	var note2 = Label.new()
	note2.text = "Note: All variants use uniform 12-triangle cubes so GPU geometry remains constant across draw call tiers."
	note2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note2.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	sec2.add_child(note2)

	# --- COLUMN 3: Dynamic Ramp-Up Emitter ---
	var sec3 = _create_section_panel(columns, "3. Dynamic Ramp-Up Emitter", Color(0.68, 0.42, 0.96))

	opt_ramp_mode = OptionButton.new()
	opt_ramp_mode.add_item("Progressive Acceleration", 0)
	opt_ramp_mode.add_item("Constant Linear Spawn", 1)
	_add_labeled_row(sec3, "Growth Model:", opt_ramp_mode)

	spin_base_rate = SpinBox.new()
	spin_base_rate.min_value = 50.0
	spin_base_rate.max_value = 5000.0
	spin_base_rate.step = 50.0
	spin_base_rate.suffix = " / s"
	_add_labeled_row(sec3, "Base Spawn Rate:", spin_base_rate)

	spin_accel_factor = SpinBox.new()
	spin_accel_factor.min_value = 0.0
	spin_accel_factor.max_value = 1000.0
	spin_accel_factor.step = 25.0
	spin_accel_factor.suffix = " / s²"
	_add_labeled_row(sec3, "Acceleration Factor:", spin_accel_factor)

	# Bottom action footer bar
	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root_vbox.add_child(footer)

	status_label = Label.new()
	status_label.text = "Settings are saved to user://settings.cfg"
	status_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	footer.add_child(status_label)

	var f_sp = Control.new()
	f_sp.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(f_sp)

	var btn_reset = Button.new()
	btn_reset.text = "Reset Defaults"
	btn_reset.custom_minimum_size = Vector2(150, 40)
	btn_reset.pressed.connect(_on_reset_defaults)
	footer.add_child(btn_reset)

	var btn_save = Button.new()
	btn_save.text = "Apply & Save Settings"
	btn_save.custom_minimum_size = Vector2(200, 40)
	btn_save.pressed.connect(_on_apply_and_save)
	footer.add_child(btn_save)


## Creates a bordered section card with a colored top accent bar.
func _create_section_panel(parent: Control, sec_title: String, accent: Color) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	style.border_color = accent
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var lbl = Label.new()
	lbl.text = sec_title
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", accent.lightened(0.25))
	vbox.add_child(lbl)

	var sep = HSeparator.new()
	vbox.add_child(sep)
	return vbox


## Wraps a form input control with a descriptive label above it.
func _add_labeled_row(parent: Control, label_text: String, ctrl: Control) -> void:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	box.add_child(lbl)
	ctrl.custom_minimum_size = Vector2(0, 34)
	box.add_child(ctrl)
	parent.add_child(box)


## Selects the item in [param opt] matching [param target_id].
func _select_option_by_id(opt: OptionButton, target_id: int) -> void:
	for i in range(opt.item_count):
		if opt.get_item_id(i) == target_id:
			opt.select(i)
			return
	opt.select(0)


## Synchronizes UI widgets with current [GameSettings] values.
func _load_from_game_settings() -> void:
	if typeof(GameSettings) == TYPE_NIL:
		return
	chk_vsync.button_pressed = GameSettings.vsync_enabled
	_select_option_by_id(opt_window_mode, GameSettings.window_mode)
	_select_option_by_id(opt_max_fps, GameSettings.max_fps_limit)
	_select_option_by_id(opt_profile, GameSettings.benchmark_profile)
	_select_option_by_id(opt_workload, GameSettings.synthetic_workload)
	_select_option_by_id(opt_mesh_mode, GameSettings.synthetic_mesh_mode)
	_select_option_by_id(opt_ramp_mode, GameSettings.ramp_growth_mode)
	spin_base_rate.value = GameSettings.ramp_base_spawn_rate
	spin_accel_factor.value = GameSettings.ramp_acceleration_factor


## Writes UI widget selections back to [GameSettings], saves to disk, and applies display rules.
func _on_apply_and_save() -> void:
	if typeof(GameSettings) == TYPE_NIL:
		return
	GameSettings.vsync_enabled = chk_vsync.button_pressed
	GameSettings.window_mode = opt_window_mode.get_selected_id()
	GameSettings.max_fps_limit = opt_max_fps.get_selected_id()
	GameSettings.benchmark_profile = opt_profile.get_selected_id()
	GameSettings.synthetic_workload = opt_workload.get_selected_id()
	GameSettings.synthetic_mesh_mode = opt_mesh_mode.get_selected_id()
	GameSettings.ramp_growth_mode = opt_ramp_mode.get_selected_id()
	GameSettings.ramp_base_spawn_rate = spin_base_rate.value
	GameSettings.ramp_acceleration_factor = spin_accel_factor.value

	GameSettings.save_settings()
	GameSettings.apply_settings()
	status_label.text = "Settings applied and saved successfully!"
	status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.45))


## Restores default benchmark parameters and persists them immediately.
func _on_reset_defaults() -> void:
	if typeof(GameSettings) == TYPE_NIL:
		return
	GameSettings.vsync_enabled = false
	GameSettings.window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	GameSettings.max_fps_limit = 0
	GameSettings.benchmark_profile = 0
	GameSettings.synthetic_workload = 0
	GameSettings.synthetic_mesh_mode = 0
	GameSettings.ramp_growth_mode = 0
	GameSettings.ramp_base_spawn_rate = 300.0
	GameSettings.ramp_acceleration_factor = 75.0
	_load_from_game_settings()
	_on_apply_and_save()
	status_label.text = "Restored default benchmark settings."
