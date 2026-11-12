#pragma once

#include "registry.hpp"
#include <random>
#include <cstdint>

namespace kaharan::core {

    class SimulationWorld {
    private:
        EntityRegistry m_registry;
        std::mt19937 m_rng{ 1337 };

        bool m_steering_enabled{ false };
        float m_sim_time{ 0.0f };

        bool m_lod_enabled{ false };
        Vec3 m_observer_pos{ 0.0f, 0.0f, 0.0f };
        float m_lod1_dist_sq{ 25.0f * 25.0f };
        float m_lod2_dist_sq{ 55.0f * 55.0f };
        uint32_t m_tick_counter{ 0 };

        size_t m_lod0_count{ 0 };
        size_t m_lod1_count{ 0 };
        size_t m_lod2_count{ 0 };

    public:
        SimulationWorld() = default;

        EntityRegistry& get_registry() noexcept { return m_registry; }
        const EntityRegistry& get_registry() const noexcept { return m_registry; }

        void spawn_test_agents(size_t count);
        void add_test_agents(size_t count);
        void tick(float delta_time);

        void set_steering_enabled(bool enabled) noexcept { m_steering_enabled = enabled; }
        [[nodiscard]] bool is_steering_enabled() const noexcept { return m_steering_enabled; }

        void set_lod_enabled(bool enabled) noexcept { m_lod_enabled = enabled; }
        [[nodiscard]] bool is_lod_enabled() const noexcept { return m_lod_enabled; }

        void set_observer_position(const Vec3& pos) noexcept { m_observer_pos = pos; }
        void set_lod_thresholds(float lod1_distance, float lod2_distance) noexcept {
            m_lod1_dist_sq = lod1_distance * lod1_distance;
            m_lod2_dist_sq = lod2_distance * lod2_distance;
        }

        [[nodiscard]] size_t get_lod0_count() const noexcept { return m_lod0_count; }
        [[nodiscard]] size_t get_lod1_count() const noexcept { return m_lod1_count; }
        [[nodiscard]] size_t get_lod2_count() const noexcept { return m_lod2_count; }
    };

} // namespace kaharan::core