# Kaharan Simulation Core

**High-Performance C++20 Data-Oriented Simulation Engine & Godot 4 GDExtension Benchmark Suite**

Developed as a Bachelor's Thesis in Business Information Technology at **Lapland University of Applied Sciences (Lapin AMK)**.  
Author: **Kimmo Hautalahti** (2026)

## Overview

**Kaharan Simulation Core** is an engine-agnostic C++20 simulation framework designed around **Data-Oriented Design (DOD)** principles and **Structure-of-Arrays (SoA)** memory layouts. It integrates into **Godot Engine 4.6** via **GDExtension** (`SimulationBridge`) and synchronizes tens of thousands of active 3D agents directly to the Vulkan rendering pipeline using a **Zero-Copy `MultiMesh`** buffer architecture.

The repository includes an automated 5-stage empirical benchmark suite comparing the C++20 DOD architecture against Godot's native Object-Oriented Programming (OOP) `SceneTree` and `GDScript` workflow.

## Core Architectural Features

* **Engine-Agnostic C++20 Core:** Pure C++20 simulation library (`kaharan_core`) with zero dependencies on Godot headers, compiling both into a standalone CLI micro-benchmark executable and a Godot GDExtension dynamic library.
* **Structure-of-Arrays (SoA) Registry:** Contiguous, pre-allocated memory buffers for entity IDs, transforms, velocities, and Simulation LOD states maximizing CPU L1/L2 cache line utilization and hardware prefetching.
* **Zero-Copy MultiMesh Synchronization:** Each entity's spatial state is stored in an aligned 48-byte `Transform3DData` matrix matching Godot 4's row-interleaved $3 \times 4$ `MultiMesh` buffer contract, enabling single-pass `std::memcpy` transfers and memory slicing (`sync_to_multimesh_range`) across multiple visual archetypes.
* **Spatial Simulation LOD (Level of Detail):** Distance-based 3-tier update frequency scaling (`LOD0_Full` every frame, `LOD1_Amortized` every 4th frame, `LOD2_Dormant` every 16th frame) with staggered index modulo scheduling (`(i + tick) & mask`) to eliminate frame-time spikes.
* **Constant-Geometry Methodology:** All single-mesh and multi-mesh tests utilize uniform 12-triangle cube primitives (`BoxMesh`) across 5 distinct materials with per-agent shadows disabled, isolating memory layout, draw-call batching, and CPU simulation throughput from polygon count variance.

## Automated 5-Stage Benchmark Suite

1. **Synthetic A/B Matrix (Rendered):** Evaluates 1 000, 5 000, and 10 000 entities across 4 variants (`DOD 1-Mesh`, `DOD 5-Mesh`, `OOP 1-Mesh`, `OOP 5-Mesh`) with full Vulkan rendering.
2. **Synthetic A/B Matrix (Headless):** Disables rendering and GPU synchronization to isolate pure CPU simulation loop and memory traversal performance.
3. **Dynamic Emitter Ramp-Up (Rendered):** Continuously spawns heterogeneous agents at a constant linear rate (`2 000 / s`) until frame time exceeds the 60 Hz threshold (`17.5 ms`) for 5.0 consecutive seconds.
4. **Dynamic Emitter Ramp-Up (Headless):** Pushes pure CPU simulation linearly (`2 000 / s`) until the 60 Hz logic budget saturates.
5. **3-Room Production Fly-Through & Sandbox:** A $100 \times 100\text{ m}$ architectural greybox level featuring 3 rooms and 2 connecting corridors. Operates both as an interactive free-roam sandbox and a 4-pass automated camera tour comparing `OOP Base`, `OOP + LOD`, `DOD Base`, and `DOD + LOD`.

## Empirical Benchmark Results (Official Release Soak Run)

Measured in a controlled standalone Release build (`run_2026-11-19_15-51-32_full_suite_release`, **4 449 730 frames sampled** over **2 h 16 min 43 s**, **300 s** per synthetic step, **75 s** per Fly-Through pass) on **Intel Core i7-6700K @ 4.00 GHz**, **NVIDIA GeForce GTX 1070 (8 GB)**, **Windows 10 (10.0.19045)**, **Godot 4.6.3-stable Release** (V-Sync OFF).

### 1. Synthetic & 3-Room Fly-Through (10 000 Entities)

| Test Scenario | Avg FPS | 1% Low FPS | StdDev (ms) | Sim Logic (µs) | GPU Sync (µs) | Process RAM (MB) | Scene Nodes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Synthetic DOD 1-Mesh (Rendered)** | 715.40 | 660.00 | 0.0873 | 22.09 | 237.29 | 320.64 | 20 |
| **Synthetic OOP 1-Mesh (Rendered)** | 60.43 | 55.38 | 0.5654 | 7 442.14 | 0.00 | 373.89 | 10 020 |
| **Synthetic DOD 5-Mesh (Rendered)** | 704.24 | 600.00 | 0.0903 | 22.19 | 248.63 | 322.27 | 20 |
| **Synthetic OOP 5-Mesh (Rendered)** | 59.35 | 55.38 | 0.5662 | 7 384.74 | 0.00 | 375.97 | 10 020 |
| **Synthetic DOD 5-Mesh (Headless)** | 960.49 | 798.08 | 0.1641 | 21.63 | 0.00 | 338.61 | 13 |
| **Synthetic OOP 5-Mesh (Headless)** | 125.38 | 110.00 | 1.0567 | 6 041.52 | 0.00 | 464.73 | 10 013 |
| **3-Room Fly-Through OOP Base** | 42.21 | 38.18 | 1.9441 | 13 556.43 | 0.00 | 453.10 | 10 056 |
| **3-Room Fly-Through OOP + LOD** | 68.16 | 60.00 | 1.2924 | 9 106.64 | 0.00 | 403.60 | 10 056 |
| **3-Room Fly-Through DOD Base** | 394.86 | 361.93 | 0.0897 | 209.78 | 282.10 | 410.74 | 56 |
| **3-Room Fly-Through DOD + LOD** | 392.43 | 360.00 | 0.0923 | 150.94 | 282.82 | 389.73 | 56 |

