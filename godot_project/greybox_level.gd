extends Node3D

const START_DELAY: float = 2.0
const WARMUP_DURATION: float = 2.0
const NUM_MESH_TYPES: int = 5

const LOD1_RADIUS: float = 25.0
const LOD2_RADIUS: float = 55.0

const POPULATION_TIERS: Array[int] = [5000, 10000, 15000, 25000, 50000, 100000]
const MAX_SAFE_OOP_ENTITIES: int = 15000

var bridge: SimulationBridge = null
var pass_duration: float = 45.0
var pop_tier_index: int = 1 # Oletus: 10 000 entiteettiä (turvallinen OOP + DOD 4-vaiheajoon)
var entity_count: int = 10000

# Tila: Pelattava vapaa kamera vs. 4-vaiheinen 3DMark Fly-Through
var is_benchmark_mode: bool = false
var interactive_use_dod: bool = true
var interactive_lod_enabled: bool = true
var show_lod_rings: bool = true
var mouse_captured: bool = false
var cam_yaw: float = 0.0
var cam_pitch: float = -12.0

# Monityyppiset MultiMesh-resurssit (DOD)
var type_meshes: Array[Mesh] = []
var extra_mmis: Array[MultiMeshInstance3D] = []

# OOP Baseline -rakenteet
var oop_container: Node3D = null
var oop_nodes: Array[MeshInstance3D] = []
var oop_velocities: Array[Vector3] = []
var oop_sim_time: float = 0.0
var oop_tick_counter: int = 0
var oop_lod0_count: int = 0
var oop_lod1_count: int = 0
var oop_lod2_count: int = 0

# Kamerat ja rata
var path_3d: Path3D
var path_follow: PathFollow3D
var bench_camera: Camera3D
var player_camera: Camera3D
var lod_ring_0: MeshInstance3D
var lod_ring_1: MeshInstance3D

# Benchmark-tilakone (4 kierrosta: OOP Base, OOP LOD, DOD Base, DOD LOD)
enum BenchState { COUNTDOWN, WARMING_UP, SAMPLING, FINISHED }
var state: BenchState = BenchState.COUNTDOWN
var timer: float = 0.0
var step_index: int = 0

var bench_configs: Array[Dictionary] = []
var current_step_samples: Array[Dictionary] = []
var summary_results: Array[Dictionary] = []
var last_logic_us: float = 0.0
var last_sync_us: float = 0.0

# HUD
var hud_label: RichTextLabel
var progress_bar: ProgressBar

func _ready() -> void:
	# Päivitetään kameran ja tarkkailijan sijainti ENNEN SimulationBridge._process()-kutsua
	process_priority = -10

	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.apply_settings()
		is_benchmark_mode = GameSettings.is_running_full_suite or GameSettings.force_greybox_benchmark
		GameSettings.force_greybox_benchmark = false

		# 3DMark-tyylinen rauhallinen kameran läpilentoaika profiilin mukaan
		match GameSettings.benchmark_profile:
			0: pass_duration = 25.0 # Quick: ~1 min 40 s (4 kierrosta)
			1: pass_duration = 45.0 # Standard: 3 min 00 s (4 kierrosta, ~4.5 m/s)
			2: pass_duration = 75.0 # Soak: 5 min 00 s (4 kierrosta)
			_: pass_duration = 45.0

		match GameSettings.synthetic_workload:
			1: pop_tier_index = 0 # Lightweight: 5 000
			2: pop_tier_index = 2 # Extreme: 15 000
			_: pop_tier_index = 1 # Standard: 10 000
		entity_count = POPULATION_TIERS[pop_tier_index]

	_ensure_bridge()
	_build_three_room_greybox_level()
	_build_cameras_and_flight_path()
	_init_multi_type_resources()
	_build_telemetry_hud()

	if is_benchmark_mode:
		_enter_benchmark_mode()
	else:
		_enter_interactive_mode()

