#pragma once

#include <cstdint>
#include <cstddef>

namespace kaharan::core {

    using EntityID = uint32_t;
    constexpr EntityID INVALID_ENTITY = 0xFFFFFFFF;

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

    enum class SimulationLOD : uint8_t {
        LOD0_Full = 0,
        LOD1_Amortized = 1,
        LOD2_Dormant = 2
    };

} // namespace kaharan::core