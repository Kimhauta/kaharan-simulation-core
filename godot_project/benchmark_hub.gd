## Central launcher hub for individual benchmark stages and the full 5-stage suite.
##
## Displays active hardware and profile metadata and presents a 3x2 grid of cards
## for running Rendered/Headless Synthetic A/B tests, Dynamic Ramp-Up saturation
## tests, the 3-Room Fly-Through LOD tour, or the automated full-suite pipeline.
extends Control

const MAIN_MENU_PATH = "res://main_menu.tscn"
const RESULTS_PATH = "res://benchmark_results.tscn"
const SETTINGS_PATH = "res://settings_menu.tscn"

const SCENE_SYNTHETIC_RENDER = "res://bench_synthetic_render.tscn"
const SCENE_SYNTHETIC_HEADLESS = "res://bench_synthetic_headless.tscn"
const SCENE_RAMP_RENDER = "res://bench_ramp_up_render.tscn"
const SCENE_RAMP_HEADLESS = "res://bench_ramp_up_headless.tscn"
const SCENE_FLYTHROUGH = "res://greybox_level.tscn"


## Ensures cursor visibility and constructs the hub UI layout.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for child in get_children():
		child.queue_free()
	_build_hub_ui()


## Navigates back to the main menu when Escape is pressed.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MAIN_MENU_PATH)


## Builds the header bar, hardware summary banner, 3x2 test grid, and footer.
func _build_hub_ui() -> void:
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

	# 1. Top header bar
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title = Label.new()
	title.text = "BENCHMARK SUITE HUB"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0))
	header.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)

	var btn_settings = Button.new()
	btn_settings.text = "Configure Settings"
	btn_settings.custom_minimum_size = Vector2(160, 36)
	btn_settings.pressed.connect(func(): get_tree().change_scene_to_file(SETTINGS_PATH))
	header.add_child(btn_settings)

	var btn_back = Button.new()
	btn_back.text = "Back to Menu (ESC)"
	btn_back.custom_minimum_size = Vector2(170, 36)
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_PATH))
	header.add_child(btn_back)

	# 2. Active profile and runtime environment banner
	var info_panel = PanelContainer.new()
	var i_style = StyleBoxFlat.new()
	i_style.bg_color = Color(0.09, 0.12, 0.17, 0.95)
	i_style.border_color = Color(0.22, 0.30, 0.42, 1.0)
	i_style.set_border_width_all(1)
	i_style.set_corner_radius_all(6)
	i_style.set_content_margin_all(12)
	info_panel.add_theme_stylebox_override("panel", i_style)
	root_vbox.add_child(info_panel)

	var info_lbl = RichTextLabel.new()
	info_lbl.bbcode_enabled = true
	info_lbl.fit_content = true
	info_lbl.text = _get_environment_summary_bbcode()
	info_panel.add_child(info_lbl)

	# 3. 3x2 Benchmark suite card grid
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	root_vbox.add_child(grid)

	_add_suite_card(grid,
		"1. Synthetic A/B (Rendered)",
		"Fixed workloads comparing C++20 SoA + MultiMesh against GDScript Node3D using uniform 5-color cubes (constant 12 tris/entity).",
		"Run Rendered A/B",
		Color(0.25, 0.55, 0.95),
		func(): _run_single_scene(SCENE_SYNTHETIC_RENDER, "synthetic_render")
	)

	_add_suite_card(grid,
		"2. Synthetic A/B (Headless)",
		"Pure CPU memory and simulation throughput benchmark with rendering and GPU buffer synchronization completely disabled.",
		"Run Headless A/B",
		Color(0.25, 0.55, 0.95),
		func(): _run_single_scene(SCENE_SYNTHETIC_HEADLESS, "synthetic_headless")
	)

	_add_suite_card(grid,
		"3. Dynamic Ramp-Up (Rendered)",
		"Continuous entity emitter determining exact 60 FPS (17.5 ms) saturation breaking points for rendered DOD vs. OOP.",
		"Run Rendered Ramp-Up",
		Color(0.95, 0.55, 0.15),
		func(): _run_single_scene(SCENE_RAMP_RENDER, "ramp_render")
	)

	_add_suite_card(grid,
		"4. Dynamic Ramp-Up (Headless)",
		"Continuous entity emitter pushing pure CPU simulation until the 60 Hz logic budget saturates.",
		"Run Headless Ramp-Up",
		Color(0.95, 0.55, 0.15),
		func(): _run_single_scene(SCENE_RAMP_HEADLESS, "ramp_headless")
	)

	_add_suite_card(grid,
		"5. 3-Room Fly-Through & LOD",
		"4-pass production camera tour (OOP Base, OOP+LOD, DOD Base, DOD+LOD) evaluating spatial Simulation LOD across 3 rooms.",
		"Run 3-Room Fly-Through",
		Color(0.20, 0.80, 0.55),
		_on_run_flythrough_pressed
	)

	_add_suite_card(grid,
		"6. Full Automated Benchmark Suite",
		"Executes all 5 benchmark stages consecutively into a single timestamped session folder with manifest.json and raw frame CSVs.",
		"RUN FULL 5-STAGE SUITE",
		Color(0.68, 0.42, 0.96),
		_on_run_full_suite_pressed
	)

	# 4. Bottom footer bar
	var footer = HBoxContainer.new()
	root_vbox.add_child(footer)

	var path_lbl = Label.new()
	var out_dir = GameSettings.get_runs_base_dir() if typeof(GameSettings) != TYPE_NIL else "res://user_files/runs"
	path_lbl.text = "Output Directory: %s" % out_dir
	path_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.65))
	footer.add_child(path_lbl)

	var f_spacer = Control.new()
	f_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(f_spacer)

	var btn_results = Button.new()
	btn_results.text = "View Results & Analytics"
	btn_results.custom_minimum_size = Vector2(210, 36)
	btn_results.pressed.connect(func(): get_tree().change_scene_to_file(RESULTS_PATH))
	footer.add_child(btn_results)