func _input(event: InputEvent) -> void:
	if is_benchmark_mode:
		return

	# Hiirellä katsominen suoraan aina kun hiiri on kaapattuna
	if event is InputEventMouseMotion and mouse_captured:
		cam_yaw -= event.relative.x * 0.18
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.18, -85.0, 85.0)
		if player_camera:
			player_camera.rotation_degrees = Vector3(cam_pitch, cam_yaw, 0.0)
	# Vasen klikkaus lukitsee hiiren takaisin, jos se oli vapautettu M-näppäimellä
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not mouse_captured:
			_set_mouse_capture(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_exit_to_menu()
			KEY_TAB:
				if is_benchmark_mode:
					_enter_interactive_mode()
				else:
					_enter_benchmark_mode()
			KEY_O:
				if not is_benchmark_mode:
					if not interactive_use_dod or entity_count <= MAX_SAFE_OOP_ENTITIES:
						interactive_use_dod = not interactive_use_dod
						_respawn_active_mode(entity_count, interactive_use_dod, interactive_lod_enabled)
			KEY_L:
				if not is_benchmark_mode:
					interactive_lod_enabled = not interactive_lod_enabled
					bridge.set_lod_enabled(interactive_lod_enabled)
					_update_ring_visibility()
			KEY_V:
				if not is_benchmark_mode:
					show_lod_rings = not show_lod_rings
					_update_ring_visibility()
			KEY_M, KEY_ALT:
				if not is_benchmark_mode:
					_set_mouse_capture(not mouse_captured)
			KEY_1:
				if not is_benchmark_mode:
					_teleport_player_to_room(1)
			KEY_2:
				if not is_benchmark_mode:
					_teleport_player_to_room(2)
			KEY_3:
				if not is_benchmark_mode:
					_teleport_player_to_room(3)
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				if not is_benchmark_mode:
					_change_population_tier(1)
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				if not is_benchmark_mode:
					_change_population_tier(-1)

func _set_mouse_capture(capture: bool) -> void:
	mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

func _exit_to_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if typeof(GameSettings) != TYPE_NIL:
		var was_suite = GameSettings.is_running_full_suite
		GameSettings.is_running_full_suite = false
		if was_suite:
			get_tree().change_scene_to_file("res://benchmark_hub.tscn")
			return
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _ensure_bridge() -> void:
	bridge = get_node_or_null("SimulationBridge") as SimulationBridge
	if bridge == null:
		bridge = SimulationBridge.new()
		bridge.name = "SimulationBridge"
		add_child(bridge)
	bridge.set_process(true)

# ==============================================================================
# KOLMEN HUONEEN + KAHDEN KÄYTÄVÄN GREYBOX-ARKKITEHTUURI (100 x 100 m)
# ==============================================================================

func _build_three_room_greybox_level() -> void:
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.11, 0.17, 0.28)
	sky_mat.sky_horizon_color = Color(0.28, 0.34, 0.42)
	sky_mat.ground_bottom_color = Color(0.06, 0.07, 0.09)
	sky_mat.ground_horizon_color = Color(0.18, 0.21, 0.26)
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.70
	world_env.environment = env
	add_child(world_env)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170.0
	add_child(sun)

	var mat_floor = _make_std_mat(Color(0.15, 0.17, 0.20), 0.85)
	var mat_wall = _make_std_mat(Color(0.28, 0.32, 0.38), 0.75)
	var mat_corridor = _make_std_mat(Color(0.22, 0.25, 0.30), 0.65)
	var mat_room1 = _make_std_mat(Color(0.22, 0.52, 0.88), 0.45) # Huone 1: Sininen
	var mat_room2 = _make_std_mat(Color(0.88, 0.48, 0.18), 0.45) # Huone 2: Oranssi
	var mat_room3 = _make_std_mat(Color(0.20, 0.76, 0.52), 0.45) # Huone 3: Smaragdi

	# Lattia (104 x 104 m)
	_spawn_box(Vector3(0.0, -0.85, 0.0), Vector3(104.0, 1.0, 104.0), mat_floor)

	# Ulkoseinät (+/- 50.6 m)
	_spawn_box(Vector3(0.0, 3.5, -50.6), Vector3(102.0, 8.0, 1.2), mat_wall)
	_spawn_box(Vector3(0.0, 3.5,  50.6), Vector3(102.0, 8.0, 1.2), mat_wall)
	_spawn_box(Vector3(-50.6, 3.5, 0.0), Vector3(1.2, 8.0, 102.0), mat_wall)
	_spawn_box(Vector3( 50.6, 3.5, 0.0), Vector3(1.2, 8.0, 102.0), mat_wall)

	# --- VÄLISEINÄT JA KÄYTÄVÄ 1 (X: -16..16, Z: -36..-20) ---
	_spawn_box(Vector3(-16.0, 3.5, -43.0), Vector3(1.4, 8.0, 14.0), mat_wall)
	_spawn_box(Vector3(-16.0, 3.5,  -7.0), Vector3(1.4, 8.0, 26.0), mat_wall)
	_spawn_box(Vector3( 16.0, 3.5, -43.0), Vector3(1.4, 8.0, 14.0), mat_wall)
	_spawn_box(Vector3( 16.0, 3.5,  -7.0), Vector3(1.4, 8.0, 26.0), mat_wall)
	_spawn_box(Vector3(0.0, 3.5, -36.0), Vector3(33.4, 8.0, 1.2), mat_corridor)
	_spawn_box(Vector3(0.0, 3.5, -20.0), Vector3(33.4, 8.0, 1.2), mat_corridor)
	for bx in [-12.0, -4.0, 4.0, 12.0]:
		_spawn_box(Vector3(bx, 7.2, -28.0), Vector3(1.6, 0.8, 17.2), mat_room1)

	# --- VÄLISEINÄT JA KÄYTÄVÄ 2 (X: 24..42, Z: 6..20) ---
	_spawn_box(Vector3(-13.0, 3.5, 6.0), Vector3(74.0, 8.0, 1.4), mat_wall)
	_spawn_box(Vector3( 46.0, 3.5, 6.0), Vector3( 8.0, 8.0, 1.4), mat_wall)
	_spawn_box(Vector3(-13.0, 3.5, 20.0), Vector3(74.0, 8.0, 1.4), mat_wall)
	_spawn_box(Vector3( 46.0, 3.5, 20.0), Vector3( 8.0, 8.0, 1.4), mat_wall)
	_spawn_box(Vector3(24.0, 3.5, 13.0), Vector3(1.2, 8.0, 15.4), mat_corridor)
	_spawn_box(Vector3(42.0, 3.5, 13.0), Vector3(1.2, 8.0, 15.4), mat_corridor)
	for bz in [9.0, 13.0, 17.0]:
		_spawn_box(Vector3(33.0, 7.2, bz), Vector3(19.2, 0.8, 1.6), mat_room2)

	# --- HUONEKOHTAISET MAAMERKIT ---
	_spawn_box(Vector3(-34.0, 5.5, -18.0), Vector3(4.5, 12.0, 4.5), mat_room1)
	_spawn_box(Vector3(-34.0, 5.5, -38.0), Vector3(4.5, 12.0, 4.5), mat_room1)

	_spawn_box(Vector3(33.0, 7.5, -28.0), Vector3(6.5, 16.0, 6.5), mat_room2)
	_spawn_box(Vector3(24.0, 4.0,  -8.0), Vector3(4.0,  9.0, 4.0), mat_room2)

	_spawn_box(Vector3(  0.0, 8.5, 35.0), Vector3(7.0, 18.0, 7.0), mat_room3)
	_spawn_box(Vector3(-28.0, 5.0, 35.0), Vector3(4.5, 11.0, 4.5), mat_room3)
	_spawn_box(Vector3( 28.0, 5.0, 35.0), Vector3(4.5, 11.0, 4.5), mat_room3)

	# Visuaaliset LOD-vyöhykekehät maanpinnassa
	lod_ring_0 = _create_lod_ring(LOD1_RADIUS, Color(0.2, 0.95, 0.45, 0.75))
	lod_ring_1 = _create_lod_ring(LOD2_RADIUS, Color(0.95, 0.60, 0.15, 0.65))
	add_child(lod_ring_0)
	add_child(lod_ring_1)

