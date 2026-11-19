# Development Log – Kaharan Simulation Core

This log documents the architectural milestones, implementation decisions, methodological refinements, and empirical benchmark findings across the development of **Kaharan Simulation Core** and its Godot 4 GDExtension benchmark suite.

---

## Milestone 1: Project Setup & Three-Tier Architecture (2026-10-17)

### Implementation & Architecture
* Initialized repository structure and Git version control.
* Separated the codebase into three strict unidirectional layers:
  * `core/`: engine-agnostic C++20 simulation library.
  * `bridge/`: Godot 4 GDExtension adapter layer.
  * `godot_project/`: presentation layer, benchmark scenes, and analytics UI.
* Configured root `CMakeLists.txt` targeting the C++20 standard (`CMAKE_CXX_STANDARD 20`).

### Findings & Decisions
* Designed the simulation core to operate completely headless with zero references to Godot headers, ensuring independent CLI verification and long-term engine portability.

---

## Milestone 2: GDExtension Bridge Integration (2026-10-19)

### Implementation & Architecture
* Added `godot-cpp` (v4.6) as a Git submodule (`external/godot-cpp`).
* Implemented the `SimulationBridge` node class and C ABI library entry point (`kaharan_bridge_init`).
* Created the `.gdextension` configuration manifest for Godot 4.

### Findings & Decisions
* **MSVC Runtime Linkage Resolution:** Resolved a Windows linkage mismatch between CMake's default dynamic runtime (`MD_DynamicRelease`) and `godot-cpp`'s static runtime (`MT_StaticRelease`) by enforcing `/MT` across all targets and automating `godot_project/bin/` creation in CMake.
* Verified dynamic loading of `simulation_bridge.dll` and `ClassDB` registration inside Godot 4.

---

## Milestone 3: Structure-of-Arrays (SoA) Core & CLI Micro-Benchmarks (2026-10-20)

### Implementation & Architecture
* Defined a 12-byte memory-aligned `Vec3` type (`alignas(4)`).
* Implemented `EntityRegistry` storing entity IDs, transforms, velocities, and Simulation LOD states in parallel contiguous `std::vector` buffers (SoA).
* Authored a linear `tick()` simulation loop annotated with `__restrict` pointers to enable compiler SIMD auto-vectorization.
* Built a standalone native CLI benchmark executable (`benchmark/src/main_bench.cpp`).

### Findings & Benchmark Results
* Compiler optimizations (`/O2` Release vs. Debug) yielded an approximate **5x** throughput increase.
* Updating 5 000 agents natively averaged **8.3 µs** (~1.66 ns per entity), demonstrating clean linear $O(N)$ scaling.

---

## Milestone 4: MultiMesh Rendering Integration in Godot 4 (2026-10-20)

### Implementation & Architecture
* Embedded `SimulationWorld` inside `SimulationBridge`.
* Implemented initial `sync_to_multimesh()` synchronization transferring SoA coordinates to Godot's `MultiMesh` without per-entity GDScript loops.
* Added symmetrical elastic boundary reflection within the $\pm 50.0\text{ m}$ test arena.

### Findings & Benchmark Results
* Rendered 5 000 active cubes smoothly at 60 FPS in a single GPU Draw Call.
* In-engine C++ tick time measured **10–48 µs** (< 0.3% of a 60 Hz frame budget).

---

## Milestone 5: Zero-Copy 48-Byte Contract, A/B Testbench & Menu UI (2026-10-21 – 2026-10-22)

### Implementation & Architecture
* **Zero-Copy 48-Byte Data Contract (`Transform3DData`):** Aligned the internal transform array (`alignas(16)`, 12 floats / 48 bytes) directly to Godot 4's row-interleaved $3 \times 4$ `MultiMesh` buffer layout, eliminating per-frame $O(N)$ matrix conversion loops.
* **Bulk Memory Copy (`std::memcpy`):** Replaced per-instance `set_instance_transform()` loops with bulk `std::memcpy` into `PackedFloat32Array` and `MultiMesh::set_buffer()`. Added `sync_to_multimesh_range()` for slicing a single contiguous SoA buffer across multiple `MultiMeshInstance3D` visual archetypes.
* **Automated A/B Prototype & Settings:** Built the initial automated A/B benchmark scene (1-Mesh DOD, 5-Mesh DOD, and 5-Mesh OOP across 1k, 5k, and 10k workloads) along with a Main Menu and persistent `GameSettings` Autoload.

### Findings & Benchmark Results
* 10 000-entity `MultiMesh` synchronization dropped to **~300–380 µs**, while C++ physics remained **~25–30 µs**.
* With V-Sync disabled in editor runs, 10k DOD reached **607 FPS** compared to **45 FPS** for the OOP `SceneTree` baseline.

---

## Milestone 6: Modular Benchmark Suite, Saturation Emitter & Session Telemetry (2026-11-10)

