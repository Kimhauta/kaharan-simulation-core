## Interactive analytics and visualization dashboard for recorded benchmark sessions.
##
## Parses [code]manifest.json[/code], [code]summary.csv[/code], and per-frame Ramp-Up timelines
## to render comparative speedup tables, 2D frame-time saturation curves, frame-pacing
## jitter ratings, and hardware environment snapshots.
extends Control

const MAIN_MENU_PATH: String = "res://main_menu.tscn"


## Resolves the base directory containing benchmark run folders.
func _get_runs_base_dir() -> String:
	if typeof(GameSettings) != TYPE_NIL:
		return GameSettings.get_runs_base_dir()
	return "res://user_files/runs"


# Active session telemetry state
var current_session_folder: String = ""
var current_manifest: Dictionary = {}
var summary_rows: Array[Dictionary] = []
var ramp_rendered_points_dod: Array[Vector2] = []
var ramp_rendered_points_oop: Array[Vector2] = []
var ramp_headless_points_dod: Array[Vector2] = []
var ramp_headless_points_oop: Array[Vector2] = []

# Top-level UI controls
var option_sessions: OptionButton
var btn_open_os: Button
var btn_delete: Button
var btn_back: Button
var tab_container: TabContainer

# Tab-specific UI controls
var txt_matrix: RichTextLabel
var txt_stability: RichTextLabel
var txt_manifest: RichTextLabel
var graph_canvas: Control
var option_ramp_source: OptionButton
var lbl_ramp_legend: RichTextLabel
var lbl_ramp_metrics: Label

# Discovered run sessions metadata
var available_sessions: Array[Dictionary] = []


## Builds the analytics UI and loads the most recent benchmark session.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui_layout()
	_refresh_session_list()


## Returns to the main menu when Escape is pressed.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_go_to_menu()


## Transitions back to the main menu scene.
func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


# ==============================================================================
# PROGRAMMATIC UI LAYOUT CONSTRUCTION
# ==============================================================================

## Constructs the header bar, session selector, and tabbed analytics container.
func _build_ui_layout() -> void:
	# Background backdrop
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.11, 1.0)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# 1. Header Bar (Title & Actions)
	var header_bar = HBoxContainer.new()
	main_vbox.add_child(header_bar)

	var title_lbl = Label.new()
	title_lbl.text = "BENCHMARK RESULTS & PERFORMANCE ANALYTICS"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0))
	header_bar.add_child(title_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header_bar.add_child(spacer)

	btn_open_os = Button.new()
	btn_open_os.text = "Open Run Folder in OS"
	btn_open_os.pressed.connect(_on_open_in_os_pressed)
	header_bar.add_child(btn_open_os)

	btn_back = Button.new()
	btn_back.text = "Return to Main Menu"
	btn_back.pressed.connect(_go_to_menu)
	header_bar.add_child(btn_back)

	# 2. Session Management Bar
	var session_panel = PanelContainer.new()
	var s_style = StyleBoxFlat.new()
	s_style.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	s_style.set_corner_radius_all(6)
	s_style.set_content_margin_all(8)
	session_panel.add_theme_stylebox_override("panel", s_style)
	main_vbox.add_child(session_panel)

	var s_hbox = HBoxContainer.new()
	s_hbox.add_theme_constant_override("separation", 12)
	session_panel.add_child(s_hbox)

	var s_lbl = Label.new()
	s_lbl.text = "Select Run Session:"
	s_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	s_hbox.add_child(s_lbl)

	option_sessions = OptionButton.new()
	option_sessions.size_flags_horizontal = SIZE_EXPAND_FILL
	option_sessions.item_selected.connect(_on_session_selected)
	s_hbox.add_child(option_sessions)

	var btn_refresh = Button.new()
	btn_refresh.text = "Refresh"
	btn_refresh.pressed.connect(_refresh_session_list)
	s_hbox.add_child(btn_refresh)

	btn_delete = Button.new()
	btn_delete.text = "Delete Session"
	btn_delete.modulate = Color(1.0, 0.4, 0.4)
	btn_delete.pressed.connect(_on_delete_session_pressed)
	s_hbox.add_child(btn_delete)

	# 3. Analytics Tab Container
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)

	_build_tab_matrix()
	_build_tab_ramp_curves()
	_build_tab_stability()
	_build_tab_manifest()


