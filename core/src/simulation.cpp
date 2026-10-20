#include "core/simulation.hpp"
#include <random>

namespace kaharan::core {

    void SimulationWorld::spawn_test_agents(size_t count) {
        m_registry.clear();
        m_registry.reserve(count);

        // Fixed deterministic seed to ensure repeatable benchmark runs
        std::mt19937 rng(1337);
        std::uniform_real_distribution<float> pos_dist(-45.0f, 45.0f);
        std::uniform_real_distribution<float> vel_dist(-8.0f, 8.0f);

        for (size_t i = 0; i < count; ++i) {
            Vec3 pos{ pos_dist(rng), 0.0f, pos_dist(rng) };
            Vec3 vel{ vel_dist(rng), 0.0f, vel_dist(rng) };
            m_registry.create_entity(pos, vel, SimulationLOD::LOD0_Full);
        }
    }

    void SimulationWorld::tick(float delta_time) {
        const size_t total = m_registry.size();

        // Raw pointers with __restrict qualify that buffers do not overlap,
        // allowing the MSVC compiler to auto-vectorize the loop via SIMD instructions.
        Vec3* __restrict positions = m_registry.get_positions_data();
        Vec3* __restrict velocities = m_registry.get_velocities_data();

        // Cache-coherent linear traversal loop
        for (size_t i = 0; i < total; ++i) {
            positions[i].x += velocities[i].x * delta_time;
            positions[i].y += velocities[i].y * delta_time;
            positions[i].z += velocities[i].z * delta_time;

            // Symmetric boundary bounce logic along X-axis (-50.0 to 50.0)
            if (positions[i].x < -50.0f) {
                positions[i].x = -50.0f;
                velocities[i].x = -velocities[i].x;
            }
            else if (positions[i].x > 50.0f) {
                positions[i].x = 50.0f;
                velocities[i].x = -velocities[i].x;
            }

            // Symmetric boundary bounce logic along Z-axis (-50.0 to 50.0)
            if (positions[i].z < -50.0f) {
                positions[i].z = -50.0f;
                velocities[i].z = -velocities[i].z;
            }
            else if (positions[i].z > 50.0f) {
                positions[i].z = 50.0f;
                velocities[i].z = -velocities[i].z;
            }
        }
    }

} // namespace kaharan::core