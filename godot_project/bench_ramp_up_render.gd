## Dynamic Rendered Emitter Ramp-Up Benchmark determining 60 FPS saturation breaking points.
##
## Continuously spawns uniform 5-color cube agents using a clamped frame accumulator
## until frame time exceeds the 60 Hz budget threshold (17.5 ms) for 5.0 consecutive seconds.
extends Node3D

@onready var bridge: SimulationBridge = $SimulationBridge

# --- Saturation Threshold Constants ---
const BUDGET_LIMIT_MS: float = 17.5    # 60 Hz frame time ceiling (~57 FPS with tolerance)
const FAIL_DURATION: float = 5.0       # Consecutive seconds above budget required to trigger saturation
const SPAWN_RATE: float = 300.0        # Default base spawn rate (+300 entities/s)
const START_DELAY: float = 1.5
const NUM_MESH_TYPES: int = 5

## Sequential ramp-up execution phases.
enum Phase { DOD_RAMP, OOP_RAMP, FINISHED }
var current_phase: Phase = Phase.DOD_RAMP

# Emitter and hysteresis saturation state
var entity_count: int = 0
var spawn_accumulator: float = 0.0
var fail_timer: float = 0.0
var phase_elapsed_time: float = 0.0
var is_starting: bool = true
var start_countdown: float = START_DELAY

# Recorded breaking-point entity counts
var dod_saturation_count: int = 0
var oop_saturation_count: int = 0

# Rendering resources (5 color-coded 12-triangle cube archetypes)
var type_meshes: Array[Mesh] = []
var extra_mmis: Array[MultiMeshInstance3D] = []

var oop_container: Node3D = null
var oop_nodes: Array[MeshInstance3D] = []
var oop_velocities: Array[Vector3] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Telemetry and CSV export state
var last_logic_us: float = 0.0
var last_sync_us: float = 0.0
var frame_index: int = 0
var f_raw: FileAccess = null
var phase_frame_times: Array[float] = []
var phase_logic_times: float = 0.0
var phase_sync_times: float = 0.0
var phase_min_logic_us: float = 999999999.0
var phase_max_logic_us: float = 0.0
var summary_results: Array[Dictionary] = []
var current_spawn_rate: float = 0.0

# HUD widgets
var hud_label: RichTextLabel
var progress_bar: ProgressBar


## Initializes priority, cube MultiMesh resources, CSV output, and starts the DOD ramp phase.
func _ready() -> void:
	process_priority = -10
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.apply_settings()

	rng.seed = 1337
	_init_resources()
	_init_csv_storage()
	_build_telemetry_hud()
	_start_phase(Phase.DOD_RAMP)


## Aborts the ramp-up benchmark when Escape is pressed.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_abort_benchmark()


## Initializes five color-coded cube meshes, MultiMesh instances, and the OOP node container.
func _init_resources() -> void:
	var colors = [
		Color(0.2, 0.85, 0.4), Color(0.2, 0.6, 1.0), Color(0.95, 0.6, 0.1),
		Color(0.9, 0.25, 0.3), Color(0.7, 0.3, 0.95)
	]
	type_meshes.clear()
	extra_mmis.clear()

	for i in range(NUM_MESH_TYPES):
		var cube = BoxMesh.new()
		cube.size = Vector3(0.55, 0.55, 0.55)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		cube.surface_set_material(0, mat)
		type_meshes.append(cube)

		var mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.use_custom_data = false
		mm.mesh = cube
		mmi.multimesh = mm
		mmi.visible = false
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-60.0, -10.0, -60.0), Vector3(120.0, 20.0, 120.0))
		mmi.extra_cull_margin = 50.0
		add_child(mmi)
		extra_mmis.append(mmi)

	oop_container = Node3D.new()
	oop_container.name = "OOP_Ramp_Container"
	oop_container.visible = false
	add_child(oop_container)