## Builds the Summary Matrix & Speedup tab.
func _build_tab_matrix() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Summary Matrix & Speedup"
	tab_container.add_child(scroll)

	txt_matrix = RichTextLabel.new()
	txt_matrix.bbcode_enabled = true
	txt_matrix.size_flags_horizontal = SIZE_EXPAND_FILL
	txt_matrix.size_flags_vertical = SIZE_EXPAND_FILL
	txt_matrix.custom_minimum_size = Vector2(800, 450)
	scroll.add_child(txt_matrix)


## Builds the Ramp-Up Curves (Timeline) tab with a custom 2D drawing canvas.
func _build_tab_ramp_curves() -> void:
	var vbox = VBoxContainer.new()
	vbox.name = "Ramp-Up Curves (Timeline)"
	vbox.add_theme_constant_override("separation", 8)
	tab_container.add_child(vbox)

	# Timeline graph control bar
	var ctrl_bar = HBoxContainer.new()
	ctrl_bar.add_theme_constant_override("separation", 14)
	vbox.add_child(ctrl_bar)

	var lbl = Label.new()
	lbl.text = "Timeline Source:"
	ctrl_bar.add_child(lbl)

	option_ramp_source = OptionButton.new()
	option_ramp_source.add_item("Rendered Emitter (5-Mesh Heterogeneous)", 0)
	option_ramp_source.add_item("Headless Emitter (Pure CPU SoA)", 1)
	option_ramp_source.item_selected.connect(func(_i): _update_ramp_curve_display())
	ctrl_bar.add_child(option_ramp_source)

	lbl_ramp_legend = RichTextLabel.new()
	lbl_ramp_legend.bbcode_enabled = true
	lbl_ramp_legend.fit_content = true
	lbl_ramp_legend.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl_ramp_legend.text = "[color=#2ecc71]-- DOD Curve[/color]   [color=#e74c3c]-- OOP Curve[/color]   [color=#f39c12]-- 60 FPS Budget (16.67 ms)[/color]"
	ctrl_bar.add_child(lbl_ramp_legend)

	# 2D timeline plot area
	var graph_panel = PanelContainer.new()
	graph_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var g_style = StyleBoxFlat.new()
	g_style.bg_color = Color(0.04, 0.05, 0.07, 1.0)
	g_style.border_color = Color(0.2, 0.25, 0.35, 1.0)
	g_style.set_border_width_all(1)
	g_style.set_corner_radius_all(4)
	graph_panel.add_theme_stylebox_override("panel", g_style)
	vbox.add_child(graph_panel)

	graph_canvas = Control.new()
	graph_canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	graph_canvas.size_flags_vertical = SIZE_EXPAND_FILL
	graph_canvas.draw.connect(_on_graph_draw)
	graph_panel.add_child(graph_canvas)

	# Saturation summary label below the plot
	lbl_ramp_metrics = Label.new()
	lbl_ramp_metrics.text = "Analyzing saturation points..."
	lbl_ramp_metrics.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	vbox.add_child(lbl_ramp_metrics)


## Builds the Stability & Frame Pacing tab.
func _build_tab_stability() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Stability & Frame Pacing"
	tab_container.add_child(scroll)

	txt_stability = RichTextLabel.new()
	txt_stability.bbcode_enabled = true
	txt_stability.size_flags_horizontal = SIZE_EXPAND_FILL
	txt_stability.size_flags_vertical = SIZE_EXPAND_FILL
	txt_stability.custom_minimum_size = Vector2(800, 450)
	scroll.add_child(txt_stability)


## Builds the Environment & Manifest metadata tab.
func _build_tab_manifest() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Environment & Manifest"
	tab_container.add_child(scroll)

	txt_manifest = RichTextLabel.new()
	txt_manifest.bbcode_enabled = true
	txt_manifest.size_flags_horizontal = SIZE_EXPAND_FILL
	txt_manifest.size_flags_vertical = SIZE_EXPAND_FILL
	txt_manifest.custom_minimum_size = Vector2(800, 450)
	scroll.add_child(txt_manifest)


# ==============================================================================
# SESSION LOADING & MANAGEMENT
# ==============================================================================