func _make_std_mat(col: Color, rough: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	return mat

func _spawn_box(pos: Vector3, sz: Vector3, mat: Material) -> void:
	var bm = BoxMesh.new()
	bm.size = sz
	var mi = MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _create_lod_ring(radius: float, col: Color) -> MeshInstance3D:
	var torus = TorusMesh.new()
	torus.inner_radius = radius - 0.18
	torus.outer_radius = radius + 0.18
	torus.rings = 64
	torus.ring_segments = 8

	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mi = MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, -0.25, 0.0)
	return mi

# ==============================================================================
# KAMERAT: 12-PISTEEN FLY-THROUGH-RATA & PELATTAVA KAMERA
# ==============================================================================

func _build_cameras_and_flight_path() -> void:
	path_3d = Path3D.new()
	var curve = Curve3D.new()

	# 12 ohjauspistettä (~204 m reitti), joissa tunnelien sisään- ja ulosmenot on linjattu keskelle käytävää
	var waypoints: Array[Vector3] = [
		Vector3(-36.0, 4.8, -40.0), # 1. Huone 1: Sisääntulo
		Vector3(-26.0, 4.2, -28.0), # 2. Huone 1: Käännös kohti Käytävä 1:tä
		Vector3(-12.0, 3.6, -28.0), # 3. Käytävä 1: Länsisuun sisäänmeno
		Vector3( 12.0, 3.6, -28.0), # 4. Käytävä 1: Itäsuun ulostulo
		Vector3( 26.0, 4.2, -28.0), # 5. Huone 2: Saapuminen reaktoripihalle
		Vector3( 38.0, 5.0, -16.0), # 6. Huone 2: Kierto reaktorin itäpuolelta
		Vector3( 33.0, 4.2,  -2.0), # 7. Huone 2: Linjaus Käytävä 2:n suulle
		Vector3( 33.0, 3.6,   7.0), # 8. Käytävä 2: Pohjoispään sisäänmeno
		Vector3( 33.0, 3.6,  19.0), # 9. Käytävä 2: Eteläpään ulostulo
		Vector3( 33.0, 4.8,  32.0), # 10. Huone 3: Eteläisen hangaarin itäsiipi
		Vector3(  0.0, 5.8,  40.0), # 11. Huone 3: Panoraama keskustornin ohi
		Vector3(-36.0, 5.0,  34.0)  # 12. Huone 3: Länsisiiven näköalapaikka
	]

	for i in range(waypoints.size()):
		var prev = waypoints[maxi(0, i - 1)]
		var curr = waypoints[i]
		var next = waypoints[mini(waypoints.size() - 1, i + 1)]
		var tangent = (next - prev).normalized() * 5.5
		curve.add_point(curr, -tangent, tangent)

	path_3d.curve = curve
	add_child(path_3d)

	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE
	path_3d.add_child(path_follow)

	bench_camera = Camera3D.new()
	bench_camera.fov = 68.0
	bench_camera.far = 250.0
	path_follow.add_child(bench_camera)

	player_camera = Camera3D.new()
	player_camera.fov = 70.0
	player_camera.far = 250.0
	add_child(player_camera)
	_teleport_player_to_room(1)