## Opens [code]ramp_rendered_frames.csv[/code] in the active session directory for streaming timeline logs.
func _init_csv_storage() -> void:
	var sess_dir: String = "res://user_files"
	if typeof(GameSettings) != TYPE_NIL:
		sess_dir = GameSettings.get_current_session_folder()
	else:
		var dir = DirAccess.open("res://")
		if not dir.dir_exists("user_files"):
			dir.make_dir("user_files")

	var path = sess_dir.path_join("ramp_rendered_frames.csv")
	f_raw = FileAccess.open(path, FileAccess.WRITE)
	if f_raw:
		f_raw.store_line("FrameIndex,Phase,ElapsedTime_s,EntityCount,FrameTime_ms,InstantFPS,Logic_us,Sync_us,TotalSim_us,SceneNodes,StaticRAM_MB")


## Resets counters and prepares active rendering structures for phase [param p].
func _start_phase(p: Phase) -> void:
	current_phase = p
	entity_count = 0
	spawn_accumulator = 0.0
	fail_timer = 0.0
	phase_elapsed_time = 0.0
	is_starting = true
	start_countdown = START_DELAY
	phase_frame_times.clear()
	phase_logic_times = 0.0
	phase_sync_times = 0.0
	phase_min_logic_us = 999999999.0
	phase_max_logic_us = 0.0

	for node in oop_nodes:
		node.free()
	oop_nodes.clear()
	oop_velocities.clear()

	if current_phase == Phase.DOD_RAMP:
		oop_container.visible = false
		for mmi in extra_mmis:
			mmi.visible = true
			mmi.multimesh.instance_count = 0
		bridge.set_process(true)
		bridge.spawn_agents(0)
	elif current_phase == Phase.OOP_RAMP:
		for mmi in extra_mmis:
			mmi.visible = false
		bridge.set_process(false)
		oop_container.visible = true


## Emits new entities, updates simulation and GPU buffers, logs telemetry, and checks saturation.
func _process(delta: float) -> void:
	frame_index += 1
	var frame_ms = delta * 1000.0

	if is_starting:
		start_countdown -= delta
		if start_countdown <= 0.0:
			is_starting = false
			_spawn_entities(100)
		_update_hud(frame_ms)
		return

	phase_elapsed_time += delta

	# Compute spawn rate according to configured linear or progressive growth model
	var base_rate = GameSettings.ramp_base_spawn_rate if typeof(GameSettings) != TYPE_NIL else 300.0
	var accel_factor = GameSettings.ramp_acceleration_factor if typeof(GameSettings) != TYPE_NIL else 75.0
	var is_progressive = (GameSettings.ramp_growth_mode == 0) if typeof(GameSettings) != TYPE_NIL else true

	current_spawn_rate = base_rate
	if is_progressive:
		current_spawn_rate += accel_factor * phase_elapsed_time

	spawn_accumulator += current_spawn_rate * delta
	var to_spawn = int(spawn_accumulator)
	
	if to_spawn > 0:
		var spawn_clamped = mini(to_spawn, 250)
		spawn_accumulator -= float(spawn_clamped)
		_spawn_entities(spawn_clamped)

	# Run simulation step and MultiMesh GPU synchronization
	if current_phase == Phase.DOD_RAMP:
		last_logic_us = bridge.get_last_tick_microseconds()
		var t0 = Time.get_ticks_usec()
		var chunk = int(float(entity_count) / float(NUM_MESH_TYPES))
		if bridge.has_method("sync_to_multimesh_range"):
			for t in range(NUM_MESH_TYPES):
				bridge.sync_to_multimesh_range(extra_mmis[t].multimesh, t * chunk, chunk)
		else:
			bridge.sync_to_multimesh(extra_mmis[0].multimesh)
		last_sync_us = float(Time.get_ticks_usec() - t0)
	elif current_phase == Phase.OOP_RAMP:
		var t0 = Time.get_ticks_usec()
		_tick_oop(delta)
		last_logic_us = float(Time.get_ticks_usec() - t0)
		last_sync_us = 0.0

	# Record per-frame timeline entry
	var ram_mb = bridge.get_process_memory_mb() if bridge.has_method("get_process_memory_mb") else (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))
	var nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var phase_str = "DOD" if current_phase == Phase.DOD_RAMP else "OOP"
	
	if f_raw:
		f_raw.store_line("%d,%s,%.4f,%d,%.4f,%.2f,%.2f,%.2f,%.2f,%d,%.2f" % [
			frame_index, phase_str, phase_elapsed_time, entity_count,
			frame_ms, 1000.0 / maxf(frame_ms, 0.0001),
			last_logic_us, last_sync_us, last_logic_us + last_sync_us,
			nodes, ram_mb
		])

	phase_frame_times.append(frame_ms)
	phase_logic_times += last_logic_us
	phase_min_logic_us = minf(phase_min_logic_us, last_logic_us)
	phase_max_logic_us = maxf(phase_max_logic_us, last_logic_us)
	phase_sync_times += last_sync_us

	_check_saturation(frame_ms, delta)
	_update_hud(frame_ms)


