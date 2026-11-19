/**
 * @file simulation.cpp
 * @brief Implementation of SimulationWorld agent spawning, kinematics, and Simulation LOD updates.
 */

#include "core/simulation.hpp"
#include <random>
#include <cmath>

namespace kaharan::core {

    void SimulationWorld::spawn_test_agents(size_t count) {
        m_registry.clear();
        m_registry.reserve(count);
        m_rng.seed(1337);
        m_tick_counter = 0;
        m_sim_time = 0.0f;

        std::uniform_real_distribution<float> pos_dist(-45.0f, 45.0f);
        std::uniform_real_distribution<float> vel_dist(-8.0f, 8.0f);

        for (size_t i = 0; i < count; ++i) {
            Vec3 pos{ pos_dist(m_rng), 0.0f, pos_dist(m_rng) };
            Vec3 vel{ vel_dist(m_rng), 0.0f, vel_dist(m_rng) };
            m_registry.create_entity(pos, vel, SimulationLOD::LOD0_Full);
        }

        m_lod0_count = count;
        m_lod1_count = 0;
        m_lod2_count = 0;
    }

    void SimulationWorld::add_test_agents(size_t count) {
        if (count == 0) return;

        size_t current = m_registry.size();
        m_registry.reserve(current + count);

        std::uniform_real_distribution<float> pos_dist(-45.0f, 45.0f);
        std::uniform_real_distribution<float> vel_dist(-8.0f, 8.0f);

        for (size_t i = 0; i < count; ++i) {
            Vec3 pos{ pos_dist(m_rng), 0.0f, pos_dist(m_rng) };
            Vec3 vel{ vel_dist(m_rng), 0.0f, vel_dist(m_rng) };
            m_registry.create_entity(pos, vel, SimulationLOD::LOD0_Full);
        }
    }

    namespace {
        /**
         * @brief Advances a single agent's position, optional steering heading, and arena bounds.
         *
         * @param xform    Mutable 48-byte transform matrix of the agent.
         * @param vel      Mutable velocity vector of the agent.
         * @param step_dt  Effective integration time step (scaled for amortized LOD tiers).
         * @param sim_time Current accumulated simulation time in seconds.
         * @param index    Entity index used to phase-shift steering oscillation.
         * @param steering Applies 2D heading rotation when true.
         */
        inline void step_agent(Transform3DData& xform, Vec3& vel, float step_dt, float sim_time, size_t index, bool steering) noexcept {
            if (steering) {
                const float phase = static_cast<float>(index) * 0.0137f;
                const float turn_rate = 1.25f * std::sin(sim_time * 1.5f + phase);
                const float angle = turn_rate * step_dt;
                const float c = std::cos(angle);
                const float s = std::sin(angle);
                const float new_vx = vel.x * c - vel.z * s;
                const float new_vz = vel.x * s + vel.z * c;
                vel.x = new_vx;
                vel.z = new_vz;
            }

            xform.origin_x += vel.x * step_dt;
            xform.origin_y += vel.y * step_dt;
            xform.origin_z += vel.z * step_dt;

            // Symmetrical elastic boundary reflection within [-50.0, 50.0] world bounds
            if (xform.origin_x < -50.0f) {
                xform.origin_x = -50.0f;
                vel.x = -vel.x;
            }
            else if (xform.origin_x > 50.0f) {
                xform.origin_x = 50.0f;
                vel.x = -vel.x;
            }

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

    void SimulationWorld::tick(float delta_time) {
        const size_t total = m_registry.size();
        if (total == 0) return;

        m_sim_time += delta_time;
        const float current_time = m_sim_time;
        const bool steering = m_steering_enabled;

        Transform3DData* __restrict transforms = m_registry.get_transforms_data();
        Vec3* __restrict velocities = m_registry.get_velocities_data();

        // 1. Baseline mode (LOD disabled): update every entity at full frame rate
        if (!m_lod_enabled) {
            for (size_t i = 0; i < total; ++i) {
                step_agent(transforms[i], velocities[i], delta_time, current_time, i, steering);
            }

            m_lod0_count = total;
            m_lod1_count = 0;
            m_lod2_count = 0;
            return;
        }

        // 2. Simulation LOD mode: radial distance classification + staggered time-slicing
        SimulationLOD* __restrict lods = m_registry.get_lods_data();
        const uint32_t frame_tick = ++m_tick_counter;

        const float obs_x = m_observer_pos.x;
        const float obs_z = m_observer_pos.z;
        const float lod1_sq = m_lod1_dist_sq;
        const float lod2_sq = m_lod2_dist_sq;

        const float dt_lod1 = delta_time * 4.0f;
        const float dt_lod2 = delta_time * 16.0f;

        size_t count_0 = 0;
        size_t count_1 = 0;
        size_t count_2 = 0;

        for (size_t i = 0; i < total; ++i) {
            Transform3DData& xform = transforms[i];

            const float dx = xform.origin_x - obs_x;
            const float dz = xform.origin_z - obs_z;
            const float dist_sq = (dx * dx) + (dz * dz);

            if (dist_sq < lod1_sq) {
                lods[i] = SimulationLOD::LOD0_Full;
                ++count_0;
                step_agent(xform, velocities[i], delta_time, current_time, i, steering);
            }
            else if (dist_sq < lod2_sq) {
                lods[i] = SimulationLOD::LOD1_Amortized;
                ++count_1;
                if (((static_cast<uint32_t>(i) + frame_tick) & 3u) == 0u) {
                    step_agent(xform, velocities[i], dt_lod1, current_time, i, steering);
                }
            }
            else {
                lods[i] = SimulationLOD::LOD2_Dormant;
                ++count_2;
                if (((static_cast<uint32_t>(i) + frame_tick) & 15u) == 0u) {
                    step_agent(xform, velocities[i], dt_lod2, current_time, i, steering);
                }
            }
        }

        m_lod0_count = count_0;
        m_lod1_count = count_1;
        m_lod2_count = count_2;
    }

} // namespace kaharan::core