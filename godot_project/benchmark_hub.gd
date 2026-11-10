extends Control

const MAIN_MENU_PATH = "res://main_menu.tscn"
const RESULTS_PATH = "res://benchmark_results.tscn"

# Skennepolut
const SCENE_SYNTHETIC_RENDER = "res://bench_synthetic_render.tscn"
const SCENE_SYNTHETIC_HEADLESS = "res://bench_synthetic_headless.tscn"
const SCENE_RAMP_RENDER = "res://bench_ramp_up_render.tscn"
const SCENE_RAMP_HEADLESS = "res://bench_ramp_up_headless.tscn"
const SCENE_FLYTHROUGH = "res://greybox_level.tscn"

@onready var btn_back: Button = find_child("BtnBack", true, false) as Button
@onready var btn_view_results: Button = find_child("BtnViewResults", true, false) as Button

@onready var btn_run_synthetic_render: Button = find_child("BtnRunSyntheticRender", true, false) as Button
@onready var btn_run_synthetic_headless: Button = find_child("BtnRunSyntheticHeadless", true, false) as Button
@onready var btn_run_dynamic_ramp: Button = find_child("BtnRunDynamicRamp", true, false) as Button
@onready var btn_run_full_suite: Button = find_child("BtnRunFullSuite", true, false) as Button

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if btn_back: btn_back.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_PATH))
	if btn_view_results: btn_view_results.pressed.connect(func(): get_tree().change_scene_to_file(RESULTS_PATH))
	
	# Yksittäiset testikäynnistykset
	if btn_run_synthetic_render:
		btn_run_synthetic_render.pressed.connect(func(): get_tree().change_scene_to_file(SCENE_SYNTHETIC_RENDER))
	if btn_run_synthetic_headless:
		btn_run_synthetic_headless.pressed.connect(func(): get_tree().change_scene_to_file(SCENE_SYNTHETIC_HEADLESS))
	if btn_run_dynamic_ramp:
		btn_run_dynamic_ramp.pressed.connect(func(): get_tree().change_scene_to_file(SCENE_RAMP_RENDER))
		
	# Täysi automatisoitu soittolista
	if btn_run_full_suite:
		btn_run_full_suite.pressed.connect(_on_run_full_suite_pressed)

func _on_run_full_suite_pressed() -> void:
	var full_playlist: Array[String] = [
		SCENE_SYNTHETIC_RENDER,    # 1. Synteettinen 12-vaiheinen (Rendered)
		SCENE_SYNTHETIC_HEADLESS,  # 2. Synteettinen 12-vaiheinen (Headless)
		SCENE_RAMP_RENDER,         # 3. Dynamic Ramp-Up Emitter (Rendered)
		SCENE_RAMP_HEADLESS,       # 4. Dynamic Ramp-Up Emitter (Headless)
		SCENE_FLYTHROUGH           # 5. Fly-Through LOD (Dummy kunnes kenttä rakennetaan)
	]
	GameSettings.start_benchmark_suite(full_playlist)
