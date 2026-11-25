## Global Autoload singleton managing benchmark configuration, session storage, and suite orchestration.
##
## Persists display and workload settings to [code]user://settings.cfg[/code], generates timestamped
## session directories with [code]manifest.json[/code] and [code]summary.csv[/code] telemetry, and
## drives multi-stage sequential benchmark runs.
extends Node

const SETTINGS_PATH: String = "user://settings.cfg"


## Resolves the root output directory for benchmark sessions (editor vs. standalone Release build).
func get_runs_base_dir() -> String:
	if OS.has_feature("editor"):
		return "res://user_files/runs"
	return OS.get_executable_path().get_base_dir().path_join("benchmark_runs")


## Resolves the path to the backward-compatible cumulative summary file.
func get_legacy_summary_path() -> String:
	return get_runs_base_dir().get_base_dir().path_join("benchmark_summary.dat")


# --- 1. Display & Engine Settings ---
var vsync_enabled: bool = false
var window_mode: int = DisplayServer.WINDOW_MODE_WINDOWED
var max_fps_limit: int = 0
var benchmark_profile: int = 0 # 0 = Quick (4 s), 1 = Standard (10 s), 2 = Soak (300 s)

# --- 2. Synthetic Benchmark Settings ---
# Batching mode: 0 = Full Matrix (1 & 5 Meshes), 1 = Single-Mesh Only, 2 = Multi-Mesh Only
var synthetic_mesh_mode: int = 0
# Entity workload tier: 0 = Standard (1k, 5k, 10k), 1 = Lightweight (500, 1k, 2.5k), 2 = Extreme (5k, 10k, 25k)
var synthetic_workload: int = 0

# --- 3. Dynamic Ramp-Up Emitter Settings ---
# Spawn growth model: 0 = Progressive Acceleration, 1 = Constant Linear
var ramp_growth_mode: int = 0
var ramp_base_spawn_rate: float = 300.0
var ramp_acceleration_factor: float = 75.0

# --- 4. Session Management & Suite Orchestrator ---
var current_session_folder: String = ""
var current_run_id: String = ""
var current_manifest: Dictionary = {}
var benchmark_queue: Array[String] = []
var is_running_full_suite: bool = false
var force_greybox_benchmark: bool = false


## Loads saved settings from disk, applies window/V-Sync rules, and ensures output folders exist.
func _ready() -> void:
	load_settings()
	apply_settings()
	_ensure_runs_directory()


## Applies V-Sync, window mode, and frame rate cap settings to the active engine instance.
func apply_settings() -> void:
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(window_mode)
	Engine.max_fps = max_fps_limit


## Returns the per-step sampling duration in seconds for the selected benchmark profile.
func get_sample_duration() -> float:
	match benchmark_profile:
		0: return 4.0
		1: return 10.0
		2: return 300.0
		_: return 4.0


# --- Dynamic Synthetic Test Matrix Generator ---

## Generates the ordered list of synthetic A/B test step dictionaries for the active settings.
func get_synthetic_configs(is_headless: bool = false) -> Array[Dictionary]:
	var prefix = "Headless_" if is_headless else ""
	var counts: Array[int] = []
	match synthetic_workload:
		0: counts = [1000, 5000, 10000]  # Standard
		1: counts = [500, 1000, 2500]    # Lightweight
		2: counts = [5000, 10000, 25000] # Extreme
		_: counts = [1000, 5000, 10000]

	var configs: Array[Dictionary] = []
	var count_labels = { 500: "500", 1000: "1k", 2500: "2.5k", 5000: "5k", 10000: "10k", 25000: "25k" }

	# 1. DOD Single-Mesh
	if synthetic_mesh_mode == 0 or synthetic_mesh_mode == 1:
		for c in counts:
			var lbl = count_labels.get(c, str(c))
			configs.append({"variant": 0, "count": c, "name": "%sDOD_1Mesh_%s" % [prefix, lbl]})

	# 2. DOD Multi-Mesh
	if synthetic_mesh_mode == 0 or synthetic_mesh_mode == 2:
		for c in counts:
			var lbl = count_labels.get(c, str(c))
			configs.append({"variant": 1, "count": c, "name": "%sDOD_5Mesh_%s" % [prefix, lbl]})

	# 3. OOP Single-Mesh
	if synthetic_mesh_mode == 0 or synthetic_mesh_mode == 1:
		for c in counts:
			var lbl = count_labels.get(c, str(c))
			configs.append({"variant": 2, "count": c, "name": "%sOOP_1Mesh_%s" % [prefix, lbl]})

	# 4. OOP Multi-Mesh
	if synthetic_mesh_mode == 0 or synthetic_mesh_mode == 2:
		for c in counts:
			var lbl = count_labels.get(c, str(c))
			configs.append({"variant": 3, "count": c, "name": "%sOOP_5Mesh_%s" % [prefix, lbl]})

	return configs


