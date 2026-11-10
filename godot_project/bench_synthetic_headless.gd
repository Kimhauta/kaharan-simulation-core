extends Node3D

@onready var bridge: SimulationBridge = $SimulationBridge
@onready var mmi_primary: MultiMeshInstance3D = find_child("MultiMeshInstance3D", true, false) as MultiMeshInstance3D

enum SimVariant { DOD_SINGLE_MESH, DOD_MULTI_MESH, OOP_SINGLE_MESH, OOP_MULTI_MESH }

const START_DELAY: float = 1.0
const WARMUP_DURATION: float = 1.0

var sample_duration: float = 4.0
var current_variant: SimVariant = SimVariant.DOD_SINGLE_MESH
var entity_count: int = 1000

var oop_container: Node3D = null
var oop_nodes: Array[MeshInstance3D] = []
var oop_velocities: Array[Vector3] = []

var last_oop_tick_us: float = 0.0

enum BenchState { COUNTDOWN, WARMING_UP, SAMPLING, FINISHED }
var state: BenchState = BenchState.COUNTDOWN
var timer: float = 0.0
var step_index: int = 0

# Haetaan dynaamisesti GameSettingsiltä
var bench_configs: Array[Dictionary] = []
var current_step_samples: Array[Dictionary] = []
var summary_results: Array[Dictionary] = []

var hud_label: RichTextLabel
var progress_bar: ProgressBar

func _ready() -> void:
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.apply_settings()
		sample_duration = GameSettings.get_sample_duration()
		# Dynaamiset asetukset (is_headless = true)
		bench_configs = GameSettings.get_synthetic_configs(true)

	if mmi_primary: 
		mmi_primary.visible = false
	
	oop_container = Node3D.new()
	oop_container.name = "OOP_Headless_Container"
	oop_container.visible = false
	add_child(oop_container)
	
	_build_telemetry_hud()
	state = BenchState.COUNTDOWN
	timer = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if typeof(GameSettings) != TYPE_NIL:
				GameSettings.is_running_full_suite = false
			get_tree().change_scene_to_file("res://benchmark_hub.tscn")

