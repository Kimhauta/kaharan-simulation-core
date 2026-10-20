#pragma once

#include "common.hpp"
#include <vector>
#include <cassert>

namespace kaharan::core {

    /**
     * @brief Data-Oriented Entity Registry utilizing a Structure-of-Arrays (SoA) layout.
     * Separates component attributes into contiguous memory buffers to maximize
     * CPU L1/L2 cache locality and facilitate automatic SIMD vectorization.
     */
    class EntityRegistry {
    private:
        // Contiguous component streams (SoA layout)
        std::vector<EntityID> m_entities;
        std::vector<Vec3> m_positions;
        std::vector<Vec3> m_velocities;
        std::vector<SimulationLOD> m_lods;

    public:
        EntityRegistry() = default;

        /**
         * @brief Pre-allocates buffer capacity to eliminate heap allocations during runtime.
         */
        void reserve(size_t capacity) {
            m_entities.reserve(capacity);
            m_positions.reserve(capacity);
            m_velocities.reserve(capacity);
            m_lods.reserve(capacity);
        }

        /**
         * @brief Spawns a new entity into the packed contiguous arrays.
         * @return The numeric EntityID corresponding to its array index.
         */
        EntityID create_entity(const Vec3& position, const Vec3& velocity, SimulationLOD lod = SimulationLOD::LOD0_Full) {
            EntityID id = static_cast<EntityID>(m_entities.size());
            m_entities.push_back(id);
            m_positions.push_back(position);
            m_velocities.push_back(velocity);
            m_lods.push_back(lod);
            return id;
        }

        // Direct buffer pointers for tight, vectorized compute loops
        [[nodiscard]] size_t size() const noexcept { return m_entities.size(); }
        [[nodiscard]] Vec3* get_positions_data() noexcept { return m_positions.data(); }
        [[nodiscard]] const Vec3* get_positions_data() const noexcept { return m_positions.data(); }
        [[nodiscard]] Vec3* get_velocities_data() noexcept { return m_velocities.data(); }
        [[nodiscard]] const Vec3* get_velocities_data() const noexcept { return m_velocities.data(); }
        [[nodiscard]] SimulationLOD* get_lods_data() noexcept { return m_lods.data(); }

        /**
         * @brief Random access lookup for telemetry or targeted entity queries.
         */
        [[nodiscard]] const Vec3& get_position(EntityID id) const {
            assert(id < m_positions.size());
            return m_positions[id];
        }

        void clear() noexcept {
            m_entities.clear();
            m_positions.clear();
            m_velocities.clear();
            m_lods.clear();
        }
    };

} // namespace kaharan::core