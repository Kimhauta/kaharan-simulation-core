/**
 * @file common.hpp
 * @brief Core primitive types, memory-aligned data structures, and Simulation LOD definitions.
 *
 * Defines engine-agnostic data structures optimized for CPU cache line utilization
 * and direct binary compatibility with Godot 4's MultiMesh 3x4 transform buffer layout.
 */

#pragma once

#include <cstdint>
#include <cstddef>

 /**
  * @namespace kaharan::core
  * @brief Engine-independent C++20 Data-Oriented Design (DOD) simulation layer.
  */
namespace kaharan::core {

    /**
     * @brief Contiguous zero-based index identifier for active entities in the SoA registry.
     */
    using EntityID = uint32_t;

    /**
     * @brief Sentinel value representing a null or uninitialized entity identifier.
     */
    constexpr EntityID INVALID_ENTITY = 0xFFFFFFFF;

    /**
     * @struct Vec3
     * @brief Lightweight 12-byte 3D floating-point vector aligned to a 4-byte boundary.
     *
     * Packs five vectors cleanly within a single 64-byte x86-64 CPU cache line
     * for linear velocity and position arithmetic.
     */
    struct alignas(4) Vec3 {
        float x{ 0.0f }; ///< X-axis component in world space.
        float y{ 0.0f }; ///< Y-axis component in world space.
        float z{ 0.0f }; ///< Z-axis component in world space.

        constexpr Vec3() = default;

        /**
         * @brief Constructs a 3D vector from explicit Cartesian coordinates.
         *
         * @param p_x Initial X component.
         * @param p_y Initial Y component.
         * @param p_z Initial Z component.
         */
        constexpr Vec3(float p_x, float p_y, float p_z) : x(p_x), y(p_y), z(p_z) {}

        /**
         * @brief Component-wise vector addition.
         *
         * @param other Vector to add.
         * @return Resulting sum vector.
         */
        constexpr Vec3 operator+(const Vec3& other) const {
            return { x + other.x, y + other.y, z + other.z };
        }

        /**
         * @brief Uniform scalar multiplication.
         *
         * @param scalar Scalar multiplier.
         * @return Scaled vector.
         */
        constexpr Vec3 operator*(float scalar) const {
            return { x * scalar, y * scalar, z * scalar };
        }
    };

    /**
     * @struct Transform3DData
     * @brief 48-byte 3x4 row-interleaved transformation matrix matching Godot 4's MultiMesh format.
     *
     * @details Serves as an explicit binary data contract between the pure C++ core and
     * the rendering bridge. Eliminates per-frame $O(N)$ matrix conversion loops by storing
     * transforms directly in the layout expected by GPU instancing buffers:
     * `[Bx.x, By.x, Bz.x, Ox,   Bx.y, By.y, Bz.y, Oy,   Bx.z, By.z, Bz.z, Oz]`.
     */
    struct alignas(16) Transform3DData {
        // Row 0: Basis X (3 floats) + Origin X (1 float)
        float x_axis[3]{ 1.0f, 0.0f, 0.0f };
        float origin_x{ 0.0f };

        // Row 1: Basis Y (3 floats) + Origin Y (1 float)
        float y_axis[3]{ 0.0f, 1.0f, 0.0f };
        float origin_y{ 0.0f };

        // Row 2: Basis Z (3 floats) + Origin Z (1 float)
        float z_axis[3]{ 0.0f, 0.0f, 1.0f };
        float origin_z{ 0.0f };

        /**
         * @brief Extracts the world-space translation component from the 3x4 matrix.
         *
         * @return Current translation vector (origin_x, origin_y, origin_z).
         */
        [[nodiscard]] Vec3 get_position() const noexcept {
            return { origin_x, origin_y, origin_z };
        }

        /**
         * @brief Updates the world-space translation component in-place without altering basis axes.
         *
         * @param pos New world-space position.
         */
        void set_position(const Vec3& pos) noexcept {
            origin_x = pos.x;
            origin_y = pos.y;
            origin_z = pos.z;
        }
    };

    static_assert(sizeof(Transform3DData) == 48, "Transform3DData must be exactly 48 bytes (12 floats).");

    /**
     * @enum SimulationLOD
     * @brief Distance-based update frequency tiers for amortized background simulation.
     */
    enum class SimulationLOD : uint8_t {
        LOD0_Full = 0,      ///< High-priority near zone: updated every simulation tick (1x dt).
        LOD1_Amortized = 1, ///< Mid-range zone: staggered update every 4th tick (4x dt).
        LOD2_Dormant = 2    ///< Far background zone: staggered update every 16th tick (16x dt).
    };

} // namespace kaharan::core