func _teleport_player_to_room(room_num: int) -> void:
	if not player_camera: return
	match room_num:
		1:
			player_camera.position = Vector3(-36.0, 4.5, -36.0)
			cam_yaw = -135.0
			cam_pitch = -10.0
		2:
			player_camera.position = Vector3(33.0, 5.0, -40.0)
			cam_yaw = 180.0
			cam_pitch = -12.0
		3:
			player_camera.position = Vector3(0.0, 6.0, 44.0)
			cam_yaw = 0.0
			cam_pitch = -12.0
	player_camera.rotation_degrees = Vector3(cam_pitch, cam_yaw, 0.0)

func _get_current_zone_name(pos: Vector3) -> String:
	if pos.z > 20.0:
		return "Room 3/3: South Grand Hangar"
	elif pos.z >= 6.0:
		return "Corridor 2: South-East Airlock Gate"
	elif pos.x < -16.0:
		return "Room 1/3: West Atrium Hall"
	elif pos.x <= 16.0:
		return "Corridor 1: North Overpass Tunnel"
	else:
		return "Room 2/3: East Reactor Courtyard"

func _init_multi_type_resources() -> void:
	var colors = [
		Color(0.2, 0.85, 0.4), # Arkkityyppi 0: Vihreä kuutio
		Color(0.2, 0.6, 1.0),  # Arkkityyppi 1: Sininen kuutio
		Color(0.95, 0.6, 0.1), # Arkkityyppi 2: Oranssi kuutio
		Color(0.9, 0.25, 0.3), # Arkkityyppi 3: Punainen kuutio
		Color(0.7, 0.3, 0.95)  # Arkkityyppi 4: Violetti kuutio
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
	oop_container.name = "OOP_Greybox_Container"
	oop_container.visible = false
	add_child(oop_container)

# ==============================================================================
# ENTITEETTIEN ALUSTUS (DOD C++ VS. OOP SCENE TREE)
# ==============================================================================

func _respawn_active_mode(count: int, use_dod: bool, lod_on: bool) -> void:
	# Siivotaan vanhat OOP-solmut
	for node in oop_nodes:
		node.free()
	oop_nodes.clear()
	oop_velocities.clear()
	oop_tick_counter = 0

	if use_dod:
		oop_container.visible = false
		var chunk = int(float(count) / float(NUM_MESH_TYPES))
		for mmi in extra_mmis:
			mmi.visible = true
			mmi.multimesh.instance_count = chunk
		bridge.set_process(true)
		bridge.set_steering_enabled(true)
		bridge.set_lod_enabled(lod_on)
		bridge.set_lod_thresholds(LOD1_RADIUS, LOD2_RADIUS)
		bridge.spawn_agents(count)
	else:
		for mmi in extra_mmis:
			mmi.visible = false
		bridge.set_process(false)
		oop_container.visible = true

		var rng = RandomNumberGenerator.new()
		rng.seed = 1337
		for i in range(count):
			var agent = MeshInstance3D.new()
			agent.mesh = type_meshes[i % NUM_MESH_TYPES]
			agent.position = Vector3(rng.randf_range(-45.0, 45.0), 0.0, rng.randf_range(-45.0, 45.0))
			var vel = Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
			agent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			oop_container.add_child(agent)
			oop_nodes.append(agent)
			oop_velocities.append(vel)

		oop_lod0_count = count
		oop_lod1_count = 0
		oop_lod2_count = 0
		oop_sim_time = 0.0

# ==============================================================================
# TILOJEN VAIHTO (INTERACTIVE DEMO VS. 4-PASS 3DMARK BENCHMARK)
# ==============================================================================

func _enter_interactive_mode() -> void:
	is_benchmark_mode = false
	_set_mouse_capture(true)
	set_process(true)
	player_camera.make_current()
	progress_bar.visible = false

	_respawn_active_mode(entity_count, interactive_use_dod, interactive_lod_enabled)
	_update_ring_visibility()

func _enter_benchmark_mode() -> void:
	is_benchmark_mode = true
	_set_mouse_capture(false)
	set_process(true)
	bench_camera.make_current()
	progress_bar.visible = true

	# Varmistetaan ettei OOP-kierros ylitä 15k rajaa, vaikka interaktiivisessa tilassa olisi ollut 50k
	var bench_count = mini(entity_count, MAX_SAFE_OOP_ENTITIES)
	entity_count = bench_count
	var count_label = "%dk" % int(bench_count / 1000.0)

	bench_configs = [
		{ "name": "FlyThrough_3Room_OOP_Base_%s" % count_label, "use_dod": false, "lod_enabled": false, "count": bench_count },
		{ "name": "FlyThrough_3Room_OOP_LOD_%s"  % count_label, "use_dod": false, "lod_enabled": true,  "count": bench_count },
		{ "name": "FlyThrough_3Room_DOD_Base_%s" % count_label, "use_dod": true,  "lod_enabled": false, "count": bench_count },
		{ "name": "FlyThrough_3Room_DOD_LOD_%s"  % count_label, "use_dod": true,  "lod_enabled": true,  "count": bench_count }
	]

	step_index = 0
	summary_results.clear()
	state = BenchState.COUNTDOWN
	timer = 0.0
	_update_camera_flight(0.0)

func _change_population_tier(delta_idx: int) -> void:
	pop_tier_index = clampi(pop_tier_index + delta_idx, 0, POPULATION_TIERS.size() - 1)
	entity_count = POPULATION_TIERS[pop_tier_index]
	if entity_count > MAX_SAFE_OOP_ENTITIES and not interactive_use_dod:
		interactive_use_dod = true
	_respawn_active_mode(entity_count, interactive_use_dod, interactive_lod_enabled)

func _update_ring_visibility() -> void:
	var vis = interactive_lod_enabled and show_lod_rings
	if lod_ring_0: lod_ring_0.visible = vis
	if lod_ring_1: lod_ring_1.visible = vis

# ==============================================================================
# PÄÄSILMUKKA JA MITTAUSLOGIIKKA
# ==============================================================================

func _process(delta: float) -> void:
	if is_benchmark_mode and state == BenchState.FINISHED:
		return

	var observer_pos = Vector3.ZERO
	if not is_benchmark_mode:
		_process_player_movement(delta)
		observer_pos = player_camera.global_position
	else:
		observer_pos = bench_camera.global_position

	var active_dod = bench_configs[clampi(step_index, 0, bench_configs.size() - 1)]["use_dod"] if is_benchmark_mode else interactive_use_dod
	var active_lod = bench_configs[clampi(step_index, 0, bench_configs.size() - 1)]["lod_enabled"] if is_benchmark_mode else interactive_lod_enabled

	if active_dod:
		last_logic_us = bridge.get_last_tick_microseconds()
		if bridge.get_agent_count() > 0:
			var t0 = Time.get_ticks_usec()
			var chunk = int(float(entity_count) / float(NUM_MESH_TYPES))
			for t in range(NUM_MESH_TYPES):
				bridge.sync_to_multimesh_range(extra_mmis[t].multimesh, t * chunk, chunk)
			last_sync_us = float(Time.get_ticks_usec() - t0)
	else:
		var t0 = Time.get_ticks_usec()
		_tick_oop(delta, observer_pos, active_lod)
		last_logic_us = float(Time.get_ticks_usec() - t0)
		last_sync_us = 0.0

	if is_benchmark_mode:
		_update_benchmark_state_machine(delta)

	_update_hud()

func _process_player_movement(delta: float) -> void:
	if not player_camera: return

	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir -= player_camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): input_dir += player_camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): input_dir -= player_camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): input_dir += player_camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q): input_dir.y -= 1.0

	var speed = 28.0 if Input.is_key_pressed(KEY_SHIFT) else 14.0
	if input_dir.length_squared() > 0.001:
		player_camera.position += input_dir.normalized() * speed * delta
		player_camera.position.x = clampf(player_camera.position.x, -48.5, 48.5)
		player_camera.position.y = clampf(player_camera.position.y, 1.2, 22.0)
		player_camera.position.z = clampf(player_camera.position.z, -48.5, 48.5)

	var cam_pos = player_camera.global_position
	if bridge:
		bridge.set_observer_position(cam_pos)
	if lod_ring_0 and lod_ring_0.visible:
		lod_ring_0.position = Vector3(cam_pos.x, -0.25, cam_pos.z)
	if lod_ring_1 and lod_ring_1.visible:
		lod_ring_1.position = Vector3(cam_pos.x, -0.25, cam_pos.z)

