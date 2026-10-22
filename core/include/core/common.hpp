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

    /**
     * @brief 48-byte layout strictly matching Godot 4's MultiMesh 3x4 row-interleaved matrix format.
     * Floats: [Bx, By, Bz, Ox,   Bx, By, Bz, Oy,   Bx, By, Bz, Oz]
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

        [[nodiscard]] Vec3 get_position() const noexcept {
            return { origin_x, origin_y, origin_z };
        }

        void set_position(const Vec3& pos) noexcept {
            origin_x = pos.x;
            origin_y = pos.y;
            origin_z = pos.z;
        }
    };

    static_assert(sizeof(Transform3DData) == 48, "Transform3DData must be exactly 48 bytes (12 floats).");

    enum class SimulationLOD : uint8_t {
        LOD0_Full = 0,
        LOD1_Amortized = 1,
        LOD2_Dormant = 2
    };

} // namespace kaharan::core