## Adds an individual benchmark card with title, description, and action button.
func _add_suite_card(parent: Control, card_title: String, desc: String, btn_text: String, accent: Color, callback: Callable) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	style.border_color = accent
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var lbl_t = Label.new()
	lbl_t.text = card_title
	lbl_t.add_theme_font_size_override("font_size", 16)
	lbl_t.add_theme_color_override("font_color", accent.lightened(0.25))
	vbox.add_child(lbl_t)

	var lbl_d = Label.new()
	lbl_d.text = desc
	lbl_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_d.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	vbox.add_child(lbl_d)

	var sp = Control.new()
	sp.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(sp)

	var btn = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.pressed.connect(callback)
	vbox.add_child(btn)


## Formats detected CPU, GPU, build mode, and active profile settings as BBCode.
func _get_environment_summary_bbcode() -> String:
	var build_type = "[color=#f39c12]Editor / Debug Build[/color]" if OS.has_feature("editor") else "[color=#2ecc71]Exported Release Build[/color]"
	var vsync_str = "ON" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "OFF"
	var dur = GameSettings.get_sample_duration() if typeof(GameSettings) != TYPE_NIL else 4.0
	var wl_idx = GameSettings.synthetic_workload if typeof(GameSettings) != TYPE_NIL else 0
	var wl_names = ["Standard (1k, 5k, 10k)", "Lightweight (500, 1k, 2.5k)", "Extreme (5k, 10k, 25k)"]

	return "[b]Runtime Environment:[/b] %s  |  [b]CPU:[/b] %s  |  [b]GPU:[/b] %s\n[b]Active Profile:[/b] %.0fs/step  |  [b]Workload:[/b] %s  |  [b]V-Sync:[/b] %s" % [
		build_type, OS.get_processor_name(), RenderingServer.get_video_adapter_name(),
		dur, wl_names[clampi(wl_idx, 0, 2)], vsync_str
	]


## Creates a dedicated session folder and starts a single benchmark scene.
func _run_single_scene(scene_path: String, label: String) -> void:
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.is_running_full_suite = false
		GameSettings.create_new_session(label)
	get_tree().change_scene_to_file(scene_path)


## Launches the 3-room level directly in 4-pass automated Fly-Through benchmark mode.
func _on_run_flythrough_pressed() -> void:
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.is_running_full_suite = false
		GameSettings.force_greybox_benchmark = true
		GameSettings.create_new_session("flythrough_lod")
	get_tree().change_scene_to_file(SCENE_FLYTHROUGH)


## Enqueues and executes all five benchmark stages sequentially under one session.
func _on_run_full_suite_pressed() -> void:
	var full_playlist: Array[String] = [
		SCENE_SYNTHETIC_RENDER,
		SCENE_SYNTHETIC_HEADLESS,
		SCENE_RAMP_RENDER,
		SCENE_RAMP_HEADLESS,
		SCENE_FLYTHROUGH
	]
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.start_benchmark_suite(full_playlist, "full_suite_release")
