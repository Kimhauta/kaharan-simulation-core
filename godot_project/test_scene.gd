extends Node3D

@onready var bridge: SimulationBridge = $SimulationBridge
@onready var mmi: MultiMeshInstance3D = $MultiMeshInstance3D

var print_timer: float = 0.0

func _ready() -> void:
	if bridge and mmi:
		# Luodaan 5 000 agenttia C++ SoA -puskuriin
		bridge.spawn_agents(5000)
		print("[Visualisointi] 5 000 agenttia alustettu ja kytketty MultiMeshiin.")
	else:
		printerr("SimulationBridge tai MultiMeshInstance3D puuttuu skenestä!")

func _process(delta: float) -> void:
	if not bridge or not mmi:
		return
		
	# Synkronoidaan kaikki 5 000 sijaintia C++:sta suoraan GPU-puskuriin
	bridge.sync_to_multimesh(mmi.multimesh)

	# Tulostetaan profilointiluvut kerran sekunnissa
	print_timer += delta
	if print_timer >= 1.0:
		print_timer = 0.0
		var tick_us = bridge.get_last_tick_microseconds()
		var fps = Engine.get_frames_per_second()
		print("FPS: %d | C++ tick: %.2f us (%.4f ms)" % [fps, tick_us, tick_us / 1000.0])