### Implementation & Architecture
* **Incremental Spawning (`add_test_agents`):** Added persistent PRNG state (`m_rng`) and incremental buffer growth to `SimulationWorld`, allowing dynamic entity injection without resetting active simulation state.
* **Modular Scene Separation:** Split the testbench into dedicated scenes:
  * `bench_synthetic_render.tscn` and `bench_synthetic_headless.tscn` (12-step fixed A/B matrix).
  * `bench_ramp_up_render.tscn` and `bench_ramp_up_headless.tscn` (continuous 60 FPS saturation emitter).
* **Clamped Accumulator Emitter & Hysteresis Guard:** Implemented a time-based emitter ($R(t) = R_0 + \alpha t$) clamped at 250 spawns/frame to prevent instantiation spikes, coupled with a 5.0-second continuous breach guard at `17.5 ms` (`60 Hz` tolerance threshold).
* **Timestamped Sessions & Analytics Dashboard:** Automated per-run session folders (`run_YYYY-MM-DD_.../`) storing `manifest.json`, `summary.csv`, and per-frame CSV timelines, accompanied by `benchmark_results.gd` featuring custom 2D `_draw()` saturation plots and frame-pacing statistics (`StdDev`, `1% Low FPS`, `0.1% Low FPS`).

### Findings & Methodological Observation (`run_2026-11-10_18-20-52_full_suite`)
* **Geometric Confounding Variable Identified:** In early 5-Mesh runs, default `SphereMesh` and `CapsuleMesh` primitives introduced >300x more triangles than `BoxMesh`, bottlenecking GPU vertex throughput at ~158 FPS (10k) and ~35 000 rendered entities. This discovery motivated constant-polygon standardization in Milestone 7.

---

## Milestone 7: Spatial Simulation LOD, 3-Room Production Tour & Release Verification (2026-11-12)

### Implementation & Architecture
* **Spatial Simulation LOD (`SimulationLOD`) & Steering:** Implemented 3-tier radial distance classification using squared distances (avoiding `sqrt`) and bitwise staggered scheduling inside `SimulationWorld`:
  * `LOD0_Full` (`< 25 m`): full kinematic and trigonometric steering update every tick ($1\times \Delta t$).
  * `LOD1_Amortized` (`25–55 m`): staggered update every 4th tick ($4\times \Delta t$) via `((i + frame_tick) & 3u) == 0u`.
  * `LOD2_Dormant` (`> 55 m`): staggered update every 16th tick ($16\times \Delta t$) via `((i + frame_tick) & 15u) == 0u`.
* **Constant-Polygon Standardization:** Standardized all 5 visual archetypes across every rendered test to uniform $0.55 \times 0.55 \times 0.55\text{ m}$ cubes (`BoxMesh`, 12 triangles/entity) with 5 distinct materials and `SHADOW_CASTING_SETTING_OFF`.
* **3-Room Greybox Level (`greybox_level.gd`) & Programmatic UI:** Built a $100 \times 100\text{ m}$ 3-room and 2-corridor facility with ground-projected LOD rings supporting both interactive FPS sandbox exploration and an automated 4-pass spline Fly-Through (`OOP Base`, `OOP + LOD`, `DOD Base`, `DOD + LOD`). Refactored `main_menu.gd`, `settings_menu.gd`, and `benchmark_hub.gd` into unified code-driven UI layouts with standalone Release output paths (`benchmark_runs/`).
* **OS-Level Process Memory Tracking (`GetProcessMemoryInfo`):** Replaced Godot's debug-only `Performance.MEMORY_STATIC` counter (which returns `0.0` in Release exports and ignores native C++ `std::vector` heap buffers) with Win32 `GetProcessMemoryInfo` (`WorkingSetSize`).

### Findings & Preliminary Release Verification (`run_2026-11-12_22-58-26_full_suite_release`)
* Confirmed constant-geometry parity between `DOD_1Mesh_10k` (`663.63 FPS`) and `DOD_5Mesh_10k` (`668.96 FPS`).
* Verified full standalone Windows Release executable stability across all 5 benchmark stages.

---

## Milestone 8: Code Documentation Polish & Official 2-Hour Soak Release Run (2026-11-19)

### Implementation & Telemetry Refinements
* **Full Codebase Documentation:** Added standardized English Doxygen comments (`@file`, `@brief`, `@param`, `@return`) across `core/`, `bridge/`, and `benchmark/`, and matching GDScript `##` docstrings across all 10 Godot scripts.
* **Telemetry & UI Fixes:**
  * Sampled post-warmup initial process Working Set RAM (`current_step_samples[0]["ram_mb"]`) in summary exports so entity memory footprints remain unskewed by per-frame telemetry buffer growth during high-FPS soak runs.
  * Added `MinLogic_us` and `MaxLogic_us` tracking and deterministic `process_priority = -10` across all Ramp-Up and Synthetic benchmarks.
  * Fixed the warm-up progress bar offset in `bench_synthetic_render.gd` and resolved `STATIC_CALLED_ON_INSTANCE` reload warnings in `game_settings.gd`.

