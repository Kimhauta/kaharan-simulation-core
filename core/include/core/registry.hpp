#pragma once

#include "common.hpp"
#include <vector>
#include <cassert>

namespace kaharan::core {

    class EntityRegistry {
    private:
        std::vector<EntityID> m_entities;
        std::vector<Vec3> m_positions;
        std::vector<Vec3> m_velocities;
        std::vector<SimulationLOD> m_lods;

    public:
        EntityRegistry() = default;

        void reserve(size_t capacity) {
            m_entities.reserve(capacity);
            m_positions.reserve(capacity);
            m_velocities.reserve(capacity);
            m_lods.reserve(capacity);
        }

        EntityID create_entity(const Vec3& position, const Vec3& velocity, SimulationLOD lod = SimulationLOD::LOD0_Full) {
            EntityID id = static_cast<EntityID>(m_entities.size());
            m_entities.push_back(id);
            m_positions.push_back(position);
            m_velocities.push_back(velocity);
            m_lods.push_back(lod);
            return id;
        }

        [[nodiscard]] size_t size() const noexcept { return m_entities.size(); }
        [[nodiscard]] Vec3* get_positions_data() noexcept { return m_positions.data(); }
        [[nodiscard]] const Vec3* get_positions_data() const noexcept { return m_positions.data(); }
        [[nodiscard]] Vec3* get_velocities_data() noexcept { return m_velocities.data(); }
        [[nodiscard]] const Vec3* get_velocities_data() const noexcept { return m_velocities.data(); }
        [[nodiscard]] SimulationLOD* get_lods_data() noexcept { return m_lods.data(); }

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