# ==============================================================================
# SESSION MANAGEMENT & TIMESTAMPED RUN DIRECTORIES
# ==============================================================================

## Creates the base runs directory if it does not already exist.
func _ensure_runs_directory() -> void:
	if not DirAccess.dir_exists_absolute(get_runs_base_dir()):
		DirAccess.make_dir_recursive_absolute(get_runs_base_dir())


## Initializes a new timestamped session directory with [code]manifest.json[/code] and [code]summary.csv[/code].
func create_new_session(custom_label: String = "run") -> String:
	_ensure_runs_directory()
	
	var dt = Time.get_datetime_dict_from_system()
	var timestamp_str = "%04d-%02d-%02d_%02d-%02d-%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]
	
	# Build a human-readable session identifier (e.g., run_2026-11-12_22-58-26_full_suite_release)
	var safe_label = custom_label.validate_filename()
	current_run_id = "run_%s_%s" % [timestamp_str, safe_label]
	current_session_folder = get_runs_base_dir().path_join(current_run_id)
	
	DirAccess.make_dir_recursive_absolute(current_session_folder)
	DirAccess.make_dir_recursive_absolute(current_session_folder.path_join("raw_frames"))
	
	# Create and initialize session manifest.json
	_init_session_manifest(timestamp_str, custom_label)
	
	# Initialize empty summary.csv with column headers
	var sum_path = current_session_folder.path_join("summary.csv")
	var f = FileAccess.open(sum_path, FileAccess.WRITE)
	if f:
		f.store_line("Config,Entities,FramesSampled,AvgFPS,StdDev_ms,FPS_1pct_Low,FPS_01pct_Low,AvgFrameTime_ms,AvgLogic_us,MinLogic_us,MaxLogic_us,AvgSync_us,AvgTotalSim_us,SceneNodes,StaticRAM_MB")
		f.close()
		
	print("[GameSettings] New benchmark session initialized: %s" % current_session_folder)
	return current_session_folder


## Returns the active session folder path, creating a fallback session if none is active.
func ensure_session_exists(fallback_label: String = "manual") -> String:
	if current_session_folder.is_empty() or not DirAccess.dir_exists_absolute(current_session_folder):
		return create_new_session(fallback_label)
	return current_session_folder


## Returns the current session root directory path.
func get_current_session_folder() -> String:
	return ensure_session_exists("single_run")


## Returns the [code]raw_frames/[/code] subdirectory path for per-frame CSV exports.
func get_current_raw_frames_folder() -> String:
	var sess = get_current_session_folder()
	var raw_dir = sess.path_join("raw_frames")
	if not DirAccess.dir_exists_absolute(raw_dir):
		DirAccess.make_dir_recursive_absolute(raw_dir)
	return raw_dir


## Populates hardware specifications and active configuration snapshot into [member current_manifest].
func _init_session_manifest(_timestamp_str: String, label: String) -> void:
	var workload_names = ["Standard (1k, 5k, 10k)", "Lightweight (500, 1k, 2.5k)", "Extreme (5k, 10k, 25k)"]
	var mesh_mode_names = ["Full Matrix (1 & 5 Meshes)", "Single-Mesh Only (1 Draw Call)", "Multi-Mesh Only (5 Draw Calls)"]
	var growth_names = ["Progressive Acceleration", "Constant Linear"]
	
	current_manifest = {
		"run_id": current_run_id,
		"label": label,
		"timestamp_start": Time.get_datetime_string_from_system(false, true),
		"timestamp_end": "",
		"status": "in_progress",
		"hardware": {
			"gpu_adapter": RenderingServer.get_video_adapter_name(),
			"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
			"cpu_name": OS.get_processor_name(),
			"cpu_cores": OS.get_processor_count(),
			"os_name": OS.get_name(),
			"os_version": OS.get_version(),
			"engine_version": Engine.get_version_info().get("string", "Godot 4.x")
		},
		"settings_snapshot": {
			"vsync_enabled": vsync_enabled,
			"sample_duration_s": get_sample_duration(),
			"synthetic_workload": workload_names[clampi(synthetic_workload, 0, 2)],
			"synthetic_mesh_mode": mesh_mode_names[clampi(synthetic_mesh_mode, 0, 2)],
			"ramp_growth_mode": growth_names[clampi(ramp_growth_mode, 0, 1)],
			"ramp_base_spawn_rate": ramp_base_spawn_rate,
			"ramp_acceleration_factor": ramp_acceleration_factor,
			"max_fps_limit": max_fps_limit
		},
		"stages_planned": benchmark_queue.duplicate(),
		"stages_completed": [],
		"files": {
			"summary_csv": "summary.csv",
			"raw_frames_dir": "raw_frames/"
		}
	}
	_save_manifest()


