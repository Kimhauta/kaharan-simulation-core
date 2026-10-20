#include "core/simulation.hpp"
#include <random>

namespace kaharan::core {

    void SimulationWorld::spawn_test_agents(size_t count) {
        m_registry.clear();
        m_registry.reserve(count);

        std::mt19937 rng(1337);
        std::uniform_real_distribution<float> pos_dist(-50.0f, 50.0f);
        std::uniform_real_distribution<float> vel_dist(-2.0f, 2.0f);

        for (size_t i = 0; i < count; ++i) {
            Vec3 pos{ pos_dist(rng), 0.0f, pos_dist(rng) };
            Vec3 vel{ vel_dist(rng), 0.0f, vel_dist(rng) };
            m_registry.create_entity(pos, vel, SimulationLOD::LOD0_Full);
        }
    }

    void SimulationWorld::tick(float delta_time) {
        const size_t total = m_registry.size();
        Vec3* __restrict positions = m_registry.get_positions_data();
        const Vec3* __restrict velocities = m_registry.get_velocities_data();

        for (size_t i = 0; i < total; ++i) {
            positions[i].x += velocities[i].x * delta_time;
            positions[i].y += velocities[i].y * delta_time;
            positions[i].z += velocities[i].z * delta_time;

            if (positions[i].x < -50.0f || positions[i].x > 50.0f) {
                positions[i].x = (positions[i].x < -50.0f) ? -50.0f : 50.0f;
            }
            if (positions[i].z < -50.0f || positions[i].z > 50.0f) {
                positions[i].z = (positions[i].z < -50.0f) ? -50.0f : 50.0f;
            }
        }
    }

} // namespace kaharan::core