## Reloads all available benchmark sessions into the dropdown selector.
func _refresh_session_list() -> void:
	option_sessions.clear()
	available_sessions.clear()

	if typeof(GameSettings) != TYPE_NIL:
		available_sessions = GameSettings.get_all_run_sessions()

	if available_sessions.is_empty():
		# Fall back to legacy single-file summary if present
		if FileAccess.file_exists("res://user_files/benchmark_summary.dat"):
			option_sessions.add_item("Legacy Single Summary (benchmark_summary.dat)")
			current_session_folder = "res://user_files"
			_load_legacy_summary()
			return
		option_sessions.add_item("No benchmark runs found. Please run a benchmark suite first.")
		_display_empty_state()
		return

	for i in range(available_sessions.size()):
		var s = available_sessions[i]
		var run_id = s.get("run_id", "Run %d" % (i + 1))
		var time_str = s.get("timestamp_start", "")
		var label = "%s  (%s)" % [run_id, time_str]
		option_sessions.add_item(label, i)

	# Select the most recent session (index 0) by default
	option_sessions.select(0)
	_load_session(0)


## Handles session selection changes from the dropdown menu.
func _on_session_selected(idx: int) -> void:
	if idx >= 0 and idx < available_sessions.size():
		_load_session(idx)


## Loads CSV and manifest data for the session at [param idx] and refreshes all tabs.
func _load_session(idx: int) -> void:
	var sess = available_sessions[idx]
	current_session_folder = sess.get("folder_path", "")
	current_manifest = sess

	_load_summary_csv(current_session_folder.path_join("summary.csv"))
	_load_ramp_csvs()
	_render_matrix_tab()
	_render_stability_tab()
	_render_manifest_tab()
	_update_ramp_curve_display()


## Loads legacy summary data when no manifest-based session directories exist.
func _load_legacy_summary() -> void:
	_load_summary_csv("res://user_files/benchmark_summary.dat")
	_load_ramp_csvs()
	_render_matrix_tab()
	_render_stability_tab()
	txt_manifest.text = "[color=yellow]Legacy run data. No manifest.json available.[/color]"
	_update_ramp_curve_display()


## Clears all visualizations when no benchmark runs exist on disk.
func _display_empty_state() -> void:
	txt_matrix.text = "[center][color=gray]No benchmark data found. Open Benchmark Hub to run a benchmark suite.[/color][/center]"
	txt_stability.text = ""
	txt_manifest.text = ""
	lbl_ramp_metrics.text = "No timeline data."
	ramp_rendered_points_dod.clear()
	ramp_rendered_points_oop.clear()
	graph_canvas.queue_redraw()


## Opens the active session folder in the OS file manager.
func _on_open_in_os_pressed() -> void:
	if typeof(GameSettings) != TYPE_NIL and not current_session_folder.is_empty():
		GameSettings.open_session_folder_in_os(current_session_folder)


## Deletes the currently selected session folder and refreshes the list.
func _on_delete_session_pressed() -> void:
	if current_session_folder.is_empty(): return
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.delete_session(current_session_folder)
		_refresh_session_list()


# ==============================================================================
# TELEMETRY CSV PARSING
# ==============================================================================

## Parses [param file_path] into [member summary_rows] dictionaries keyed by column header.
func _load_summary_csv(file_path: String) -> void:
	summary_rows.clear()
	if not FileAccess.file_exists(file_path): return

	var f = FileAccess.open(file_path, FileAccess.READ)
	if not f: return

	var lines: Array[String] = []
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if not line.is_empty():
			lines.append(line)
	f.close()

	if lines.size() < 2: return
	var headers = lines[0].split(",")

	for i in range(1, lines.size()):
		var parts = lines[i].split(",")
		var row: Dictionary = {}
		for h in range(headers.size()):
			if h < parts.size():
				row[headers[h].strip_edges()] = parts[h].strip_edges()
		summary_rows.append(row)


## Loads both rendered and headless Ramp-Up frame timelines for the active session.
func _load_ramp_csvs() -> void:
	ramp_rendered_points_dod.clear()
	ramp_rendered_points_oop.clear()
	ramp_headless_points_dod.clear()
	ramp_headless_points_oop.clear()

	# 1. Rendered Timeline
	var rend_path = current_session_folder.path_join("ramp_rendered_frames.csv")
	if not FileAccess.file_exists(rend_path):
		rend_path = "res://user_files/ramp_rendered_frames.csv" # Fallback
	_parse_ramp_file(rend_path, ramp_rendered_points_dod, ramp_rendered_points_oop)

	# 2. Headless Timeline
	var head_path = current_session_folder.path_join("ramp_headless_frames.csv")
	if not FileAccess.file_exists(head_path):
		head_path = "res://user_files/ramp_headless_frames.csv" # Fallback
	_parse_ramp_file(head_path, ramp_headless_points_dod, ramp_headless_points_oop)