func _build_telemetry_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(460, 250)
	canvas.add_child(panel)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	hud_label = RichTextLabel.new()
	hud_label.bbcode_enabled = true
	hud_label.fit_content = true
	hud_label.custom_minimum_size = Vector2(440, 190)
	vbox.add_child(hud_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(440, 20)
	vbox.add_child(progress_bar)

func _setup_simulation(count: int, variant: SimVariant) -> void:
	entity_count = count
	current_variant = variant
	
	for node in oop_nodes:
		node.free()
	oop_nodes.clear()
	oop_velocities.clear()
	
	if variant == SimVariant.DOD_SINGLE_MESH or variant == SimVariant.DOD_MULTI_MESH:
		bridge.set_process(true)
		bridge.spawn_agents(entity_count)
	else:
		bridge.set_process(false)
		var rng = RandomNumberGenerator.new()
		rng.seed = 1337
		for i in range(entity_count):
			var agent = MeshInstance3D.new()
			agent.position = Vector3(rng.randf_range(-45.0, 45.0), 0.0, rng.randf_range(-45.0, 45.0))
			var vel = Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
			oop_container.add_child(agent)
			oop_nodes.append(agent)
			oop_velocities.append(vel)

func _process(delta: float) -> void:
	# Headless: vain OOP liikuttaa solmuja skriptistä, C++ bridge hoitaa DOD:n
	if current_variant == SimVariant.OOP_SINGLE_MESH or current_variant == SimVariant.OOP_MULTI_MESH:
		var t0 = Time.get_ticks_usec()
		_tick_oop(delta)
		last_oop_tick_us = float(Time.get_ticks_usec() - t0)

	_update_state_machine(delta)
	_update_hud()

func _update_state_machine(delta: float) -> void:
	timer += delta
	match state:
		BenchState.COUNTDOWN:
			progress_bar.value = (timer / START_DELAY) * 100.0
			if timer >= START_DELAY:
				step_index = 0
				summary_results.clear()
				if bench_configs.size() > 0:
					_start_step(0)
				else:
					_finish_suite()
		BenchState.WARMING_UP:
			var total_steps = float(maxi(1, bench_configs.size()))
			progress_bar.value = ((step_index + (timer / (WARMUP_DURATION + sample_duration))) / total_steps) * 100.0
			if timer >= WARMUP_DURATION:
				timer = 0.0
				state = BenchState.SAMPLING
		BenchState.SAMPLING:
			var total_steps = float(maxi(1, bench_configs.size()))
			progress_bar.value = ((step_index + ((WARMUP_DURATION + timer) / (WARMUP_DURATION + sample_duration))) / total_steps) * 100.0
			_record_frame_sample(delta)
			if timer >= sample_duration:
				_finalize_step()
				step_index += 1
				if step_index < bench_configs.size():
					_start_step(step_index)
				else:
					_finish_suite()

func _start_step(idx: int) -> void:
	var cfg = bench_configs[idx]
	current_step_samples.clear()
	timer = 0.0
	state = BenchState.WARMING_UP
	_setup_simulation(cfg["count"], cfg["variant"])

func _record_frame_sample(delta: float) -> void:
	var is_oop = (current_variant == SimVariant.OOP_SINGLE_MESH or current_variant == SimVariant.OOP_MULTI_MESH)
	var logic_us = last_oop_tick_us if is_oop else bridge.get_last_tick_microseconds()
	var frame_ms = delta * 1000.0
	current_step_samples.append({
		"frame_ms": frame_ms,
		"fps": 1000.0 / maxf(frame_ms, 0.0001),
		"logic_us": logic_us,
		"sync_us": 0.0,
		"total_us": logic_us,
		"ram_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	})

func _finalize_step() -> void:
	var cfg = bench_configs[step_index]
	var n = current_step_samples.size()
	if n == 0:
		return

	var raw_dir: String = "res://user_files"
	if typeof(GameSettings) != TYPE_NIL:
		raw_dir = GameSettings.get_current_raw_frames_folder()
	else:
		var dir = DirAccess.open("res://")
		if not dir.dir_exists("user_files"):
			dir.make_dir("user_files")

	var raw_path = raw_dir.path_join("raw_%s.csv" % cfg["name"])
	var f_raw = FileAccess.open(raw_path, FileAccess.WRITE)
	if f_raw:
		f_raw.store_line("FrameIndex,FrameTime_ms,InstantFPS,Logic_us,Sync_us,TotalSim_us,SceneNodes,StaticRAM_MB")
		for i in range(n):
			var s = current_step_samples[i]
			f_raw.store_line("%d,%.4f,%.2f,%.2f,%.2f,%.2f,%d,%.2f" % [
				i + 1, s["frame_ms"], s["fps"], s["logic_us"], s["sync_us"], s["total_us"], s["nodes"], s["ram_mb"]
			])
		f_raw.close()

	var sum_frame = 0.0
	var sum_logic = 0.0
	var min_logic = 999999999.0
	var max_logic = 0.0
	var frame_times: Array[float] = []

	for s in current_step_samples:
		sum_frame += s["frame_ms"]
		sum_logic += s["logic_us"]
		min_logic = minf(min_logic, s["logic_us"])
		max_logic = maxf(max_logic, s["logic_us"])
		frame_times.append(s["frame_ms"])

	var avg_frame_ms = sum_frame / n
	var avg_fps = 1000.0 / maxf(avg_frame_ms, 0.0001)

	var variance = 0.0
	for ft in frame_times:
		var d = ft - avg_frame_ms
		variance += d * d
	var std_dev_ms = sqrt(variance / n)

	frame_times.sort()
	var idx_99 = clampi(int(ceil(n * 0.99)) - 1, 0, n - 1)
	var idx_999 = clampi(int(ceil(n * 0.999)) - 1, 0, n - 1)
	var fps_1_low = 1000.0 / maxf(frame_times[idx_99], 0.0001)
	var fps_01_low = 1000.0 / maxf(frame_times[idx_999], 0.0001)

	summary_results.append({
		"name": cfg["name"],
		"entities": cfg["count"],
		"frames": n,
		"avg_fps": avg_fps,
		"avg_frame_ms": avg_frame_ms,
		"std_dev_ms": std_dev_ms,
		"fps_1_low": fps_1_low,
		"fps_01_low": fps_01_low,
		"avg_logic_us": sum_logic / n,
		"min_logic_us": min_logic,
		"max_logic_us": max_logic,
		"avg_sync_us": 0.0,
		"avg_total_us": sum_logic / n,
		"nodes": current_step_samples[-1]["nodes"],
		"ram_mb": current_step_samples[-1]["ram_mb"]
	})

func _finish_suite() -> void:
	state = BenchState.FINISHED
	set_process(false)
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.append_summary_results(summary_results)
		GameSettings.finish_current_benchmark()

func _update_hud() -> void:
	if state == BenchState.FINISHED:
		return
		
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / maxf(fps, 1.0)
	var is_oop = (current_variant == SimVariant.OOP_SINGLE_MESH or current_variant == SimVariant.OOP_MULTI_MESH)
	var logic_us = last_oop_tick_us if is_oop else bridge.get_last_tick_microseconds()
	var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	var nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vsync_str = "ON" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "OFF"
	
	var status_str = ""
	if state == BenchState.COUNTDOWN:
		status_str = "[color=yellow]Starting in %.1f s...[/color]" % (START_DELAY - timer)
	elif state == BenchState.WARMING_UP:
		status_str = "[color=orange]Warming up...[/color]"
	elif state == BenchState.SAMPLING:
		status_str = "[color=green]Sampling (%.1f / %.1f s)...[/color]" % [timer, sample_duration]

	var safe_idx = clampi(step_index, 0, maxi(0, bench_configs.size() - 1))
	var cfg_name = bench_configs[safe_idx]["name"] if bench_configs.size() > 0 else "None"
	
	# Muotoillaan aktiiviset esiasetukset
	var workload_str = "Standard (1k-10k)"
	if typeof(GameSettings) != TYPE_NIL:
		match GameSettings.synthetic_workload:
			1: workload_str = "Lightweight (500-2.5k)"
			2: workload_str = "Extreme (5k-25k)"

	var txt = "[b][color=#58a6ff]SYNTHETIC BENCHMARK SUITE[/color][/b] | Step %d/%d: [color=white][b]%s[/b][/color]\n" % [safe_idx + 1, bench_configs.size(), cfg_name]
	txt += "Status: " + status_str + "\n"
	txt += "[color=#8b949e]Profile: %.1fs/step | Workload: %s | V-Sync: %s[/color]\n\n" % [sample_duration, workload_str, vsync_str]
	txt += "[code]"
	txt += "Active Entities : %d\n" % entity_count
	txt += "FPS / FrameTime : %d FPS (%.2f ms)\n" % [fps, frame_ms]
	txt += "Sim Logic Tick  : %.2f us (%.4f ms)\n" % [logic_us, logic_us / 1000.0]
	txt += "MultiMesh Sync    : 0.00 us (Disabled)\n"
	txt += "SceneTree Nodes : %d\n" % nodes
	txt += "Static RAM      : %.1f MB\n" % ram_mb
	txt += "[/code]\n"
	txt += "[color=gray][i]Press [ESC] at any time to abort.[/i][/color]"
	hud_label.text = txt

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
