#include "bridge/simulation_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace kaharan::bridge {

    void SimulationBridge::_bind_methods() {
        // Expose control API and telemetry queries to Godot ClassDB and GDScript
        godot::ClassDB::bind_method(godot::D_METHOD("get_bridge_version"), &SimulationBridge::get_bridge_version);
        godot::ClassDB::bind_method(godot::D_METHOD("spawn_agents", "count"), &SimulationBridge::spawn_agents);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_count"), &SimulationBridge::get_agent_count);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_position", "index"), &SimulationBridge::get_agent_position);
        godot::ClassDB::bind_method(godot::D_METHOD("get_last_tick_microseconds"), &SimulationBridge::get_last_tick_microseconds);
        godot::ClassDB::bind_method(godot::D_METHOD("sync_to_multimesh", "multimesh"), &SimulationBridge::sync_to_multimesh);
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

        // High-resolution profiling of the pure C++ simulation loop
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

    void SimulationBridge::sync_to_multimesh(godot::Ref<godot::MultiMesh> p_multimesh) {
        if (p_multimesh.is_null()) {
            return;
        }

        const auto& reg = m_world.get_registry();
        const size_t total = reg.size();
        if (total == 0) {
            return;
        }

        // Ensure MultiMesh configuration matches the entity buffer dimensions
        if (p_multimesh->get_transform_format() != godot::MultiMesh::TRANSFORM_3D) {
            p_multimesh->set_transform_format(godot::MultiMesh::TRANSFORM_3D);
        }
        if (p_multimesh->get_instance_count() != static_cast<int64_t>(total)) {
            p_multimesh->set_instance_count(static_cast<int64_t>(total));
        }

        const kaharan::core::Vec3* positions = reg.get_positions_data();

        // Fast-path synchronization: direct memory writes to Godot's GPU instance transforms
        for (size_t i = 0; i < total; ++i) {
            godot::Transform3D t;
            t.origin = godot::Vector3(positions[i].x, positions[i].y, positions[i].z);
            p_multimesh->set_instance_transform(static_cast<int32_t>(i), t);
        }
    }

    godot::String SimulationBridge::get_bridge_version() const {
        return "Kaharan Simulation Core v0.1.0 (C++20 SoA)";
    }

} // namespace kaharan::bridge