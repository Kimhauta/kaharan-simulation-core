#include "bridge/simulation_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace kaharan::bridge {

    void SimulationBridge::_bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("get_bridge_version"), &SimulationBridge::get_bridge_version);
    }

    SimulationBridge::SimulationBridge() {
    }

    SimulationBridge::~SimulationBridge() {
    }

    void SimulationBridge::_ready() {
        godot::UtilityFunctions::print("[Kaharan Simulation Bridge] Initialized and connected to Godot!");
    }

    void SimulationBridge::_process(double delta) {
        // Core simulation tick will be invoked here
    }

    godot::String SimulationBridge::get_bridge_version() const {
        return "Kaharan Simulation Core v0.1.0 (C++20)";
    }

} // namespace kaharan::bridge