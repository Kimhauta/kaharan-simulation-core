#pragma once

#include "registry.hpp"
#include <random>

namespace kaharan::core {

    class SimulationWorld {
    private:
        EntityRegistry m_registry;
        std::mt19937 m_rng{ 1337 }; // Pysyvä satunnaislukugeneraattori

    public:
        SimulationWorld() = default;

        EntityRegistry& get_registry() noexcept { return m_registry; }
        const EntityRegistry& get_registry() const noexcept { return m_registry; }

        void spawn_test_agents(size_t count);
        void add_test_agents(size_t count); // <-- UUSI FUNKTIO
        void tick(float delta_time);
    };

} // namespace kaharan::core