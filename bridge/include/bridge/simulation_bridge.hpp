/**
 * @file simulation_bridge.hpp
 * @brief Godot 4 GDExtension adapter node bridging the C++20 SimulationWorld to the engine.
 */

#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include "core/simulation.hpp"

 /**
  * @namespace kaharan::bridge
  * @brief Adapter layer isolating Godot 4 API dependencies from the pure C++20 simulation core.
  */
namespace kaharan::bridge {

    /**
     * @class SimulationBridge
     * @brief Godot Node wrapping kaharan::core::SimulationWorld for SceneTree integration.
     *
     * Implements a Strangler Fig adapter boundary: advances the engine-agnostic
     * Structure-of-Arrays (SoA) simulation each frame, exposes Simulation LOD and
     * telemetry controls to GDScript, and performs Zero-Copy bulk transfers of
     * 48-byte transform matrices into Godot MultiMesh rendering buffers.
     */
    class SimulationBridge : public godot::Node {
        GDCLASS(SimulationBridge, godot::Node);

    private:
        kaharan::core::SimulationWorld m_world; ///< Owned engine-independent simulation world instance.
        double m_last_tick_us{ 0.0 };           ///< Duration of the most recent simulation tick in microseconds.

    protected:
        /**
         * @brief Exposes methods to Godot's ClassDB for GDScript and editor access.
         */
        static void _bind_methods();

    public:
        /**
         * @brief Constructs a new SimulationBridge node.
         */
        SimulationBridge();

        /**
         * @brief Destroys the SimulationBridge node and releases owned simulation memory.
         */
        ~SimulationBridge();

        /**
         * @brief Godot lifecycle callback invoked when the node enters the SceneTree.
         */
        void _ready() override;

        /**
         * @brief Godot per-frame update callback advancing the C++ simulation world.
         *
         * @param delta Elapsed frame time in seconds.
         */
        void _process(double delta) override;

        // --- Entity Management & Telemetry ---

        /**
         * @brief Resets the simulation world and deterministically spawns new agents.
         *
         * @param p_count Number of agents to spawn (ignored if <= 0).
         */
        void spawn_agents(int p_count);

        /**
         * @brief Incrementally appends new agents to the active simulation without resetting state.
         *
         * @param p_count Number of additional agents to append (ignored if <= 0).
         */
        void add_agents(int p_count);

        /**
         * @brief Returns the total number of active agents in the simulation registry.
         *
         * @return Active entity count.
         */
        [[nodiscard]] int get_agent_count() const;

        /**
         * @brief Queries the world-space position of a single agent by index.
         *
         * @param p_index Zero-based agent index.
         * @return Agent position as a Godot Vector3, or (0, 0, 0) if out of bounds.
         */
        [[nodiscard]] godot::Vector3 get_agent_position(int p_index) const;

        /**
         * @brief Returns the execution duration of the last C++ simulation tick.
         *
         * @return Elapsed tick time in microseconds.
         */
        [[nodiscard]] double get_last_tick_microseconds() const;

        /**
         * @brief Queries the operating system for the current process physical memory usage.
         *
         * Uses Win32 GetProcessMemoryInfo (WorkingSetSize) on Windows so both Godot engine
         * allocations and native C++ std::vector buffers are accounted for in Release builds.
         *
         * @return Process Working Set size in megabytes (MB), or 0.0 on unsupported platforms.
         */
        [[nodiscard]] double get_process_memory_mb() const;

        // --- Simulation LOD & Kinematics Configuration ---

        /**
         * @brief Enables or disables distance-based 3-tier Simulation LOD scheduling.
         *
         * @param p_enabled True to enable amortized LOD tiers; false for full-rate updates.
         */
        void set_lod_enabled(bool p_enabled);

        /**
         * @brief Checks whether Simulation LOD is currently active.
         *
         * @return True if Simulation LOD is enabled.
         */
        [[nodiscard]] bool is_lod_enabled() const;

        /**
         * @brief Updates the observer (camera/player) world position used for LOD distance checks.
         *
         * @param p_pos Observer coordinates in world space.
         */
        void set_observer_position(const godot::Vector3& p_pos);

        /**
         * @brief Configures the radial distance thresholds separating LOD0, LOD1, and LOD2 zones.
         *
         * @param p_lod1_dist Radius in meters transitioning from LOD0_Full to LOD1_Amortized.
         * @param p_lod2_dist Radius in meters transitioning from LOD1_Amortized to LOD2_Dormant.
         */
        void set_lod_thresholds(float p_lod1_dist, float p_lod2_dist);

        /**
         * @brief Returns the entity distribution across the three Simulation LOD tiers.
         *
         * @return 3-element PackedInt32Array containing [LOD0_Full, LOD1_Amortized, LOD2_Dormant] counts.
         */
        [[nodiscard]] godot::PackedInt32Array get_lod_counts() const;

        /**
         * @brief Enables or disables trigonometric heading oscillation during agent updates.
         *
         * @param p_enabled True to apply per-agent steering turns; false for linear motion.
         */
        void set_steering_enabled(bool p_enabled);

        // --- Zero-Copy MultiMesh Synchronization ---

        /**
         * @brief Copies all agent transform matrices into a single Godot MultiMesh buffer.
         *
         * Performs a bulk std::memcpy of the contiguous 48-byte Transform3DData array into
         * a PackedFloat32Array and uploads it to the GPU via MultiMesh::set_buffer().
         *
         * @param p_multimesh Target Godot MultiMesh resource reference.
         */
        void sync_to_multimesh(godot::Ref<godot::MultiMesh> p_multimesh);

        /**
         * @brief Copies a contiguous sub-range of agent transforms into a Godot MultiMesh buffer.
         *
         * Enables splitting a unified simulation population across multiple MultiMeshInstance3D
         * archetypes without partitioning the underlying C++ SoA memory buffers.
         *
         * @param p_multimesh   Target Godot MultiMesh resource reference.
         * @param p_start_index Starting entity index within the SoA transform array.
         * @param p_count       Number of consecutive entities to copy.
         */
        void sync_to_multimesh_range(godot::Ref<godot::MultiMesh> p_multimesh, int p_start_index, int p_count);

        /**
         * @brief Returns the version identifier string of the GDExtension module.
         *
         * @return Human-readable version and architecture description.
         */
        [[nodiscard]] godot::String get_bridge_version() const;
    };

} // namespace kaharan::bridge