func _update_camera_flight(ratio: float) -> void:
	if not path_follow or not path_3d or not path_3d.curve: return

	path_follow.progress_ratio = clampf(ratio, 0.0, 0.999)
	var curve_len = path_3d.curve.get_baked_length()
	var look_dist = minf(path_follow.progress + 10.0, curve_len)
	var look_target = path_3d.curve.sample_baked(look_dist)
	look_target.y = 1.6

	if bench_camera.global_position.distance_squared_to(look_target) > 0.01:
		bench_camera.look_at(look_target, Vector3.UP)

	var cam_pos = bench_camera.global_position
	if bridge:
		bridge.set_observer_position(cam_pos)
	if lod_ring_0 and lod_ring_0.visible:
		lod_ring_0.position = Vector3(cam_pos.x, -0.25, cam_pos.z)
	if lod_ring_1 and lod_ring_1.visible:
		lod_ring_1.position = Vector3(cam_pos.x, -0.25, cam_pos.z)

func _start_benchmark_step(idx: int) -> void:
	var cfg = bench_configs[idx]
	current_step_samples.clear()
	timer = 0.0
	state = BenchState.WARMING_UP

	var use_dod: bool = cfg["use_dod"]
	var lod_on: bool = cfg["lod_enabled"]
	_respawn_active_mode(entity_count, use_dod, lod_on)

	if lod_ring_0: lod_ring_0.visible = lod_on
	if lod_ring_1: lod_ring_1.visible = lod_on
	_update_camera_flight(0.0)