## Incrementally appends [param count] new agents to the active DOD or OOP simulation.
func _spawn_entities(count: int) -> void:
	entity_count += count

	if current_phase == Phase.DOD_RAMP:
		var chunk = int(float(entity_count) / float(NUM_MESH_TYPES))
		for mmi in extra_mmis:
			mmi.multimesh.instance_count = chunk
		bridge.add_agents(count)
	else:
		for i in range(count):
			var agent = MeshInstance3D.new()
			agent.mesh = type_meshes[i % NUM_MESH_TYPES]
			agent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			agent.position = Vector3(rng.randf_range(-45.0, 45.0), 0.0, rng.randf_range(-45.0, 45.0))
			var vel = Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
			oop_container.add_child(agent)
			oop_nodes.append(agent)
			oop_velocities.append(vel)


## Updates the 5-second hysteresis fail timer when frame time exceeds [constant BUDGET_LIMIT_MS].
func _check_saturation(frame_ms: float, delta: float) -> void:
	if frame_ms > BUDGET_LIMIT_MS:
		fail_timer += delta
	else:
		fail_timer = maxf(0.0, fail_timer - delta * 0.5)

	if fail_timer >= FAIL_DURATION:
		_on_phase_saturated()


## Records saturation summary metrics and transitions from DOD to OOP or finishes the benchmark.
func _on_phase_saturated() -> void:
	var n_frames = phase_frame_times.size()
	if n_frames == 0: return

	var sum_frame = 0.0
	for ft in phase_frame_times: sum_frame += ft
	var avg_frame = sum_frame / n_frames
	var avg_fps = 1000.0 / maxf(avg_frame, 0.0001)

	phase_frame_times.sort()
	var idx_99 = clampi(int(ceil(n_frames * 0.99)) - 1, 0, n_frames - 1)
	var fps_1_low = 1000.0 / maxf(phase_frame_times[idx_99], 0.0001)

	var phase_name = "Ramp_DOD_5Mesh_Rendered" if current_phase == Phase.DOD_RAMP else "Ramp_OOP_5Mesh_Rendered"
	if current_phase == Phase.DOD_RAMP:
		dod_saturation_count = entity_count
	else:
		oop_saturation_count = entity_count

	summary_results.append({
		"name": phase_name,
		"entities": entity_count,
		"frames": n_frames,
		"avg_fps": avg_fps,
		"avg_frame_ms": avg_frame,
		"std_dev_ms": 0.0,
		"fps_1_low": fps_1_low,
		"fps_01_low": 0.0,
		"avg_logic_us": phase_logic_times / n_frames,
		"min_logic_us": phase_min_logic_us if n_frames > 0 else 0.0,
		"max_logic_us": phase_max_logic_us,
		"avg_sync_us": phase_sync_times / n_frames,
		"avg_total_us": (phase_logic_times + phase_sync_times) / n_frames,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"ram_mb": bridge.get_process_memory_mb() if bridge.has_method("get_process_memory_mb") else (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))
	})

	if current_phase == Phase.DOD_RAMP:
		print("[RampUp] DOD saturated at N = %d. Transitioning to OOP..." % dod_saturation_count)
		_start_phase(Phase.OOP_RAMP)
	else:
		print("[RampUp] OOP saturated at N = %d. Finishing benchmark." % oop_saturation_count)
		_finish_benchmark()


## Closes the raw CSV file, writes summary records, and advances the suite.
func _finish_benchmark() -> void:
	current_phase = Phase.FINISHED
	set_process(false)
	if f_raw:
		f_raw.close()
		f_raw = null

	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.append_summary_results(summary_results)
		GameSettings.finish_current_benchmark()


