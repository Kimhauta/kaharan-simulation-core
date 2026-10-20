extends Node

@onready var bridge: SimulationBridge = $SimulationBridge
var print_timer: float = 0.0

func _ready() -> void:
	if bridge:
		print("[Godot] Yhteys muodostettu: ", bridge.get_bridge_version())
		# Luodaan 5 000 agenttia C++ -ytimen SoA-puskuriin
		bridge.spawn_agents(5000)
		print("[Godot] Agentteja aktiivisena: ", bridge.get_agent_count())
	else:
		printerr("[Godot Virhe] SimulationBridge-solmua ei löydy skenepuusta!")

func _process(delta: float) -> void:
	if not bridge:
		return
		
	# Tulostetaan simulaation tila kerran sekunnissa
	print_timer += delta
	if print_timer >= 1.0:
		print_timer = 0.0
		var count = bridge.get_agent_count()
		var tick_us = bridge.get_last_tick_microseconds()
		var p0 = bridge.get_agent_position(0)
		
		print("Agentteja: %d | C++ tick: %.2f us (%.4f ms) | Agentti 0 sijainti: (%.2f, %.2f, %.2f)" % [
			count, 
			tick_us, 
			tick_us / 1000.0, 
			p0.x, 
			p0.y, 
			p0.z
		])