### Official Endurance / Soak Benchmark Results (`run_2026-11-19_15-51-32_full_suite_release`)
Executed in a stabilized standalone Windows 10 Release build (`Godot 4.6.3-stable`, `i7-6700K @ 4.00 GHz`, `GTX 1070 8 GB`, V-Sync OFF) totaling **4 449 730 sampled frames** over **2 hours 16 minutes 43 seconds** (`300 s` per synthetic step, `75 s` per 3-Room Fly-Through pass, `Constant Linear 2 000 / s` Ramp-Up):

* **Synthetic 10 000 Entities (5-Mesh Rendered, 300 s soak):**
  * **DOD:** **704.24 FPS** (`1% Low 600.00`, `StdDev 0.0903 ms`, `Logic 22.19 µs`, `Sync 248.63 µs`, `RAM 322.27 MB`, `20 nodes`).
  * **OOP:** **59.35 FPS** (`1% Low 55.38`, `StdDev 0.5662 ms`, `Logic 7 384.74 µs`, `RAM 375.97 MB`, `10 020 nodes`).
  * **Result:** **332.8x** faster simulation logic, **27.3x** faster total simulation+sync, **11.87x** higher FPS, **6.27x** tighter frame pacing, and **53.70 MB** lower process RAM.
* **Synthetic 10 000 Entities (5-Mesh Headless, 300 s soak):**
  * **DOD:** **960.49 FPS** (`Logic 21.63 µs`, `13 nodes`) vs. **OOP:** **125.38 FPS** (`Logic 6 041.52 µs`, `10 013 nodes`) $\rightarrow$ **279.3x** faster CPU logic and **7.66x** higher FPS.
* **Dynamic Ramp-Up Saturation Points (Constant Linear `2 000 / s`):**
  * **Rendered (5-Mesh):** DOD reached **294 871 entities** (`426.41 MB`) vs. OOP **20 311 entities** (`509.64 MB`) $\rightarrow$ **14.52x** 60 FPS capacity (**-83.23 MB** RAM). Within a realistic **3.0 ms** game subsystem budget (`TotalSim ≤ 3 000 µs`), DOD supported **105 735 entities** vs. OOP **4 449 entities** (**23.77x**).
  * **Headless (Pure CPU):** DOD reached **871 819 entities** (`497.24 MB`) vs. OOP **32 409 entities** (`499.26 MB`) $\rightarrow$ **26.90x** 60 FPS capacity. Within a **3.0 ms** subsystem budget, DOD supported **712 679 entities** vs. OOP **4 742 entities** (**150.29x**).
* **3-Room Fly-Through & Simulation LOD (10 000 Entities with Steering, 75 s/pass):**
  * `OOP Base`: **42.21 FPS** (`Logic 13 556.43 µs`, `StdDev 1.9441 ms`).
  * `OOP + LOD`: **68.16 FPS** (`Logic 9 106.64 µs`, **-32.8%** logic time, **+61.5%** FPS, `StdDev 1.2924 ms`).
  * `DOD Base`: **394.86 FPS** (`Logic 209.78 µs`, `Sync 282.10 µs`, `StdDev 0.0897 ms`, **64.6x** faster logic than OOP Base).
  * `DOD + LOD`: **392.43 FPS** (`Logic 150.94 µs`, `Sync 282.82 µs`, **-28.0%** logic time vs. DOD Base, **89.8x** faster logic and **21.1x** lower jitter than OOP Base).

### Standalone Native C++20 CLI Verification (`kaharan_bench.exe`)
Executed natively against `kaharan_core.lib` with zero Godot dependencies (2 000 timed frames after warm-up):

* **Linear Kinematics (`1k–100k`):** `2.07 µs` (1k), `9.20 µs` (5k), `18.37 µs` (10k), `46.46 µs` (25k), `98.01 µs` (50k), and `214.37 µs` (100k) — scaling linearly at **1.84–2.14 ns/entity** and confirming a negligible **+0.34–3.27 µs** overhead inside Godot's `Headless DOD` bridge (`2.41–21.64 µs`).
* **Steering Kinematics + Simulation LOD:** Reduced tick times by **34.6%** at 10k (`242.21 µs` $\rightarrow$ `158.52 µs`), **34.7%** at 25k (`605.52 µs` $\rightarrow$ `395.39 µs`), and **36.0%** at 100k (`2 310.87 µs` $\rightarrow$ `1 478.03 µs`, staying under half of a 3.0 ms subsystem budget at 100 000 active steering agents).95.39 µs`), and **36.0%** at 100k (`2 310.87 µs` $\rightarrow$ `1 478.03 µs`, staying under half of a 3.0 ms subsystem budget at 100 000 active steering agents). 