func _update_benchmark_state_machine(delta: float) -> void:
	timer += delta

	match state:
		BenchState.COUNTDOWN:
			progress_bar.value = (timer / START_DELAY) * 100.0
			if timer >= START_DELAY:
				_start_benchmark_step(0)

		BenchState.WARMING_UP:
			_update_camera_flight(0.0)
			var step_prog = timer / float(WARMUP_DURATION + pass_duration)
			progress_bar.value = ((float(step_index) + step_prog) / float(bench_configs.size())) * 100.0
			if timer >= WARMUP_DURATION:
				timer = 0.0
				state = BenchState.SAMPLING

		BenchState.SAMPLING:
			var flight_ratio = clampf(timer / pass_duration, 0.0, 1.0)
			_update_camera_flight(flight_ratio)

			var step_prog = (WARMUP_DURATION + timer) / float(WARMUP_DURATION + pass_duration)
			progress_bar.value = ((float(step_index) + step_prog) / float(bench_configs.size())) * 100.0

			_record_frame_sample(delta)

			if timer >= pass_duration:
				_finalize_benchmark_step()
				step_index += 1
				if step_index < bench_configs.size():
					_start_benchmark_step(step_index)
				else:
					_finish_benchmark_and_return()

func _record_frame_sample(delta: float) -> void:
	var cfg = bench_configs[step_index]
	var frame_ms = delta * 1000.0
	var l0 = entity_count
	var l1 = 0
	var l2 = 0

	if cfg["use_dod"]:
		var lod_counts = bridge.get_lod_counts()
		if lod_counts.size() >= 3:
			l0 = lod_counts[0]; l1 = lod_counts[1]; l2 = lod_counts[2]
	else:
		l0 = oop_lod0_count; l1 = oop_lod1_count; l2 = oop_lod2_count

	current_step_samples.append({
		"frame_ms": frame_ms,
		"fps": 1000.0 / maxf(frame_ms, 0.0001),
		"logic_us": last_logic_us,
		"sync_us": last_sync_us,
		"total_us": last_logic_us + last_sync_us,
		"ram_mb": bridge.get_process_memory_mb() if bridge.has_method("get_process_memory_mb") else (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"lod0": l0,
		"lod1": l1,
		"lod2": l2
	})

func _finalize_benchmark_step() -> void:
	var cfg = bench_configs[step_index]
	var n = current_step_samples.size()
	if n == 0: return

	var raw_dir: String = "res://user_files"
	if typeof(GameSettings) != TYPE_NIL:
		raw_dir = GameSettings.get_current_raw_frames_folder()

	var raw_path = raw_dir.path_join("raw_%s.csv" % cfg["name"])
	var f_raw = FileAccess.open(raw_path, FileAccess.WRITE)
	if f_raw:
		f_raw.store_line("FrameIndex,FrameTime_ms,InstantFPS,Logic_us,Sync_us,TotalSim_us,SceneNodes,StaticRAM_MB,LOD0_Full,LOD1_Amortized,LOD2_Dormant")
		for i in range(n):
			var s = current_step_samples[i]
			f_raw.store_line("%d,%.4f,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%d,%d,%d" % [
				i + 1, s["frame_ms"], s["fps"], s["logic_us"], s["sync_us"], s["total_us"],
				s["nodes"], s["ram_mb"], s["lod0"], s["lod1"], s["lod2"]
			])
		f_raw.close()

	var sum_frame: float = 0.0
	var sum_logic: float = 0.0
	var sum_sync: float = 0.0
	var min_logic: float = 999999999.0
	var max_logic: float = 0.0
	var frame_times: Array[float] = []

	for s in current_step_samples:
		sum_frame += s["frame_ms"]
		sum_logic += s["logic_us"]
		sum_sync += s["sync_us"]
		min_logic = minf(min_logic, s["logic_us"])
		max_logic = maxf(max_logic, s["logic_us"])
		frame_times.append(s["frame_ms"])

	var avg_frame_ms = sum_frame / n
	var avg_fps = 1000.0 / maxf(avg_frame_ms, 0.0001)
	var avg_logic = sum_logic / n
	var avg_sync = sum_sync / n

	var variance: float = 0.0
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
		"entities": entity_count,
		"frames": n,
		"avg_fps": avg_fps,
		"avg_frame_ms": avg_frame_ms,
		"std_dev_ms": std_dev_ms,
		"fps_1_low": fps_1_low,
		"fps_01_low": fps_01_low,
		"avg_logic_us": avg_logic,
		"min_logic_us": min_logic,
		"max_logic_us": max_logic,
		"avg_sync_us": avg_sync,
		"avg_total_us": avg_logic + avg_sync,
		"nodes": current_step_samples[-1]["nodes"],
		"ram_mb": current_step_samples[0]["ram_mb"]
	})

