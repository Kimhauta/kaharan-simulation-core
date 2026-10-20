#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include "core/simulation.hpp"
#include <chrono>

namespace kaharan::bridge {

    class SimulationBridge : public godot::Node {
        GDCLASS(SimulationBridge, godot::Node);

    private:
        // Pure C++ headless simulation world
        kaharan::core::SimulationWorld m_world;

        // Telemetry / Profiling
        double m_last_tick_us{ 0.0 };

    protected:
        static void _bind_methods();

    public:
        SimulationBridge();
        ~SimulationBridge();

        void _ready() override;
        void _process(double delta) override;

        // Bridge API exposed to Godot
        void spawn_agents(int p_count);
        [[nodiscard]] int get_agent_count() const;
        [[nodiscard]] godot::Vector3 get_agent_position(int p_index) const;
        [[nodiscard]] double get_last_tick_microseconds() const;

        [[nodiscard]] godot::String get_bridge_version() const;
    };

} // namespace kaharan::bridge