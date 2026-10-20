#pragma once

#include "registry.hpp"

namespace kaharan::core {

    class SimulationWorld {
    private:
        EntityRegistry m_registry;

    public:
        SimulationWorld() = default;

        EntityRegistry& get_registry() noexcept { return m_registry; }
        const EntityRegistry& get_registry() const noexcept { return m_registry; }

        void spawn_test_agents(size_t count);
        void tick(float delta_time);
    };

} // namespace kaharan::core