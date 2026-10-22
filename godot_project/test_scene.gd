extends Node3D

@onready var bridge: SimulationBridge = $SimulationBridge
@onready var mmi_primary: MultiMeshInstance3D = $MultiMeshInstance3D

enum SimVariant { DOD_SINGLE_MESH, DOD_MULTI_MESH, OOP_SINGLE_MESH, OOP_MULTI_MESH }

const START_DELAY: float = 1.5
const WARMUP_DURATION: float = 1.5
const SAMPLE_DURATION: float = 4.0
const NUM_MESH_TYPES: int = 5

var current_variant: SimVariant = SimVariant.DOD_SINGLE_MESH
var entity_count: int = 1000

# Monityyppiset resurssit
var type_meshes: Array[Mesh] = []
var extra_mmis: Array[MultiMeshInstance3D] = []

# OOP Baseline -rakenteet
var oop_container: Node3D = null
var oop_nodes: Array[MeshInstance3D] = []
var oop_velocities: Array[Vector3] = []

# Mittausmuuttujat
var last_oop_tick_us: float = 0.0
var last_sync_us: float = 0.0

# Automaattinen 12-vaiheinen sekvensseri
enum BenchState { COUNTDOWN, WARMING_UP, SAMPLING, FINISHED }
var state: BenchState = BenchState.COUNTDOWN
var timer: float = 0.0
var step_index: int = 0

var bench_configs: Array[Dictionary] = [
	# 1. DOD Single Mesh (1 Draw Call)
	{"variant": SimVariant.DOD_SINGLE_MESH, "count": 1000,  "name": "DOD_1Mesh_1k"},
	{"variant": SimVariant.DOD_SINGLE_MESH, "count": 5000,  "name": "DOD_1Mesh_5k"},
	{"variant": SimVariant.DOD_SINGLE_MESH, "count": 10000, "name": "DOD_1Mesh_10k"},
	# 2. DOD Multi-Mesh (5 eri 3D-muotoa -> 5 Draw Callia)
	{"variant": SimVariant.DOD_MULTI_MESH,  "count": 1000,  "name": "DOD_5Mesh_1k"},
	{"variant": SimVariant.DOD_MULTI_MESH,  "count": 5000,  "name": "DOD_5Mesh_5k"},
	{"variant": SimVariant.DOD_MULTI_MESH,  "count": 10000, "name": "DOD_5Mesh_10k"},
	# 3. OOP Single Mesh (Kaikki sama kuutio -solmu)
	{"variant": SimVariant.OOP_SINGLE_MESH, "count": 1000,  "name": "OOP_1Mesh_1k"},
	{"variant": SimVariant.OOP_SINGLE_MESH, "count": 5000,  "name": "OOP_1Mesh_5k"},
	{"variant": SimVariant.OOP_SINGLE_MESH, "count": 10000, "name": "OOP_1Mesh_10k"},
	# 4. OOP Multi-Mesh (5 eri 3D-muotoa erillisinä Node3D-solmuina)
	{"variant": SimVariant.OOP_MULTI_MESH,  "count": 1000,  "name": "OOP_5Mesh_1k"},
	{"variant": SimVariant.OOP_MULTI_MESH,  "count": 5000,  "name": "OOP_5Mesh_5k"},
	{"variant": SimVariant.OOP_MULTI_MESH,  "count": 10000, "name": "OOP_5Mesh_10k"}
]

var current_step_samples: Array[Dictionary] = []
var summary_results: Array[Dictionary] = []

var hud_label: RichTextLabel
var progress_bar: ProgressBar

func _ready() -> void:
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.apply_settings()
		
	_init_multi_type_resources()
	_build_telemetry_hud()
	
	oop_container = Node3D.new()
	oop_container.name = "OOP_Agents_Container"
	add_child(oop_container)
	
	_setup_simulation(1000, SimVariant.DOD_SINGLE_MESH)
	state = BenchState.COUNTDOWN
	timer = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			print("[Benchmark] Cancelled by user (ESC). Returning to Main Menu...")
			get_tree().change_scene_to_file("res://main_menu.tscn")

