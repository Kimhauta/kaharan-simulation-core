/**
 * @file simulation.hpp
 * @brief High-level simulation controller orchestrating deterministic kinematics and Simulation LOD.
 */

#pragma once

#include "registry.hpp"
#include <random>
#include <cstdint>

namespace kaharan::core {

    /**
     * @class SimulationWorld
     * @brief Engine-independent simulation domain owning the EntityRegistry and update loops.
     *
     * Executes deterministic 3D agent kinematics, arena boundary collisions, optional
     * trigonometric steering, and distance-based 3-tier Simulation LOD scheduling over
     * contiguous SoA memory buffers.
     */
    class SimulationWorld {
    private:
        EntityRegistry m_registry;    ///< Contiguous SoA storage for all active entities.
        std::mt19937 m_rng{ 1337 };   ///< Deterministic Mersenne Twister PRNG for reproducible spawns.

        bool m_steering_enabled{ false }; ///< Enables sinusoidal angular steering when true.
        float m_sim_time{ 0.0f };         ///< Accumulated simulation time in seconds.

        bool m_lod_enabled{ false };                 ///< Enables 3-tier distance-based LOD scheduling when true.
        Vec3 m_observer_pos{ 0.0f, 0.0f, 0.0f };     ///< Observer world coordinates for LOD distance checks.
        float m_lod1_dist_sq{ 25.0f * 25.0f };       ///< Squared radial threshold between LOD0 and LOD1.
        float m_lod2_dist_sq{ 55.0f * 55.0f };       ///< Squared radial threshold between LOD1 and LOD2.
        uint32_t m_tick_counter{ 0 };                ///< Monotonic frame counter for staggered modulo scheduling.

        size_t m_lod0_count{ 0 }; ///< Active entity count in LOD0_Full during the last tick.
        size_t m_lod1_count{ 0 }; ///< Active entity count in LOD1_Amortized during the last tick.
        size_t m_lod2_count{ 0 }; ///< Active entity count in LOD2_Dormant during the last tick.

    public:
        /**
         * @brief Constructs a SimulationWorld with default deterministic configuration.
         */
        SimulationWorld() = default;

        /**
         * @brief Provides mutable access to the underlying SoA EntityRegistry.
         *
         * @return Reference to the owned EntityRegistry.
         */
        EntityRegistry& get_registry() noexcept { return m_registry; }

        /**
         * @brief Provides read-only access to the underlying SoA EntityRegistry.
         *
         * @return Const reference to the owned EntityRegistry.
         */
        const EntityRegistry& get_registry() const noexcept { return m_registry; }

        /**
         * @brief Resets the world and deterministically spawns a fixed population of agents.
         *
         * Clears existing entities, resets the PRNG seed to 1337, pre-allocates SoA buffers,
         * and initializes all agents within the [-45, 45] XZ spawn bounds.
         *
         * @param count Number of test agents to create.
         */
        void spawn_test_agents(size_t count);

        /**
         * @brief Incrementally appends new agents to the running simulation without resetting state.
         *
         * Used by dynamic Ramp-Up saturation benchmarks to grow population smoothly
         * while preserving existing entity positions and PRNG sequence state.
         *
         * @param count Number of additional agents to append.
         */
        void add_test_agents(size_t count);

        /**
         * @brief Advances the simulation state by one time step.
         *
         * Iterates linearly over SoA buffers using `__restrict` pointers to enable
         * compiler SIMD auto-vectorization and staggered Simulation LOD execution.
         *
         * @param delta_time Frame delta time in seconds.
         */
        void tick(float delta_time);

        /**
         * @brief Enables or disables per-agent trigonometric steering oscillation.
         *
         * @param enabled True to apply sinusoidal heading turns; false for purely linear motion.
         */
        void set_steering_enabled(bool enabled) noexcept { m_steering_enabled = enabled; }

        /**
         * @brief Checks whether trigonometric steering is currently active.
         *
         * @return True if steering is enabled.
         */
        [[nodiscard]] bool is_steering_enabled() const noexcept { return m_steering_enabled; }

        /**
         * @brief Enables or disables distance-based 3-tier Simulation LOD scheduling.
         *
         * @param enabled True to enable amortized updates; false to update all entities every tick.
         */
        void set_lod_enabled(bool enabled) noexcept { m_lod_enabled = enabled; }

        /**
         * @brief Checks whether Simulation LOD is currently active.
         *
         * @return True if Simulation LOD is enabled.
         */
        [[nodiscard]] bool is_lod_enabled() const noexcept { return m_lod_enabled; }

        /**
         * @brief Sets the observer world position used to evaluate squared radial LOD distances.
         *
         * @param pos Current observer (camera/player) coordinates.
         */
        void set_observer_position(const Vec3& pos) noexcept { m_observer_pos = pos; }

        /**
         * @brief Configures radial distance thresholds separating LOD0, LOD1, and LOD2 zones.
         *
         * Stores squared distances internally to avoid per-entity square root operations.
         *
         * @param lod1_distance Radius in meters transitioning from LOD0_Full to LOD1_Amortized.
         * @param lod2_distance Radius in meters transitioning from LOD1_Amortized to LOD2_Dormant.
         */
        void set_lod_thresholds(float lod1_distance, float lod2_distance) noexcept {
            m_lod1_dist_sq = lod1_distance * lod1_distance;
            m_lod2_dist_sq = lod2_distance * lod2_distance;
        }

        /**
         * @brief Returns the number of entities classified into LOD0_Full on the last tick.
         *
         * @return Entity count in LOD0.
         */
        [[nodiscard]] size_t get_lod0_count() const noexcept { return m_lod0_count; }

        /**
         * @brief Returns the number of entities classified into LOD1_Amortized on the last tick.
         *
         * @return Entity count in LOD1.
         */
        [[nodiscard]] size_t get_lod1_count() const noexcept { return m_lod1_count; }

        /**
         * @brief Returns the number of entities classified into LOD2_Dormant on the last tick.
         *
         * @return Entity count in LOD2.
         */
        [[nodiscard]] size_t get_lod2_count() const noexcept { return m_lod2_count; }
    };

} // namespace kaharan::core