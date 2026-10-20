#include "bridge/simulation_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace kaharan::bridge {

    void SimulationBridge::_bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("get_bridge_version"), &SimulationBridge::get_bridge_version);
        godot::ClassDB::bind_method(godot::D_METHOD("spawn_agents", "count"), &SimulationBridge::spawn_agents);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_count"), &SimulationBridge::get_agent_count);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_position", "index"), &SimulationBridge::get_agent_position);
        godot::ClassDB::bind_method(godot::D_METHOD("get_last_tick_microseconds"), &SimulationBridge::get_last_tick_microseconds);
    }

    SimulationBridge::SimulationBridge() = default;
    SimulationBridge::~SimulationBridge() = default;

    void SimulationBridge::_ready() {
        godot::UtilityFunctions::print("[SimulationBridge] Initialized. Ready to spawn headless agents.");
    }

    void SimulationBridge::_process(double delta) {
        if (m_world.get_registry().size() == 0) {
            return;
        }

        // High-precision timing of the pure C++ tick inside Godot's frame
        auto start_time = std::chrono::high_resolution_clock::now();

        m_world.tick(static_cast<float>(delta));

        auto end_time = std::chrono::high_resolution_clock::now();
        m_last_tick_us = std::chrono::duration<double, std::micro>(end_time - start_time).count();
    }

    void SimulationBridge::spawn_agents(int p_count) {
        if (p_count <= 0) return;
        m_world.spawn_test_agents(static_cast<size_t>(p_count));
        godot::UtilityFunctions::print("[SimulationBridge] Successfully spawned ", p_count, " agents into SoA buffer.");
    }

    int SimulationBridge::get_agent_count() const {
        return static_cast<int>(m_world.get_registry().size());
    }

    godot::Vector3 SimulationBridge::get_agent_position(int p_index) const {
        const auto& reg = m_world.get_registry();
        if (p_index < 0 || static_cast<size_t>(p_index) >= reg.size()) {
            return { 0.0f, 0.0f, 0.0f };
        }
        const auto& pos = reg.get_position(static_cast<kaharan::core::EntityID>(p_index));
        return { pos.x, pos.y, pos.z };
    }

    double SimulationBridge::get_last_tick_microseconds() const {
        return m_last_tick_us;
    }

    godot::String SimulationBridge::get_bridge_version() const {
        return "Kaharan Simulation Core v0.1.0 (C++20 SoA)";
    }

} // namespace kaharan::bridge