func _init_multi_type_resources() -> void:
	var colors = [
		Color(0.2, 0.85, 0.4), # Vihreä
		Color(0.2, 0.6, 1.0),  # Sininen
		Color(0.95, 0.6, 0.1), # Oranssi
		Color(0.9, 0.25, 0.3), # Punainen
		Color(0.7, 0.3, 0.95)  # Violetti
	]
	
	var m0 = BoxMesh.new(); m0.size = Vector3(0.6, 0.6, 0.6)
	var m1 = SphereMesh.new(); m1.radius = 0.35; m1.height = 0.7
	var m2 = CapsuleMesh.new(); m2.radius = 0.25; m2.height = 0.8
	var m3 = CylinderMesh.new(); m3.top_radius = 0.3; m3.bottom_radius = 0.3; m3.height = 0.7
	var m4 = PrismMesh.new(); m4.size = Vector3(0.6, 0.6, 0.6)
	type_meshes = [m0, m1, m2, m3, m4]
	
	for i in range(NUM_MESH_TYPES):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.roughness = 0.4
		type_meshes[i].surface_set_material(0, mat)
		
		var mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = type_meshes[i]
		mmi.multimesh = mm
		mmi.visible = false
		add_child(mmi)
		extra_mmis.append(mmi)

func _build_telemetry_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(460, 260)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	style.border_color = Color(0.25, 0.55, 0.95, 0.8)
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
	hud_label.custom_minimum_size = Vector2(430, 200)
	vbox.add_child(hud_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.custom_minimum_size = Vector2(430, 22)
	vbox.add_child(progress_bar)

func _setup_simulation(count: int, variant: SimVariant) -> void:
	entity_count = count
	current_variant = variant
	
	for node in oop_nodes:
		node.free()
	oop_nodes.clear()
	oop_velocities.clear()
	
	mmi_primary.visible = false
	for mmi in extra_mmis:
		mmi.visible = false
		
	if variant == SimVariant.DOD_SINGLE_MESH:
		mmi_primary.visible = true
		bridge.set_process(true)
		bridge.spawn_agents(entity_count)
	elif variant == SimVariant.DOD_MULTI_MESH:
		for mmi in extra_mmis:
			mmi.visible = true
		bridge.set_process(true)
		bridge.spawn_agents(entity_count)
	else: # OOP_SINGLE_MESH tai OOP_MULTI_MESH
		bridge.set_process(false)
		var rng = RandomNumberGenerator.new()
		rng.seed = 1337
		
		for i in range(entity_count):
			var agent = MeshInstance3D.new()
			if variant == SimVariant.OOP_SINGLE_MESH:
				agent.mesh = type_meshes[0] # Vain yksi mesh kaikille
			else:
				agent.mesh = type_meshes[i % NUM_MESH_TYPES] # 5 eri meshiä
				
			agent.position = Vector3(
				rng.randf_range(-45.0, 45.0),
				0.0,
				rng.randf_range(-45.0, 45.0)
			)
			var vel = Vector3(
				rng.randf_range(-8.0, 8.0),
				0.0,
				rng.randf_range(-8.0, 8.0)
			)
			oop_container.add_child(agent)
			oop_nodes.append(agent)
			oop_velocities.append(vel)

func _process(delta: float) -> void:
	if current_variant == SimVariant.DOD_SINGLE_MESH:
		var t0 = Time.get_ticks_usec()
		bridge.sync_to_multimesh(mmi_primary.multimesh)
		last_sync_us = float(Time.get_ticks_usec() - t0)
	elif current_variant == SimVariant.DOD_MULTI_MESH:
		var t0 = Time.get_ticks_usec()
		var chunk = entity_count / NUM_MESH_TYPES
		if bridge.has_method("sync_to_multimesh_range"):
			for t in range(NUM_MESH_TYPES):
				bridge.sync_to_multimesh_range(extra_mmis[t].multimesh, t * chunk, chunk)
		else:
			bridge.sync_to_multimesh(extra_mmis[0].multimesh)
		last_sync_us = float(Time.get_ticks_usec() - t0)
	else:
		var t0 = Time.get_ticks_usec()
		_tick_oop(delta)
		last_oop_tick_us = float(Time.get_ticks_usec() - t0)
		last_sync_us = 0.0

	_update_benchmark_state_machine(delta)
	_update_hud()

func _update_benchmark_state_machine(delta: float) -> void:
	timer += delta
	
	match state:
		BenchState.COUNTDOWN:
			progress_bar.value = (timer / START_DELAY) * 100.0
			if timer >= START_DELAY:
				step_index = 0
				summary_results.clear()
				_start_step(0)
				
		BenchState.WARMING_UP:
			var total_steps = float(bench_configs.size())
			var step_progress = (timer / (WARMUP_DURATION + SAMPLE_DURATION))
			progress_bar.value = ((step_index + step_progress) / total_steps) * 100.0
			
			if timer >= WARMUP_DURATION:
				timer = 0.0
				state = BenchState.SAMPLING
				
		BenchState.SAMPLING:
			var total_steps = float(bench_configs.size())
			var step_progress = ((WARMUP_DURATION + timer) / (WARMUP_DURATION + SAMPLE_DURATION))
			progress_bar.value = ((step_index + step_progress) / total_steps) * 100.0
			
			_record_frame_sample(delta)
			
			if timer >= SAMPLE_DURATION:
				_finalize_step()
				step_index += 1
				if step_index < bench_configs.size():
					_start_step(step_index)
				else:
					_finish_benchmark_and_return()

func _start_step(idx: int) -> void:
	var cfg = bench_configs[idx]
	current_step_samples.clear()
	timer = 0.0
	state = BenchState.WARMING_UP
	_setup_simulation(cfg["count"], cfg["variant"])

func _record_frame_sample(delta: float) -> void:
	var is_oop = (current_variant == SimVariant.OOP_SINGLE_MESH or current_variant == SimVariant.OOP_MULTI_MESH)
	var logic_us = last_oop_tick_us if is_oop else bridge.get_last_tick_microseconds()
	current_step_samples.append({
		"frame_ms": delta * 1000.0,
		"logic_us": logic_us,
		"sync_us": last_sync_us,
		"total_us": logic_us + last_sync_us,
		"ram_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	})

func _finalize_step() -> void:
	var cfg = bench_configs[step_index]
	var n = current_step_samples.size()
	if n == 0:
		return
		
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("user_files"):
		dir.make_dir("user_files")
		
	var raw_path = "res://user_files/raw_%s.dat" % cfg["name"]
	var f_raw = FileAccess.open(raw_path, FileAccess.WRITE)
	if f_raw:
		f_raw.store_line("Config,Entities,FrameTime_ms,Logic_us,Sync_us,TotalSim_us,SceneNodes,StaticRAM_MB")
		for s in current_step_samples:
			f_raw.store_line("%s,%d,%.4f,%.2f,%.2f,%.2f,%d,%.2f" % [
				cfg["name"], entity_count, s["frame_ms"],
				s["logic_us"], s["sync_us"], s["total_us"], s["nodes"], s["ram_mb"]
			])
		f_raw.close()

	var sum_frame: float = 0.0
	var sum_logic: float = 0.0
	var sum_sync: float = 0.0
	var min_logic: float = 999999999.0
	var max_logic: float = 0.0
	
	for s in current_step_samples:
		sum_frame += s["frame_ms"]
		sum_logic += s["logic_us"]
		sum_sync += s["sync_us"]
		min_logic = minf(min_logic, s["logic_us"])
		max_logic = maxf(max_logic, s["logic_us"])
		
	var avg_frame_ms = sum_frame / n
	var avg_fps = 1000.0 / maxf(avg_frame_ms, 0.0001)
	var avg_logic = sum_logic / n
	var avg_sync = sum_sync / n
	
	summary_results.append({
		"name": cfg["name"],
		"entities": cfg["count"],
		"frames": n,
		"avg_fps": avg_fps,
		"avg_frame_ms": avg_frame_ms,
		"avg_logic_us": avg_logic,
		"min_logic_us": min_logic,
		"max_logic_us": max_logic,
		"avg_sync_us": avg_sync,
		"avg_total_us": avg_logic + avg_sync,
		"nodes": current_step_samples[-1]["nodes"],
		"ram_mb": current_step_samples[-1]["ram_mb"]
	})

func _finish_benchmark_and_return() -> void:
	state = BenchState.FINISHED
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("user_files"):
		dir.make_dir("user_files")
		
	var path = "res://user_files/benchmark_summary.dat"
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line("Config,Entities,FramesSampled,AvgFPS,AvgFrameTime_ms,AvgLogic_us,MinLogic_us,MaxLogic_us,AvgSync_us,AvgTotalSim_us,SceneNodes,StaticRAM_MB")
		for r in summary_results:
			f.store_line("%s,%d,%d,%.2f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f" % [
				r["name"], r["entities"], r["frames"], r["avg_fps"], r["avg_frame_ms"],
				r["avg_logic_us"], r["min_logic_us"], r["max_logic_us"],
				r["avg_sync_us"], r["avg_total_us"], r["nodes"], r["ram_mb"]
			])
		f.close()
		
	print("[Benchmark] 12-step suite completed! Returning to Main Menu...")
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _update_hud() -> void:
	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / maxf(fps, 1.0)
	var is_oop = (current_variant == SimVariant.OOP_SINGLE_MESH or current_variant == SimVariant.OOP_MULTI_MESH)
	var logic_us = last_oop_tick_us if is_oop else bridge.get_last_tick_microseconds()
	var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	var nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vsync_str = "ON (60 Hz Cap)" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "OFF (Uncapped)"
	
	var status_str = ""
	if state == BenchState.COUNTDOWN:
		status_str = "[color=yellow]Starting 12-step suite in %.1f s...[/color]" % (START_DELAY - timer)
	elif state == BenchState.WARMING_UP:
		status_str = "[color=orange]Step %d/%d: %s (Warming up...)[/color]" % [step_index + 1, bench_configs.size(), bench_configs[step_index]["name"]]
	elif state == BenchState.SAMPLING:
		status_str = "[color=green]Step %d/%d: %s (Sampling data...)[/color]" % [step_index + 1, bench_configs.size(), bench_configs[step_index]["name"]]
		
	var txt = "[b][color=#58a6ff]KAHARAN 12-STEP BENCHMARK HUD[/color][/b]\n"
	txt += status_str + "\n\n"
	txt += "[code]"
	txt += "Active Entities : %d\n" % entity_count
	txt += "V-Sync Mode     : %s\n" % vsync_str
	txt += "FPS / FrameTime : %d FPS (%.2f ms)\n" % [fps, frame_ms]
	txt += "Sim Logic Tick  : %.2f us (%.4f ms)\n" % [logic_us, logic_us / 1000.0]
	txt += "MultiMesh Sync  : %.2f us\n" % last_sync_us
	txt += "SceneTree Nodes : %d\n" % nodes
	txt += "Static RAM      : %.1f MB\n" % ram_mb
	txt += "[/code]\n"
	txt += "[color=gray][i]Press [ESC] at any time to abort.[/i][/color]"
	hud_label.text = txt

func _tick_oop(delta: float) -> void:
	var total = oop_nodes.size()
	for i in range(total):
		var node: MeshInstance3D = oop_nodes[i]
		var pos: Vector3 = node.position
		var vel: Vector3 = oop_velocities[i]
		
		pos.x += vel.x * delta
		pos.y += vel.y * delta
		pos.z += vel.z * delta
		
		if pos.x < -50.0:
			pos.x = -50.0; vel.x = -vel.x; oop_velocities[i] = vel
		elif pos.x > 50.0:
			pos.x = 50.0; vel.x = -vel.x; oop_velocities[i] = vel
			
		if pos.z < -50.0:
			pos.z = -50.0; vel.z = -vel.z; oop_velocities[i] = vel
		elif pos.z > 50.0:
			pos.z = 50.0; vel.z = -vel.z; oop_velocities[i] = vel
			
		node.position = pos