## Splits a Ramp-Up CSV timeline into DOD and OOP (EntityCount, FrameTime_ms) series.
func _parse_ramp_file(path: String, out_dod: Array[Vector2], out_oop: Array[Vector2]) -> void:
	if not FileAccess.file_exists(path): return
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return

	var raw_dod: Array[Vector2] = []
	var raw_oop: Array[Vector2] = []

	var _header = f.get_line()
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line.is_empty(): continue
		var parts = line.split(",")
		if parts.size() < 5: continue

		var phase = parts[1].to_upper()
		var entities = parts[3].to_float()
		var frame_ms = parts[4].to_float()

		if phase.contains("DOD"):
			raw_dod.append(Vector2(entities, frame_ms))
		else:
			raw_oop.append(Vector2(entities, frame_ms))
	f.close()

	_downsample_points(raw_dod, out_dod, 800)
	_downsample_points(raw_oop, out_oop, 800)


## Uniformly subsamples [param source] to at most [param max_pts] points for responsive 2D polyline rendering.
func _downsample_points(source: Array[Vector2], dest: Array[Vector2], max_pts: int) -> void:
	var n = source.size()
	if n <= max_pts:
		dest.append_array(source)
		return
	var step = float(n) / float(max_pts)
	for i in range(max_pts):
		var idx = clampi(int(i * step), 0, n - 1)
		dest.append(source[idx])
	dest.append(source[-1])


# ==============================================================================
# TAB VIEW RENDERING
# ==============================================================================

## Renders the speedup highlight cards and full metrics BBCode table.
func _render_matrix_tab() -> void:
	if summary_rows.is_empty():
		txt_matrix.text = "[color=yellow]No summary records found in this run.[/color]"
		return

	# Compute peak speedup multipliers at 10k entities for summary cards
	var peak_speedup_str = "N/A"
	var peak_logic_speedup_str = "N/A"
	
	for r in summary_rows:
		if r["Config"].begins_with("DOD_") and r["Entities"] == "10000":
			for oop in summary_rows:
				if oop["Config"] == r["Config"].replace("DOD_", "OOP_"):
					var dod_fps = r["AvgFPS"].to_float()
					var oop_fps = oop["AvgFPS"].to_float()
					if oop_fps > 0:
						peak_speedup_str = "%.1fx faster" % (dod_fps / oop_fps)
					var dod_us = r["AvgLogic_us"].to_float()
					var oop_us = oop["AvgLogic_us"].to_float()
					if dod_us > 0:
						peak_logic_speedup_str = "%.0fx faster" % (oop_us / dod_us)

	var bb = "[b][font_size=16]ARCHITECTURAL SPEEDUP HIGHLIGHTS[/font_size][/b]\n"
	bb += "[table=3]"
	bb += "[cell][color=#58a6ff][b]Peak Rendered Speedup (10k):[/b][/color] %s[/cell]" % peak_speedup_str
	bb += "[cell][color=#58a6ff][b]Pure Logic Speedup (10k):[/b][/color] %s[/cell]" % peak_logic_speedup_str
	bb += "[cell][color=#58a6ff][b]Tested Configurations:[/b][/color] %d stages[/cell]" % summary_rows.size()
	bb += "[/table]\n\n"

	bb += "[b]FULL SUMMARY METRICS TABLE[/b]\n"
	bb += "[table=9]"
	bb += "[cell][b]Configuration[/b][/cell]"
	bb += "[cell][b]Entities[/b][/cell]"
	bb += "[cell][b]Avg FPS[/b][/cell]"
	bb += "[cell][b]1% Low FPS[/b][/cell]"
	bb += "[cell][b]Frame Time[/b][/cell]"
	bb += "[cell][b]Logic Tick[/b][/cell]"
	bb += "[cell][b]Sync Time[/b][/cell]"
	bb += "[cell][b]RAM (MB)[/b][/cell]"
	bb += "[cell][b]Nodes[/b][/cell]"

	for r in summary_rows:
		var is_dod = r["Config"].contains("DOD")
		var col = "#2ecc71" if is_dod else "#e74c3c"
		bb += "[cell][color=%s]%s[/color][/cell]" % [col, r["Config"]]
		bb += "[cell]%s[/cell]" % r["Entities"]
		bb += "[cell][b]%.1f[/b][/cell]" % r["AvgFPS"].to_float()
		bb += "[cell]%.1f[/cell]" % r["FPS_1pct_Low"].to_float()
		bb += "[cell]%.2f ms[/cell]" % r["AvgFrameTime_ms"].to_float()
		bb += "[cell]%.1f us[/cell]" % r["AvgLogic_us"].to_float()
		bb += "[cell]%.1f us[/cell]" % r["AvgSync_us"].to_float()
		bb += "[cell]%.1f[/cell]" % r["StaticRAM_MB"].to_float()
		bb += "[cell]%s[/cell]" % r["SceneNodes"]

	bb += "[/table]"
	txt_matrix.text = bb


