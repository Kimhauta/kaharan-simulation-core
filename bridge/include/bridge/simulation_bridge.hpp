#pragma once

#include <godot_cpp/classes/node.hpp>

namespace kaharan::bridge {

    class SimulationBridge : public godot::Node {
        GDCLASS(SimulationBridge, godot::Node);

    protected:
        static void _bind_methods();

    public:
        SimulationBridge();
        ~SimulationBridge();

        void _ready() override;
        void _process(double delta) override;

        godot::String get_bridge_version() const;
    };

} // namespace kaharan::bridge