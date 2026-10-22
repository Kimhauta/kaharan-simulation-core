#include "core/simulation.hpp"
#include <random>

namespace kaharan::core {

    void SimulationWorld::spawn_test_agents(size_t count) {
        m_registry.clear();
        m_registry.reserve(count);

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

        Transform3DData* __restrict transforms = m_registry.get_transforms_data();
        Vec3* __restrict velocities = m_registry.get_velocities_data();

        for (size_t i = 0; i < total; ++i) {
            Transform3DData& xform = transforms[i];
            Vec3& vel = velocities[i];

            xform.origin_x += vel.x * delta_time;
            xform.origin_y += vel.y * delta_time;
            xform.origin_z += vel.z * delta_time;

            // Symmetric boundary bounce logic along X-axis (-50.0 to 50.0)
            if (xform.origin_x < -50.0f) {
                xform.origin_x = -50.0f;
                vel.x = -vel.x;
            }
            else if (xform.origin_x > 50.0f) {
                xform.origin_x = 50.0f;
                vel.x = -vel.x;
            }

            // Symmetric boundary bounce logic along Z-axis (-50.0 to 50.0)
            if (xform.origin_z < -50.0f) {
                xform.origin_z = -50.0f;
                vel.z = -vel.z;
            }
            else if (xform.origin_z > 50.0f) {
                xform.origin_z = 50.0f;
                vel.z = -vel.z;
            }
        }
    }

} // namespace kaharan::core