## Serializes [member current_manifest] to [code]manifest.json[/code] in the active session directory.
func _save_manifest() -> void:
	if current_session_folder.is_empty(): return
	var manifest_path = current_session_folder.path_join("manifest.json")
	var f = FileAccess.open(manifest_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(current_manifest, "\t"))
		f.close()


## Appends completed stage summary rows to the active session's [code]summary.csv[/code].
func append_summary_results(results: Array[Dictionary]) -> void:
	var sess = get_current_session_folder()
	var path = sess.path_join("summary.csv")
	var file_exists = FileAccess.file_exists(path)
	
	var f = FileAccess.open(path, FileAccess.READ_WRITE if file_exists else FileAccess.WRITE)
	if f:
		if file_exists:
			f.seek_end()
		else:
			f.store_line("Config,Entities,FramesSampled,AvgFPS,StdDev_ms,FPS_1pct_Low,FPS_01pct_Low,AvgFrameTime_ms,AvgLogic_us,MinLogic_us,MaxLogic_us,AvgSync_us,AvgTotalSim_us,SceneNodes,StaticRAM_MB")
		
		for r in results:
			f.store_line("%s,%d,%d,%.2f,%.4f,%.2f,%.2f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f" % [
				r["name"], r["entities"], r["frames"],
				r["avg_fps"], r["std_dev_ms"], r["fps_1_low"], r["fps_01_low"], r["avg_frame_ms"],
				r["avg_logic_us"], r["min_logic_us"], r["max_logic_us"],
				r["avg_sync_us"], r["avg_total_us"], r["nodes"], r["ram_mb"]
			])
		f.close()

	# Mirror records to legacy root summary file for backward compatibility
	_mirror_to_legacy_summary(results)


## Appends summary records to the legacy root summary file.
func _mirror_to_legacy_summary(results: Array[Dictionary]) -> void:
	var file_exists = FileAccess.file_exists(get_legacy_summary_path())
	var f = FileAccess.open(get_legacy_summary_path(), FileAccess.READ_WRITE if file_exists else FileAccess.WRITE)
	if f:
		if file_exists: f.seek_end()
		else: f.store_line("Config,Entities,FramesSampled,AvgFPS,StdDev_ms,FPS_1pct_Low,FPS_01pct_Low,AvgFrameTime_ms,AvgLogic_us,MinLogic_us,MaxLogic_us,AvgSync_us,AvgTotalSim_us,SceneNodes,StaticRAM_MB")
		for r in results:
			f.store_line("%s,%d,%d,%.2f,%.4f,%.2f,%.2f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f" % [
				r["name"], r["entities"], r["frames"],
				r["avg_fps"], r["std_dev_ms"], r["fps_1_low"], r["fps_01_low"], r["avg_frame_ms"],
				r["avg_logic_us"], r["min_logic_us"], r["max_logic_us"],
				r["avg_sync_us"], r["avg_total_us"], r["nodes"], r["ram_mb"]
			])
		f.close()


# ==============================================================================
# MULTI-STAGE SUITE ORCHESTRATOR
# ==============================================================================

## Starts an automated multi-scene benchmark run under a shared session folder.
func start_benchmark_suite(scene_paths: Array[String], session_label: String = "full_suite") -> void:
	benchmark_queue = scene_paths.duplicate()
	is_running_full_suite = true
	create_new_session(session_label)
	advance_benchmark_suite()


## Transitions to the next queued benchmark scene or opens the results screen when complete.
func advance_benchmark_suite() -> void:
	if benchmark_queue.is_empty():
		finalize_session()
		get_tree().change_scene_to_file("res://benchmark_results.tscn")
	else:
		var next_scene = benchmark_queue.pop_front()
		if current_manifest.has("stages_completed"):
			current_manifest["stages_completed"].append(next_scene)
			_save_manifest()
		get_tree().change_scene_to_file(next_scene)


