#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include "core/simulation.hpp"
#include <chrono>

namespace kaharan::bridge {

    class SimulationBridge : public godot::Node {
        GDCLASS(SimulationBridge, godot::Node);

    private:
        kaharan::core::SimulationWorld m_world;
        double m_last_tick_us{ 0.0 };

    protected:
        static void _bind_methods();

    public:
        SimulationBridge();
        ~SimulationBridge();

        void _ready() override;
        void _process(double delta) override;

        void spawn_agents(int p_count);
        void add_agents(int p_count);
        [[nodiscard]] int get_agent_count() const;
        [[nodiscard]] godot::Vector3 get_agent_position(int p_index) const;
        [[nodiscard]] double get_last_tick_microseconds() const;
        [[nodiscard]] double get_process_memory_mb() const;

        // Simulation LOD -ohjaus ja telemetria
        void set_lod_enabled(bool p_enabled);
        [[nodiscard]] bool is_lod_enabled() const;
        void set_observer_position(const godot::Vector3& p_pos);
        void set_lod_thresholds(float p_lod1_dist, float p_lod2_dist);
        [[nodiscard]] godot::PackedInt32Array get_lod_counts() const;

        void sync_to_multimesh(godot::Ref<godot::MultiMesh> p_multimesh);
        void sync_to_multimesh_range(godot::Ref<godot::MultiMesh> p_multimesh, int p_start_index, int p_count);
        void set_steering_enabled(bool p_enabled);

        [[nodiscard]] godot::String get_bridge_version() const;
    };

} // namespace kaharan::bridge