## Renders the frame-pacing standard deviation and consistency rating table.
func _render_stability_tab() -> void:
	if summary_rows.is_empty():
		txt_stability.text = "[color=yellow]No data available.[/color]"
		return

	var bb = "[b][font_size=16]FRAME PACING & JITTER ANALYSIS[/font_size][/b]\n"
	bb += "Frame pacing measures how consistently frames are delivered. High frame time standard deviation (σ) causes noticeable micro-stuttering, even when average FPS appears adequate.\n\n"
	
	bb += "[table=6]"
	bb += "[cell][b]Configuration[/b][/cell]"
	bb += "[cell][b]Avg FPS[/b][/cell]"
	bb += "[cell][b]1% Low FPS[/b][/cell]"
	bb += "[cell][b]StdDev σ (ms)[/b][/cell]"
	bb += "[cell][b]Consistency (%)[/b][/cell]"
	bb += "[cell][b]Pacing Rating[/b][/cell]"

	for r in summary_rows:
		var fps = r["AvgFPS"].to_float()
		var low = r["FPS_1pct_Low"].to_float()
		var sigma = r["StdDev_ms"].to_float()
		var consistency = (low / maxf(fps, 0.001)) * 100.0

		var rating = "[color=#2ecc71]Rock Solid[/color]"
		if consistency < 60.0 or sigma > 1.5:
			rating = "[color=#e74c3c]Severe Jitter[/color]"
		elif consistency < 80.0 or sigma > 0.5:
			rating = "[color=#f39c12]Micro-stutters[/color]"

		var col = "#2ecc71" if r["Config"].contains("DOD") else "#e74c3c"
		bb += "[cell][color=%s]%s[/color][/cell]" % [col, r["Config"]]
		bb += "[cell]%.1f[/cell]" % fps
		bb += "[cell]%.1f[/cell]" % low
		bb += "[cell]±%.3f ms[/cell]" % sigma
		bb += "[cell]%.1f %%[/cell]" % consistency
		bb += "[cell]%s[/cell]" % rating

	bb += "[/table]"
	txt_stability.text = bb


## Renders hardware metadata and benchmark settings recorded in [member current_manifest].
func _render_manifest_tab() -> void:
	if current_manifest.is_empty():
		txt_manifest.text = "[color=gray]No manifest data recorded for this session.[/color]"
		return

	var hw = current_manifest.get("hardware", {})
	var cfg = current_manifest.get("settings_snapshot", {})

	var bb = "[b][font_size=16]RUN METADATA & ENVIRONMENT PROFILE[/font_size][/b]\n\n"
	bb += "[b]Hardware Specifications:[/b]\n"
	bb += "[code]"
	bb += "GPU Adapter     : %s\n" % hw.get("gpu_adapter", "Unknown")
	bb += "GPU Vendor      : %s\n" % hw.get("gpu_vendor", "Unknown")
	bb += "CPU Model       : %s (%s cores)\n" % [hw.get("cpu_name", "Unknown"), str(hw.get("cpu_cores", "?"))]
	bb += "Operating System: %s %s\n" % [hw.get("os_name", ""), hw.get("os_version", "")]
	bb += "Engine Platform : %s\n" % hw.get("engine_version", "")
	bb += "[/code]\n"

	bb += "[b]Benchmark Configuration Snapshot:[/b]\n"
	bb += "[code]"
	bb += "Session ID      : %s\n" % current_manifest.get("run_id", "")
	bb += "Timestamp Start : %s\n" % current_manifest.get("timestamp_start", "")
	bb += "Timestamp End   : %s\n" % current_manifest.get("timestamp_end", "In Progress")
	bb += "Workload Profile: %s\n" % cfg.get("synthetic_workload", "Standard")
	bb += "Mesh Mode       : %s\n" % cfg.get("synthetic_mesh_mode", "Full Matrix")
	bb += "Sample Duration : %s s per stage\n" % str(cfg.get("sample_duration_s", 4.0))
	bb += "Ramp Growth     : %s (Base: %s/s, Accel: +%s/s²)\n" % [
		cfg.get("ramp_growth_mode", "Progressive"),
		str(cfg.get("ramp_base_spawn_rate", 300)),
		str(cfg.get("ramp_acceleration_factor", 75))
	]
	bb += "[/code]"
	txt_manifest.text = bb


