#pragma once

#include "common.hpp"
#include <vector>
#include <cassert>

namespace kaharan::core {

    class EntityRegistry {
    private:
        std::vector<EntityID> m_entities;
        std::vector<Transform3DData> m_transforms;
        std::vector<Vec3> m_velocities;
        std::vector<SimulationLOD> m_lods;

    public:
        EntityRegistry() = default;

        void reserve(size_t capacity) {
            m_entities.reserve(capacity);
            m_transforms.reserve(capacity);
            m_velocities.reserve(capacity);
            m_lods.reserve(capacity);
        }

        EntityID create_entity(const Vec3& position, const Vec3& velocity, SimulationLOD lod = SimulationLOD::LOD0_Full) {
            EntityID id = static_cast<EntityID>(m_entities.size());
            m_entities.push_back(id);

            Transform3DData xform{};
            xform.set_position(position);
            m_transforms.push_back(xform);

            m_velocities.push_back(velocity);
            m_lods.push_back(lod);
            return id;
        }

        [[nodiscard]] size_t size() const noexcept { return m_entities.size(); }

        [[nodiscard]] Transform3DData* get_transforms_data() noexcept { return m_transforms.data(); }
        [[nodiscard]] const Transform3DData* get_transforms_data() const noexcept { return m_transforms.data(); }
        [[nodiscard]] const float* get_raw_float_data() const noexcept {
            return reinterpret_cast<const float*>(m_transforms.data());
        }

        [[nodiscard]] Vec3* get_velocities_data() noexcept { return m_velocities.data(); }
        [[nodiscard]] const Vec3* get_velocities_data() const noexcept { return m_velocities.data(); }
        [[nodiscard]] SimulationLOD* get_lods_data() noexcept { return m_lods.data(); }

        [[nodiscard]] Vec3 get_position(EntityID id) const {
            assert(id < m_transforms.size());
            return m_transforms[id].get_position();
        }

        void clear() noexcept {
            m_entities.clear();
            m_transforms.clear();
            m_velocities.clear();
            m_lods.clear();
        }
    };

} // namespace kaharan::core