#pragma once

#include <cstdint>
#include <cstddef>

namespace kaharan::core {

    /**
     * @brief Unique numeric identifier for simulation entities.
     * Keeps entities as plain IDs without object overhead.
     */
    using EntityID = uint32_t;
    constexpr EntityID INVALID_ENTITY = 0xFFFFFFFF;

    /**
     * @brief Cache-friendly 12-byte 3D vector.
     * Uses 4-byte alignment to avoid padding and maximize SIMD/cache line density.
     */
    struct alignas(4) Vec3 {
        float x{ 0.0f };
        float y{ 0.0f };
        float z{ 0.0f };

        constexpr Vec3() = default;
        constexpr Vec3(float p_x, float p_y, float p_z) : x(p_x), y(p_y), z(p_z) {}

        constexpr Vec3 operator+(const Vec3& other) const {
            return { x + other.x, y + other.y, z + other.z };
        }

        constexpr Vec3 operator*(float scalar) const {
            return { x * scalar, y * scalar, z * scalar };
        }
    };

    /**
     * @brief Simulation Level of Detail state for amortized updates.
     * LOD0: Full simulation tick every frame (close proximity).
     * LOD1: Amortized simulation (intermediate distance).
     * LOD2: Dormant / macro-simulation (far distance).
     */
    enum class SimulationLOD : uint8_t {
        LOD0_Full = 0,
        LOD1_Amortized = 1,
        LOD2_Dormant = 2
    };

} // namespace kaharan::core