func _finish_benchmark_and_return() -> void:
	state = BenchState.FINISHED
	set_process(false)
	if typeof(GameSettings) != TYPE_NIL:
		GameSettings.append_summary_results(summary_results)
		GameSettings.finish_current_benchmark()

# ==============================================================================
# OOP VERROKKISILMUKKA (ILMAN LOD:IA JA SAMALLA ETÄISYYSPERUSTEISELLA LOD:ILLA)
# ==============================================================================

func _tick_oop(delta: float, observer_pos: Vector3, lod_enabled: bool) -> void:
	var total = oop_nodes.size()
	if total == 0: return

	oop_sim_time += delta
	var cur_time = oop_sim_time

	if not lod_enabled:
		for i in range(total):
			var node: MeshInstance3D = oop_nodes[i]
			var pos: Vector3 = node.position
			var vel: Vector3 = oop_velocities[i]

			var angle = 1.25 * sin(cur_time * 1.5 + float(i) * 0.0137) * delta
			var c = cos(angle)
			var s = sin(angle)
			var nvx = vel.x * c - vel.z * s
			var nvz = vel.x * s + vel.z * c
			vel.x = nvx
			vel.z = nvz

			pos.x += vel.x * delta
			pos.z += vel.z * delta
			if pos.x < -50.0: pos.x = -50.0; vel.x = -vel.x
			elif pos.x > 50.0: pos.x = 50.0; vel.x = -vel.x
			if pos.z < -50.0: pos.z = -50.0; vel.z = -vel.z
			elif pos.z > 50.0: pos.z = 50.0; vel.z = -vel.z
			oop_velocities[i] = vel
			node.position = pos

		oop_lod0_count = total
		oop_lod1_count = 0
		oop_lod2_count = 0
		return

	oop_tick_counter += 1
	var obs_x = observer_pos.x
	var obs_z = observer_pos.z
	var lod1_sq = LOD1_RADIUS * LOD1_RADIUS
	var lod2_sq = LOD2_RADIUS * LOD2_RADIUS
	var dt1 = delta * 4.0
	var dt2 = delta * 16.0

	var c0: int = 0
	var c1: int = 0
	var c2: int = 0

	for i in range(total):
		var node: MeshInstance3D = oop_nodes[i]
		var pos: Vector3 = node.position
		var dx = pos.x - obs_x
		var dz = pos.z - obs_z
		var dist_sq = dx * dx + dz * dz

		if dist_sq < lod1_sq:
			c0 += 1
			var vel: Vector3 = oop_velocities[i]
			var angle = 1.25 * sin(cur_time * 1.5 + float(i) * 0.0137) * delta
			var c = cos(angle)
			var s = sin(angle)
			var nvx = vel.x * c - vel.z * s
			var nvz = vel.x * s + vel.z * c
			vel.x = nvx; vel.z = nvz
			pos.x += vel.x * delta
			pos.z += vel.z * delta
			if pos.x < -50.0: pos.x = -50.0; vel.x = -vel.x
			elif pos.x > 50.0: pos.x = 50.0; vel.x = -vel.x
			if pos.z < -50.0: pos.z = -50.0; vel.z = -vel.z
			elif pos.z > 50.0: pos.z = 50.0; vel.z = -vel.z
			oop_velocities[i] = vel
			node.position = pos
		elif dist_sq < lod2_sq:
			c1 += 1
			if ((i + oop_tick_counter) & 3) == 0:
				var vel: Vector3 = oop_velocities[i]
				var angle = 1.25 * sin(cur_time * 1.5 + float(i) * 0.0137) * dt1
				var c = cos(angle)
				var s = sin(angle)
				var nvx = vel.x * c - vel.z * s
				var nvz = vel.x * s + vel.z * c
				vel.x = nvx; vel.z = nvz
				pos.x += vel.x * dt1
				pos.z += vel.z * dt1
				if pos.x < -50.0: pos.x = -50.0; vel.x = -vel.x
				elif pos.x > 50.0: pos.x = 50.0; vel.x = -vel.x
				if pos.z < -50.0: pos.z = -50.0; vel.z = -vel.z
				elif pos.z > 50.0: pos.z = 50.0; vel.z = -vel.z
				oop_velocities[i] = vel
				node.position = pos
		else:
			c2 += 1
			if ((i + oop_tick_counter) & 15) == 0:
				var vel: Vector3 = oop_velocities[i]
				var angle = 1.25 * sin(cur_time * 1.5 + float(i) * 0.0137) * dt2
				var c = cos(angle)
				var s = sin(angle)
				var nvx = vel.x * c - vel.z * s
				var nvz = vel.x * s + vel.z * c
				vel.x = nvx; vel.z = nvz
				pos.x += vel.x * dt2
				pos.z += vel.z * dt2
				if pos.x < -50.0: pos.x = -50.0; vel.x = -vel.x
				elif pos.x > 50.0: pos.x = 50.0; vel.x = -vel.x
				if pos.z < -50.0: pos.z = -50.0; vel.z = -vel.z
				elif pos.z > 50.0: pos.z = 50.0; vel.z = -vel.z
				oop_velocities[i] = vel
				node.position = pos

	oop_lod0_count = c0
	oop_lod1_count = c1
	oop_lod2_count = c2

