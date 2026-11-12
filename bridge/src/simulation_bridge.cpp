#include "bridge/simulation_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#pragma comment(lib, "psapi.lib")
#endif

#include <chrono>
#include <cstring>

namespace kaharan::bridge {

    void SimulationBridge::_bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("get_bridge_version"), &SimulationBridge::get_bridge_version);
        godot::ClassDB::bind_method(godot::D_METHOD("spawn_agents", "count"), &SimulationBridge::spawn_agents);
        godot::ClassDB::bind_method(godot::D_METHOD("add_agents", "count"), &SimulationBridge::add_agents);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_count"), &SimulationBridge::get_agent_count);
        godot::ClassDB::bind_method(godot::D_METHOD("get_agent_position", "index"), &SimulationBridge::get_agent_position);
        godot::ClassDB::bind_method(godot::D_METHOD("get_last_tick_microseconds"), &SimulationBridge::get_last_tick_microseconds);

        godot::ClassDB::bind_method(godot::D_METHOD("set_lod_enabled", "enabled"), &SimulationBridge::set_lod_enabled);
        godot::ClassDB::bind_method(godot::D_METHOD("is_lod_enabled"), &SimulationBridge::is_lod_enabled);
        godot::ClassDB::bind_method(godot::D_METHOD("set_observer_position", "position"), &SimulationBridge::set_observer_position);
        godot::ClassDB::bind_method(godot::D_METHOD("set_lod_thresholds", "lod1_dist", "lod2_dist"), &SimulationBridge::set_lod_thresholds);
        godot::ClassDB::bind_method(godot::D_METHOD("get_lod_counts"), &SimulationBridge::get_lod_counts);

        godot::ClassDB::bind_method(godot::D_METHOD("sync_to_multimesh", "multimesh"), &SimulationBridge::sync_to_multimesh);
        godot::ClassDB::bind_method(godot::D_METHOD("sync_to_multimesh_range", "multimesh", "start_index", "count"), &SimulationBridge::sync_to_multimesh_range);

        godot::ClassDB::bind_method(godot::D_METHOD("set_steering_enabled", "enabled"), &SimulationBridge::set_steering_enabled);

        godot::ClassDB::bind_method(godot::D_METHOD("get_process_memory_mb"), &SimulationBridge::get_process_memory_mb);
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

    void SimulationBridge::add_agents(int p_count) {
        if (p_count <= 0) return;
        m_world.add_test_agents(static_cast<size_t>(p_count));
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

    double SimulationBridge::get_process_memory_mb() const {
#ifdef _WIN32
        PROCESS_MEMORY_COUNTERS pmc;
        if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) {
            return static_cast<double>(pmc.WorkingSetSize) / (1024.0 * 1024.0);
        }
#endif
        return 0.0;
    }

    void SimulationBridge::set_lod_enabled(bool p_enabled) {
        m_world.set_lod_enabled(p_enabled);
    }

    bool SimulationBridge::is_lod_enabled() const {
        return m_world.is_lod_enabled();
    }

    void SimulationBridge::set_observer_position(const godot::Vector3& p_pos) {
        m_world.set_observer_position({ p_pos.x, p_pos.y, p_pos.z });
    }

    void SimulationBridge::set_lod_thresholds(float p_lod1_dist, float p_lod2_dist) {
        m_world.set_lod_thresholds(p_lod1_dist, p_lod2_dist);
    }

    godot::PackedInt32Array SimulationBridge::get_lod_counts() const {
        godot::PackedInt32Array counts;
        counts.resize(3);
        counts[0] = static_cast<int32_t>(m_world.get_lod0_count());
        counts[1] = static_cast<int32_t>(m_world.get_lod1_count());
        counts[2] = static_cast<int32_t>(m_world.get_lod2_count());
        return counts;
    }

    godot::String SimulationBridge::get_bridge_version() const {
        return "Kaharan Simulation Core v0.2.0 (C++20 SoA + Simulation LOD)";
    }

    void SimulationBridge::sync_to_multimesh(godot::Ref<godot::MultiMesh> p_multimesh) {
        if (p_multimesh.is_null()) return;

        const auto& reg = m_world.get_registry();
        const size_t total = reg.size();
        if (total == 0) return;

        if (p_multimesh->get_transform_format() != godot::MultiMesh::TRANSFORM_3D) {
            p_multimesh->set_transform_format(godot::MultiMesh::TRANSFORM_3D);
        }
        if (p_multimesh->is_using_colors()) p_multimesh->set_use_colors(false);
        if (p_multimesh->is_using_custom_data()) p_multimesh->set_use_custom_data(false);

        if (p_multimesh->get_instance_count() != static_cast<int64_t>(total)) {
            p_multimesh->set_instance_count(static_cast<int64_t>(total));
        }

        const float* raw_transforms = reg.get_raw_float_data();
        const size_t total_floats = total * 12;

        godot::PackedFloat32Array buffer;
        buffer.resize(static_cast<int64_t>(total_floats));
        std::memcpy(buffer.ptrw(), raw_transforms, total_floats * sizeof(float));

        p_multimesh->set_buffer(buffer);
    }

    void SimulationBridge::sync_to_multimesh_range(godot::Ref<godot::MultiMesh> p_multimesh, int p_start_index, int p_count) {
        if (p_multimesh.is_null() || p_count <= 0) return;

        const auto& registry = m_world.get_registry();
        const int total_entities = static_cast<int>(registry.size());
        if (p_start_index < 0 || p_start_index >= total_entities) return;

        const int actual_count = (p_start_index + p_count > total_entities) ? (total_entities - p_start_index) : p_count;

        if (p_multimesh->get_transform_format() != godot::MultiMesh::TRANSFORM_3D) {
            p_multimesh->set_transform_format(godot::MultiMesh::TRANSFORM_3D);
        }
        if (p_multimesh->is_using_colors()) p_multimesh->set_use_colors(false);
        if (p_multimesh->is_using_custom_data()) p_multimesh->set_use_custom_data(false);

        if (p_multimesh->get_instance_count() != actual_count) {
            p_multimesh->set_instance_count(actual_count);
        }

        const float* raw_transforms_slice = registry.get_raw_float_data() + (static_cast<size_t>(p_start_index) * 12);
        const size_t total_floats = static_cast<size_t>(actual_count) * 12;

        godot::PackedFloat32Array buffer;
        buffer.resize(static_cast<int64_t>(total_floats));
        std::memcpy(buffer.ptrw(), raw_transforms_slice, total_floats * sizeof(float));

        p_multimesh->set_buffer(buffer);
    }

    void SimulationBridge::set_steering_enabled(bool p_enabled) {
        m_world.set_steering_enabled(p_enabled);
    }

} // namespace kaharan::bridge