At 10 000 rendered 5-mesh entities, the C++20 SoA simulation loop executes **332.8x faster** than GDScript (`22.19 µs` vs. `7 384.74 µs`), delivering an **11.87x higher frame rate** (`704.24` vs. `59.35 FPS`) and **6.27x tighter frame pacing** (`0.090 ms` vs. `0.566 ms`) while reducing `SceneTree` node count from 10 020 to 20 and saving **53.70 MB** of process RAM. In the 3-room Fly-Through with trigonometric steering kinematics, Simulation LOD reduces C++ logic execution time by **28.0%** (`209.78 µs` to `150.94 µs`, **89.8x** faster than OOP Base) and OOP logic time by **32.8%** (`13.56 ms` to `9.11 ms`).

### 2. Dynamic Ramp-Up Breaking Points (Constant Linear `2 000 / s`)

| Benchmark Mode | DOD Max (60 FPS) | OOP Max (60 FPS) | 60 FPS Multiplier | DOD ≤ 3.0 ms Budget | OOP ≤ 3.0 ms Budget | 3.0 ms Multiplier |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Rendered (5-Mesh)** | 294 871 | 20 311 | **14.52x** | 105 735 | 4 449 | **23.77x** |
| **Headless (Pure CPU)** | 871 819 | 32 409 | **26.90x** | 712 679 | 4 742 | **150.29x** |

### 3. Standalone Native C++20 CLI Micro-Benchmark (Zero Godot)

Executed via `simulation_benchmark.exe` (`x64-Release`, 2 000 timed frames after 100-frame warm-up) directly against `simulation_core.lib` with zero Godot Engine or GDExtension dependencies:

| Entity Count | Kinematics Mode | Simulation LOD | Avg Tick (µs) | Cost / Entity (ns) | Max CPU Throughput | LOD Savings |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| **1 000** | Linear | OFF | 2.07 | 2.07 ns | 482 567 FPS | — |
| **5 000** | Linear | OFF | 9.20 | 1.84 ns | 108 748 FPS | — |
| **10 000** | Linear | OFF | 18.37 | 1.84 ns | 54 439 FPS | — |
| **25 000** | Linear | OFF | 46.46 | 1.86 ns | 21 523 FPS | — |
| **50 000** | Linear | OFF | 98.01 | 1.96 ns | 10 203 FPS | — |
| **100 000** | Linear | OFF | 214.37 | 2.14 ns | 4 665 FPS | — |
| **10 000** | Steering | OFF | 242.21 | 24.22 ns | 4 129 FPS | — |
| **10 000** | Steering | **ON** | **158.52** | **15.85 ns** | **6 308 FPS** | **-34.6% (1.53x)** |
| **25 000** | Steering | OFF | 605.52 | 24.22 ns | 1 651 FPS | — |
| **25 000** | Steering | **ON** | **395.39** | **15.82 ns** | **2 529 FPS** | **-34.7% (1.53x)** |
| **100 000** | Steering | OFF | 2 310.87 | 23.11 ns | 433 FPS | — |
| **100 000** | Steering | **ON** | **1 478.03** | **14.78 ns** | **677 FPS** | **-36.0% (1.56x)** |

Comparing native CLI execution (`18.37 µs` at 10k linear entities) against Godot `Headless DOD` (`21.63–21.64 µs`) confirms a minimal **~3.3 µs** integration/cache-coherency overhead across the GDExtension boundary.

## Build Instructions

### Prerequisites
* **Visual Studio 2022** (Desktop development with C++ workload, MSVC v143, CMake tools)
* **Godot Engine 4.6+** (Standard 64-bit edition)
* **Git** (with initialized `external/godot-cpp` submodule)

## Build Instructions

### Prerequisites
* **Visual Studio 2022** (Desktop development with C++ workload, MSVC v143, CMake tools)
* **Godot Engine 4.6+** (Standard 64-bit edition)
* **Git** (with initialized `extern/godot-cpp` submodule)

### Compiling the C++20 Core & GDExtension Bridge
1. Clone the repository with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/Kimhauta/Kaharan-simulation-core.git
   ```
2. Open the root folder in **Visual Studio 2022** as a CMake project.
3. Select the **`x64-Release`** configuration and build the solution (`Ctrl + Shift + B`):
   * Builds `simulation_core.lib` (static simulation core)
   * Builds `simulation_benchmark.exe` (standalone native CLI benchmark)
   * Builds and copies `simulation_bridge.dll` directly into `godot_project/bin/`

### Running & Exporting the Godot Benchmark Suite
1. Open `godot_project/project.godot` in Godot 4.6.
2. Press **F5** to launch the main menu, or export a standalone **Windows Desktop (`x86_64`)** executable with **Export With Debug** disabled.
3. All benchmark runs automatically generate timestamped session folders under `benchmark_runs/` (or `res://user_files/runs/` in the editor) containing `manifest.json`, `summary.csv`, and per-frame raw telemetry (`raw_frames/`).