## Called by each benchmark scene upon completion to advance the queue or finish the session.
func finish_current_benchmark() -> void:
	if is_running_full_suite and not benchmark_queue.is_empty():
		advance_benchmark_suite()
	else:
		finalize_session()
		get_tree().change_scene_to_file("res://benchmark_results.tscn")


## Marks the current session manifest as completed and writes the final end timestamp.
func finalize_session() -> void:
	is_running_full_suite = false
	if not current_manifest.is_empty():
		current_manifest["timestamp_end"] = Time.get_datetime_string_from_system(false, true)
		current_manifest["status"] = "completed"
		_save_manifest()
	print("[GameSettings] Benchmark session finalized: %s" % current_run_id)


# ==============================================================================
# SESSION INDEXING & FILESYSTEM UTILITIES
# ==============================================================================

## Scans the runs directory and returns all valid session manifests sorted newest first.
func get_all_run_sessions() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(get_runs_base_dir()):
		return runs
		
	var dir = DirAccess.open(get_runs_base_dir())
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry != "." and entry != "..":
				var folder_path = get_runs_base_dir().path_join(entry)
				var manifest_file = folder_path.path_join("manifest.json")
				if FileAccess.file_exists(manifest_file):
					var f = FileAccess.open(manifest_file, FileAccess.READ)
					if f:
						var parsed = JSON.parse_string(f.get_as_text())
						f.close()
						if typeof(parsed) == TYPE_DICTIONARY:
							parsed["folder_path"] = folder_path
							runs.append(parsed)
			entry = dir.get_next()
		dir.list_dir_end()

	# Sort sessions from newest to oldest by start timestamp
	runs.sort_custom(func(a, b): return a.get("timestamp_start", "") > b.get("timestamp_start", ""))
	return runs


## Opens the specified session directory in the host operating system's file explorer.
func open_session_folder_in_os(folder_path: String = "") -> void:
	var target = folder_path if not folder_path.is_empty() else current_session_folder
	if target.is_empty():
		target = get_runs_base_dir()
	var global_path = ProjectSettings.globalize_path(target)
	OS.shell_open(global_path)


## Permanently deletes a benchmark session directory and all its contents.
func delete_session(folder_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(folder_path):
		return false
	_delete_dir_recursive(folder_path)
	if current_session_folder == folder_path:
		current_session_folder = ""
		current_run_id = ""
		current_manifest.clear()
	return true


## Recursively removes files and subdirectories inside [param path].
func _delete_dir_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = path.path_join(file_name)
				if dir.current_is_dir():
					_delete_dir_recursive(full_path)
				else:
					DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)


# ==============================================================================
# PERSISTENT CONFIGURATION STORAGE (settings.cfg)
# ==============================================================================

## Saves all current display and benchmark settings to [code]user://settings.cfg[/code].
func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "max_fps_limit", max_fps_limit)
	config.set_value("benchmark", "benchmark_profile", benchmark_profile)
	config.set_value("synthetic", "synthetic_mesh_mode", synthetic_mesh_mode)
	config.set_value("synthetic", "synthetic_workload", synthetic_workload)
	config.set_value("ramp_up", "ramp_growth_mode", ramp_growth_mode)
	config.set_value("ramp_up", "ramp_base_spawn_rate", ramp_base_spawn_rate)
	config.set_value("ramp_up", "ramp_acceleration_factor", ramp_acceleration_factor)
	config.save(SETTINGS_PATH)


## Loads settings from [code]user://settings.cfg[/code], writing defaults if missing.
func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		vsync_enabled = config.get_value("display", "vsync_enabled", false)
		window_mode = config.get_value("display", "window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
		max_fps_limit = config.get_value("display", "max_fps_limit", 0)
		benchmark_profile = config.get_value("benchmark", "benchmark_profile", 0)
		synthetic_mesh_mode = config.get_value("synthetic", "synthetic_mesh_mode", 0)
		synthetic_workload = config.get_value("synthetic", "synthetic_workload", 0)
		ramp_growth_mode = config.get_value("ramp_up", "ramp_growth_mode", 0)
		ramp_base_spawn_rate = config.get_value("ramp_up", "ramp_base_spawn_rate", 300.0)
		ramp_acceleration_factor = config.get_value("ramp_up", "ramp_acceleration_factor", 75.0)
	else:
		save_settings()
