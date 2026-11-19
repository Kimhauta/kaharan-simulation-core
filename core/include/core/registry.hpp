/**
 * @file registry.hpp
 * @brief Structure-of-Arrays (SoA) entity data container for cache-coherent simulation.
 */

#pragma once

#include "common.hpp"
#include <vector>
#include <cassert>

namespace kaharan::core {

    /**
     * @class EntityRegistry
     * @brief Contiguous Structure-of-Arrays (SoA) storage managing all simulated entity attributes.
     *
     * Replaces fragmented heap-allocated object graphs with parallel, pre-allocated
     * std::vector buffers. Parallel indexing guarantees $O(1)$ attribute lookup, zero
     * pointer chasing, and optimal hardware prefetching across hot simulation loops.
     */
    class EntityRegistry {
    private:
        std::vector<EntityID> m_entities;          ///< Contiguous array of active entity identifiers.
        std::vector<Transform3DData> m_transforms; ///< Contiguous 48-byte transform matrices (Zero-Copy GPU buffer).
        std::vector<Vec3> m_velocities;            ///< Contiguous 12-byte linear velocity vectors.
        std::vector<SimulationLOD> m_lods;         ///< Contiguous 1-byte Simulation LOD state flags.

    public:
        /**
         * @brief Constructs an empty EntityRegistry.
         */
        EntityRegistry() = default;

        /**
         * @brief Pre-allocates contiguous heap capacity across all parallel SoA buffers.
         *
         * Prevents mid-simulation memory reallocations and heap fragmentation spikes.
         *
         * @param capacity Number of entities to reserve storage for.
         */
        void reserve(size_t capacity) {
            m_entities.reserve(capacity);
            m_transforms.reserve(capacity);
            m_velocities.reserve(capacity);
            m_lods.reserve(capacity);
        }

        /**
         * @brief Appends a new entity to the end of all parallel SoA arrays.
         *
         * @param position Initial world-space position.
         * @param velocity Initial linear velocity vector.
         * @param lod      Initial Simulation LOD tier (defaults to LOD0_Full).
         * @return Assigned zero-based EntityID.
         */
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

        /**
         * @brief Returns the total number of active entities stored in the registry.
         *
         * @return Current entity count.
         */
        [[nodiscard]] size_t size() const noexcept { return m_entities.size(); }

        /**
         * @brief Returns a mutable raw pointer to the contiguous transform buffer.
         *
         * @return Pointer to the first Transform3DData element.
         */
        [[nodiscard]] Transform3DData* get_transforms_data() noexcept { return m_transforms.data(); }

        /**
         * @brief Returns a read-only raw pointer to the contiguous transform buffer.
         *
         * @return Const pointer to the first Transform3DData element.
         */
        [[nodiscard]] const Transform3DData* get_transforms_data() const noexcept { return m_transforms.data(); }

        /**
         * @brief Exposes the transform buffer as a flat float array for bulk Zero-Copy transfers.
         *
         * @return Const float pointer spanning `size() * 12` floats.
         */
        [[nodiscard]] const float* get_raw_float_data() const noexcept {
            return reinterpret_cast<const float*>(m_transforms.data());
        }

        /**
         * @brief Returns a mutable raw pointer to the contiguous velocity buffer.
         *
         * @return Pointer to the first Vec3 velocity element.
         */
        [[nodiscard]] Vec3* get_velocities_data() noexcept { return m_velocities.data(); }

        /**
         * @brief Returns a read-only raw pointer to the contiguous velocity buffer.
         *
         * @return Const pointer to the first Vec3 velocity element.
         */
        [[nodiscard]] const Vec3* get_velocities_data() const noexcept { return m_velocities.data(); }

        /**
         * @brief Returns a mutable raw pointer to the contiguous Simulation LOD state buffer.
         *
         * @return Pointer to the first SimulationLOD element.
         */
        [[nodiscard]] SimulationLOD* get_lods_data() noexcept { return m_lods.data(); }

        /**
         * @brief Returns a read-only raw pointer to the contiguous Simulation LOD state buffer.
         *
         * @return Const pointer to the first SimulationLOD element.
         */
        [[nodiscard]] const SimulationLOD* get_lods_data() const noexcept { return m_lods.data(); }

        /**
         * @brief Retrieves the world-space position of a single entity by identifier.
         *
         * @param id Valid EntityID (`id < size()`).
         * @return Entity world-space position.
         */
        [[nodiscard]] Vec3 get_position(EntityID id) const {
            assert(id < m_transforms.size());
            return m_transforms[id].get_position();
        }

        /**
         * @brief Clears all active entities while retaining allocated vector capacity.
         */
        void clear() noexcept {
            m_entities.clear();
            m_transforms.clear();
            m_velocities.clear();
            m_lods.clear();
        }
    };

} // namespace kaharan::core