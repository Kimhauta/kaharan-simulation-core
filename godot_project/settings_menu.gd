extends Control

const MAIN_MENU_PATH = "res://main_menu.tscn"

# UI-viittaukset
@onready var check_vsync: CheckButton = find_child("CheckVSync", true, false) as CheckButton
@onready var option_window_mode: OptionButton = find_child("OptionWindowMode", true, false) as OptionButton
@onready var option_max_fps: OptionButton = find_child("OptionMaxFPS", true, false) as OptionButton

@onready var option_profile: OptionButton = find_child("OptionProfile", true, false) as OptionButton
@onready var option_mesh_mode: OptionButton = find_child("OptionMeshMode", true, false) as OptionButton
@onready var option_workload: OptionButton = find_child("OptionWorkload", true, false) as OptionButton

@onready var option_growth_mode: OptionButton = find_child("OptionGrowthMode", true, false) as OptionButton
@onready var option_base_rate: OptionButton = find_child("OptionBaseRate", true, false) as OptionButton
@onready var option_accel: OptionButton = find_child("OptionAccel", true, false) as OptionButton

@onready var btn_reset: Button = find_child("BtnReset", true, false) as Button
@onready var btn_back: Button = find_child("BtnBack", true, false) as Button

const FPS_OPTIONS: Array[int] = [0, 30, 60, 120, 144]
const BASE_RATE_OPTIONS: Array[float] = [100.0, 300.0, 500.0, 1000.0]
const ACCEL_OPTIONS: Array[float] = [25.0, 75.0, 150.0, 300.0]

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_populate_dropdowns()
	_load_current_values()
	_connect_signals()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: _go_back()

func _populate_dropdowns() -> void:
	if option_window_mode:
		option_window_mode.clear()
		option_window_mode.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
		option_window_mode.add_item("Exclusive Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		option_window_mode.add_item("Borderless Window", DisplayServer.WINDOW_MODE_FULLSCREEN)

	if option_max_fps:
		option_max_fps.clear()
		option_max_fps.add_item("Uncapped (0)")
		option_max_fps.add_item("30 FPS")
		option_max_fps.add_item("60 FPS")
		option_max_fps.add_item("120 FPS")
		option_max_fps.add_item("144 FPS")

	if option_profile:
		option_profile.clear()
		option_profile.add_item("Quick (4 s / stage)", 0)
		option_profile.add_item("Standard (10 s / stage)", 1)
		option_profile.add_item("Endurance Soak (5 min / stage)", 2)

	if option_mesh_mode:
		option_mesh_mode.clear()
		option_mesh_mode.add_item("Full Matrix (1 & 5 Meshes)", 0)
		option_mesh_mode.add_item("Single-Mesh Only (1 Draw Call)", 1)
		option_mesh_mode.add_item("Multi-Mesh Only (5 Draw Calls)", 2)

	if option_workload:
		option_workload.clear()
		option_workload.add_item("Standard (1k, 5k, 10k)", 0)
		option_workload.add_item("Lightweight (500, 1k, 2.5k)", 1)
		option_workload.add_item("Extreme Stress (5k, 10k, 25k)", 2)

	if option_growth_mode:
		option_growth_mode.clear()
		option_growth_mode.add_item("Progressive Acceleration", 0)
		option_growth_mode.add_item("Constant Linear", 1)

	if option_base_rate:
		option_base_rate.clear()
		option_base_rate.add_item("100 agents / s")
		option_base_rate.add_item("300 agents / s (Default)")
		option_base_rate.add_item("500 agents / s")
		option_base_rate.add_item("1000 agents / s")

	if option_accel:
		option_accel.clear()
		option_accel.add_item("+25 agents / s² (Gentle)")
		option_accel.add_item("+75 agents / s² (Balanced)")
		option_accel.add_item("+150 agents / s² (Aggressive)")
		option_accel.add_item("+300 agents / s² (Rapid)")

func _load_current_values() -> void:
	if typeof(GameSettings) == TYPE_NIL: return

	if check_vsync:
		check_vsync.set_pressed_no_signal(GameSettings.vsync_enabled)
		check_vsync.text = "On" if GameSettings.vsync_enabled else "Off"

	if option_window_mode:
		for i in range(option_window_mode.item_count):
			if option_window_mode.get_item_id(i) == GameSettings.window_mode:
				option_window_mode.select(i)
				break

	if option_max_fps:
		var idx = FPS_OPTIONS.find(GameSettings.max_fps_limit)
		option_max_fps.select(idx if idx != -1 else 0)

	if option_profile: option_profile.select(clampi(GameSettings.benchmark_profile, 0, 2))
	if option_mesh_mode: option_mesh_mode.select(clampi(GameSettings.synthetic_mesh_mode, 0, 2))
	if option_workload: option_workload.select(clampi(GameSettings.synthetic_workload, 0, 2))
	if option_growth_mode: option_growth_mode.select(clampi(GameSettings.ramp_growth_mode, 0, 1))

	if option_base_rate:
		var b_idx = BASE_RATE_OPTIONS.find(GameSettings.ramp_base_spawn_rate)
		option_base_rate.select(b_idx if b_idx != -1 else 1)

	if option_accel:
		var a_idx = ACCEL_OPTIONS.find(GameSettings.ramp_acceleration_factor)
		option_accel.select(a_idx if a_idx != -1 else 1)

func _connect_signals() -> void:
	if check_vsync: check_vsync.toggled.connect(func(v): check_vsync.text = "On" if v else "Off"; GameSettings.vsync_enabled = v; GameSettings.apply_settings(); GameSettings.save_settings())
	if option_window_mode: option_window_mode.item_selected.connect(func(i): GameSettings.window_mode = option_window_mode.get_item_id(i); GameSettings.apply_settings(); GameSettings.save_settings())
	if option_max_fps: option_max_fps.item_selected.connect(func(i): GameSettings.max_fps_limit = FPS_OPTIONS[i]; GameSettings.apply_settings(); GameSettings.save_settings())
	if option_profile: option_profile.item_selected.connect(func(i): GameSettings.benchmark_profile = i; GameSettings.save_settings())
	if option_mesh_mode: option_mesh_mode.item_selected.connect(func(i): GameSettings.synthetic_mesh_mode = i; GameSettings.save_settings())
	if option_workload: option_workload.item_selected.connect(func(i): GameSettings.synthetic_workload = i; GameSettings.save_settings())
	if option_growth_mode: option_growth_mode.item_selected.connect(func(i): GameSettings.ramp_growth_mode = i; GameSettings.save_settings())
	if option_base_rate: option_base_rate.item_selected.connect(func(i): GameSettings.ramp_base_spawn_rate = BASE_RATE_OPTIONS[i]; GameSettings.save_settings())
	if option_accel: option_accel.item_selected.connect(func(i): GameSettings.ramp_acceleration_factor = ACCEL_OPTIONS[i]; GameSettings.save_settings())

	if btn_reset: btn_reset.pressed.connect(_on_reset_pressed)
	if btn_back: btn_back.pressed.connect(_go_back)

func _on_reset_pressed() -> void:
	GameSettings.vsync_enabled = false
	GameSettings.window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	GameSettings.max_fps_limit = 0
	GameSettings.benchmark_profile = 0
	GameSettings.synthetic_mesh_mode = 0
	GameSettings.synthetic_workload = 0
	GameSettings.ramp_growth_mode = 0
	GameSettings.ramp_base_spawn_rate = 300.0
	GameSettings.ramp_acceleration_factor = 75.0
	GameSettings.apply_settings()
	GameSettings.save_settings()
	_load_current_values()

func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
