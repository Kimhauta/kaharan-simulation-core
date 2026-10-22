extends Node

const SETTINGS_PATH = "user://settings.cfg"

var vsync_enabled: bool = false
var default_entity_count: int = 5000
var auto_start_benchmark: bool = false

func _ready() -> void:
	load_settings()
	apply_settings()

func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	apply_settings()
	save_settings()

func apply_settings() -> void:
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("simulation", "default_entity_count", default_entity_count)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		vsync_enabled = config.get_value("display", "vsync_enabled", false)
		default_entity_count = config.get_value("simulation", "default_entity_count", 5000)
	else:
		# Oletusasetukset ensimmäisellä käynnistyksellä
		vsync_enabled = false
		default_entity_count = 5000
		save_settings()
