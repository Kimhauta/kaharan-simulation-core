extends Node

func _ready() -> void:
	if has_node("SimulationBridge"):
		var bridge = $SimulationBridge
		var version_str = bridge.get_bridge_version()
		print("[GDScript Test] Bridge answered with version: ", version_str)
	else:
		printerr("[GDScript Test] SimulationBridge node not found!")