# ==============================================================================
# RAMP-UP 2D TIMELINE VISUALIZATION (_DRAW)
# ==============================================================================

## Updates the saturation capacity summary label and triggers a 2D canvas redraw.
func _update_ramp_curve_display() -> void:
	var is_rendered = (option_ramp_source.selected == 0)
	var dod_pts = ramp_rendered_points_dod if is_rendered else ramp_headless_points_dod
	var oop_pts = ramp_rendered_points_oop if is_rendered else ramp_headless_points_oop

	var dod_max = 0
	var oop_max = 0
	for p in dod_pts: dod_max = maxi(dod_max, int(p.x))
	for p in oop_pts: oop_max = maxi(oop_max, int(p.x))

	var ratio_str = "%.1fx" % (float(dod_max) / maxf(float(oop_max), 1.0))
	lbl_ramp_metrics.text = "Saturation Capacity: DOD Max = %d entities | OOP Max = %d entities | Headroom Ratio = %s capacity" % [
		dod_max, oop_max, ratio_str
	]
	graph_canvas.queue_redraw()


## Custom 2D draw callback plotting DOD vs. OOP frame time against entity population.
func _on_graph_draw() -> void:
	var rect = graph_canvas.get_rect()
	var w = rect.size.x
	var h = rect.size.y
	if w < 100 or h < 100: return

	var pad_l = 70.0
	var pad_r = 40.0
	var pad_t = 30.0
	var pad_b = 40.0
	var plot_w = w - pad_l - pad_r
	var plot_h = h - pad_t - pad_b

	var is_rendered = (option_ramp_source.selected == 0)
	var dod_pts = ramp_rendered_points_dod if is_rendered else ramp_headless_points_dod
	var oop_pts = ramp_rendered_points_oop if is_rendered else ramp_headless_points_oop

	# Plot background and border
	graph_canvas.draw_rect(Rect2(pad_l, pad_t, plot_w, plot_h), Color(0.06, 0.08, 0.12, 1.0))
	graph_canvas.draw_rect(Rect2(pad_l, pad_t, plot_w, plot_h), Color(0.25, 0.3, 0.4, 0.8), false, 1.0)

	# Calculate dynamic axis bounds
	var max_x = 1000.0
	var max_y = 35.0
	for p in dod_pts:
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	for p in oop_pts:
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	max_y = maxf(max_y * 1.15, 25.0)

	var font = ThemeDB.fallback_font

	# 16.67 ms (60 FPS) target frame budget reference line
	var y_60 = pad_t + plot_h - (16.6667 / max_y) * plot_h
	if y_60 >= pad_t and y_60 <= pad_t + plot_h:
		graph_canvas.draw_line(Vector2(pad_l, y_60), Vector2(pad_l + plot_w, y_60), Color(0.95, 0.6, 0.1, 0.85), 2.0)
		graph_canvas.draw_string(font, Vector2(pad_l + 10, y_60 - 6), "60 FPS Target Budget (16.67 ms)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.6, 0.1))

	# Y-axis labels
	graph_canvas.draw_string(font, Vector2(10, pad_t + 12), "%.1f ms" % max_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
	graph_canvas.draw_string(font, Vector2(10, pad_t + plot_h), "0.0 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))

	# X-axis labels
	graph_canvas.draw_string(font, Vector2(pad_l, pad_t + plot_h + 24), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.8))
	graph_canvas.draw_string(font, Vector2(pad_l + plot_w - 70, pad_t + plot_h + 24), "%d agents" % int(max_x), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.8))

	# Project data points into canvas screen space
	var screen_dod: PackedVector2Array = []
	for p in dod_pts:
		var px = pad_l + (p.x / max_x) * plot_w
		var py = pad_t + plot_h - (p.y / max_y) * plot_h
		screen_dod.append(Vector2(px, py))

	var screen_oop: PackedVector2Array = []
	for p in oop_pts:
		var px = pad_l + (p.x / max_x) * plot_w
		var py = pad_t + plot_h - (p.y / max_y) * plot_h
		screen_oop.append(Vector2(px, py))

	if screen_dod.size() > 1:
		graph_canvas.draw_polyline(screen_dod, Color(0.2, 0.85, 0.4), 2.5, true)
	if screen_oop.size() > 1:
		graph_canvas.draw_polyline(screen_oop, Color(0.9, 0.25, 0.3), 2.5, true)