# ==============================================================================
# TELEMETRIA-HUD
# ==============================================================================

func _build_telemetry_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)

	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(560, 330)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	style.border_color = Color(0.20, 0.80, 0.55, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	hud_label = RichTextLabel.new()
	hud_label.bbcode_enabled = true
	hud_label.fit_content = true
	hud_label.custom_minimum_size = Vector2(530, 270)
	vbox.add_child(hud_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.custom_minimum_size = Vector2(530, 18)
	vbox.add_child(progress_bar)

func _update_hud() -> void:
	if is_benchmark_mode and state == BenchState.FINISHED:
		return

	var fps = Engine.get_frames_per_second()
	var frame_ms = 1000.0 / maxf(fps, 1.0)
	var ram_mb = bridge.get_process_memory_mb() if bridge.has_method("get_process_memory_mb") else (Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))
	var nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	var active_cam = bench_camera if is_benchmark_mode else player_camera
	var zone_name = _get_current_zone_name(active_cam.global_position) if active_cam else "Unknown"

	var active_dod = bench_configs[clampi(step_index, 0, bench_configs.size() - 1)]["use_dod"] if is_benchmark_mode else interactive_use_dod
	var active_lod = bench_configs[clampi(step_index, 0, bench_configs.size() - 1)]["lod_enabled"] if is_benchmark_mode else interactive_lod_enabled

	var l0 = entity_count
	var l1 = 0
	var l2 = 0
	if active_dod and bridge:
		var lod_counts = bridge.get_lod_counts()
		if lod_counts.size() >= 3:
			l0 = lod_counts[0]; l1 = lod_counts[1]; l2 = lod_counts[2]
	else:
		l0 = oop_lod0_count; l1 = oop_lod1_count; l2 = oop_lod2_count

	var arch_badge = "[color=#2ecc71]DOD (C++20 SoA)[/color]" if active_dod else "[color=#e74c3c]OOP (GDScript Nodes)[/color]"
	var lod_badge = "[color=#2ecc71]ON (25m / 55m)[/color]" if active_lod else "[color=#e67e22]OFF (100% Full)[/color]"

	var txt = ""
	if is_benchmark_mode:
		var safe_idx = clampi(step_index, 0, bench_configs.size() - 1)
		var cfg = bench_configs[safe_idx]
		var status_str = ""
		if state == BenchState.COUNTDOWN:
			status_str = "[color=yellow]Starting in %.1f s...[/color]" % (START_DELAY - timer)
		elif state == BenchState.WARMING_UP:
			status_str = "[color=orange]Warming up in Room 1...[/color]"
		elif state == BenchState.SAMPLING:
			status_str = "[color=green]Recording Tour (%.1f / %.1f s)...[/color]" % [timer, pass_duration]

		txt += "[b][color=#58a6ff]3-ROOM PRODUCTION FLY-THROUGH[/color][/b] | Pass %d/%d\n" % [safe_idx + 1, bench_configs.size()]
		txt += "Config: [b]%s[/b] | %s | LOD: %s\n" % [cfg["name"], arch_badge, lod_badge]
		txt += "Sector: [color=#79c0ff][b]%s[/b][/color] | %s\n\n" % [zone_name, status_str]
	else:
		txt += "[b][color=#58a6ff]3-ROOM INTERACTIVE SANDBOX[/color][/b] | %s | LOD: %s\n" % [arch_badge, lod_badge]
		txt += "Sector: [color=#79c0ff][b]%s[/b][/color]\n\n" % zone_name

	txt += "[code]"
	txt += "Active Entities : %d (5-Mesh Heterogeneous)\n" % entity_count
	txt += "LOD Distribution: Full: %d | Amort(4x): %d | Dormant(16x): %d\n" % [l0, l1, l2]
	txt += "FPS / FrameTime : %d FPS (%.2f ms)\n" % [fps, frame_ms]
	txt += "Sim Logic Tick  : %.2f us (%.4f ms)\n" % [last_logic_us, last_logic_us / 1000.0]
	txt += "GPU Sync Time   : %.2f us\n" % last_sync_us
	txt += "SceneTree Nodes : %d | Static RAM: %.1f MB\n" % [nodes, ram_mb]
	txt += "[/code]\n"

	if is_benchmark_mode:
		txt += "[color=gray][i][Tab] Switch to Free-Roam | [ESC] Abort Benchmark[/i][/color]"
	else:
		txt += "[color=gray][i][WASD] Move | [Mouse] Look | [M] Cursor | [1/2/3] Room | [O] DOD/OOP | [L] LOD | [V] Rings | [+/-] Count | [Tab] Bench[/i][/color]"

	hud_label.text = txt