## Aborts the benchmark immediately, closes open CSV handles, and returns to the hub.
func _abort_benchmark() -> void:
	if f_raw:
		f_raw.close()
		f_raw = null
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.is_running_full_suite = false
	get_tree().change_scene_to_file("res://benchmark_hub.tscn")


## Constructs the telemetry HUD overlay and fail-streak progress bar.
func _build_telemetry_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(480, 270)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.90)
	style.border_color = Color(0.95, 0.55, 0.15, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	hud_label = RichTextLabel.new()
	hud_label.bbcode_enabled = true
	hud_label.fit_content = true
	hud_label.custom_minimum_size = Vector2(450, 200)
	vbox.add_child(hud_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = FAIL_DURATION
	progress_bar.custom_minimum_size = Vector2(450, 20)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.95, 0.3, 0.2)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	vbox.add_child(progress_bar)


## Updates the telemetry HUD with active entity population, spawn rate, and saturation status.
func _update_hud(frame_ms: float) -> void:
	var fps = Engine.get_frames_per_second()
	var ram_mb = bridge.get_process_memory_mb() if bridge.has_method("get_process_memory_mb") else (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))
	var nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var phase_title = "[color=#2ecc71]PHASE 1/2: DOD RAMP-UP (5-Mesh)[/color]" if current_phase == Phase.DOD_RAMP else "[color=#e74c3c]PHASE 2/2: OOP RAMP-UP (5-Mesh)[/color]"

	progress_bar.value = fail_timer

	var status_text = ""
	if is_starting:
		status_text = "[color=yellow]Starting in %.1f s...[/color]" % start_countdown
	elif fail_timer > 0.0:
		status_text = "[color=red][b]FAIL STREAK: %.1f / %.1f s (Exceeds 17.5 ms)[/b][/color]" % [fail_timer, FAIL_DURATION]
	else:
		status_text = "[color=green]HEALTHY (Under 17.5 ms Budget)[/color]"

	var is_progressive = (GameSettings.ramp_growth_mode == 0) if typeof(GameSettings) != TYPE_NIL else true
	var growth_str = "Progressive (+%.0f/s²)" % GameSettings.ramp_acceleration_factor if is_progressive else "Constant Linear"

	var txt = "[b]DYNAMIC EMITTER RAMP-UP BENCHMARK[/b]\n"
	txt += phase_title + " | " + status_text + "\n"
	txt += "[color=#8b949e]Settings: Model: %s | Base: %.0f/s | Budget: 17.5 ms[/color]\n\n" % [growth_str, GameSettings.ramp_base_spawn_rate if typeof(GameSettings) != TYPE_NIL else 300.0]
	txt += "[code]"
	txt += "Active Entities : %-8d [Live Spawn Rate: +%.0f / s]\n" % [entity_count, current_spawn_rate]
	txt += "Frame Time / FPS: %.2f ms / %d FPS\n" % [frame_ms, fps]
	txt += "Sim Logic Tick  : %.2f us (%.4f ms)\n" % [last_logic_us, last_logic_us / 1000.0]
	txt += "GPU Sync Time   : %.2f us\n" % last_sync_us
	txt += "SceneTree Nodes : %d\n" % nodes
	txt += "Static RAM      : %.1f MB\n" % ram_mb
	txt += "[/code]\n"
	txt += "[color=gray][i]Saturation triggers if Frame Time > 17.5 ms for 5.0 s. [ESC] aborts.[/i][/color]"
	hud_label.text = txt


## Advances all OOP MeshInstance3D nodes linearly and reflects off [-50, 50] arena bounds.
func _tick_oop(delta: float) -> void:
	for i in range(oop_nodes.size()):
		var node = oop_nodes[i]
		var pos = node.position
		var vel = oop_velocities[i]
		pos += vel * delta
		if pos.x < -50.0: pos.x = -50.0; vel.x = -vel.x; oop_velocities[i] = vel
		elif pos.x > 50.0: pos.x = 50.0; vel.x = -vel.x; oop_velocities[i] = vel
		if pos.z < -50.0: pos.z = -50.0; vel.z = -vel.z; oop_velocities[i] = vel
		elif pos.z > 50.0: pos.z = 50.0; vel.z = -vel.z; oop_velocities[i] = vel
		node.position = pos
