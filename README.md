# Kaharan Simulation Core

**High-Performance C++20 Data-Oriented Simulation Engine & Godot 4 GDExtension Benchmark Suite**

Developed as a Bachelor of Engineering Thesis at **Lapland University of Applied Sciences (Lapin AMK)**.  
Author: **Kimmo Hautalahti** (2026)

## Overview

**Kaharan Simulation Core** is an engine-agnostic C++20 simulation framework designed around **Data-Oriented Design (DOD)** principles and **Structure-of-Arrays (SoA)** memory layouts. It integrates into **Godot Engine 4.6** via **GDExtension** (`SimulationBridge`) and synchronizes tens of thousands of active 3D agents directly to the Vulkan rendering pipeline using a **Zero-Copy `MultiMesh`** buffer architecture.

The repository includes an automated 5-stage empirical benchmark suite comparing the C++20 DOD architecture against Godot's native Object-Oriented Programming (OOP) `SceneTree` and `GDScript` workflow.

## Core Architectural Features

* **Engine-Agnostic C++20 Core:** Pure C++20 simulation library (`kaharan_core`) with zero dependencies on Godot headers, compiling both into a standalone CLI micro-benchmark executable and a Godot GDExtension dynamic library.
* **Structure-of-Arrays (SoA) Registry:** Contiguous, pre-allocated memory buffers for entity transforms, velocities, and Simulation LOD states maximizing CPU L1/L2 cache line utilization and hardware prefetching.
* **Zero-Copy MultiMesh Synchronization:** Each entity's spatial state is stored in an aligned 48-byte `Transform3DData` matrix matching Godot 4's row-interleaved $3 \times 4$ `MultiMesh` buffer contract, enabling single-pass `std::memcpy` transfers and memory slicing (`sync_to_multimesh_range`) across multiple visual archetypes.
* **Spatial Simulation LOD (Level of Detail):** Distance-based 3-tier update frequency scaling (`LOD0_Full` every frame, `LOD1_Amortized` every 4th frame, `LOD2_Dormant` every 16th frame) with staggered index modulo scheduling (`(i + tick) & mask`) to eliminate frame-time spikes.
* **Constant-Geometry Methodology:** All single-mesh and multi-mesh tests utilize uniform 12-triangle cube primitives across 5 distinct materials, isolating memory layout, draw-call batching, and CPU simulation throughput from polygon count variance.

## Automated 5-Stage Benchmark Suite

1. **Synthetic A/B Matrix (Rendered):** Evaluates 1 000, 5 000, and 10 000 entities across 4 variants (DOD 1-Mesh, DOD 5-Mesh, OOP 1-Mesh, OOP 5-Mesh) with full Vulkan rendering.
2. **Synthetic A/B Matrix (Headless):** Disables rendering and GPU synchronization to isolate pure CPU simulation loop and memory traversal performance.
3. **Dynamic Emitter Ramp-Up (Rendered):** Continuously spawns heterogeneous agents until frame time exceeds the 60 Hz threshold (17.5 ms) for 5.0 consecutive seconds.
4. **Dynamic Emitter Ramp-Up (Headless):** Pushes pure CPU simulation until the 60 Hz logic budget saturates.
5. **3-Room Production Fly-Through & Sandbox:** A $100 \times 100\text{ m}$ architectural greybox level featuring 3 rooms and 2 connecting corridors. Operates both as an interactive free-roam sandbox and a 4-pass automated camera tour comparing OOP Base, OOP + LOD, DOD Base, and DOD + LOD.

## Empirical Benchmark Results (Release Build)

Measured on **Intel Core i7-6700K @ 4.00 GHz**, **NVIDIA GeForce GTX 1070 (8 GB)**, **Windows 10 (10.0.19045)**, **Godot 4.6.3-stable Release** (V-Sync OFF).

### 1. Synthetic & 3-Room Fly-Through (10 000 Entities)

| Test Scenario | Avg FPS | 1% Low FPS | Sim Logic (µs) | Scene Nodes |
| :--- | :---: | :---: | :---: | :---: |
| **Synthetic DOD 5-Mesh (Rendered)** | 668.96 | 600.00 | 23.92 | 20 |
| **Synthetic OOP 5-Mesh (Rendered)** | 54.92 | 43.43 | 8 207.26 | 10 020 |
| **Synthetic DOD 5-Mesh (Headless)** | 886.58 | 720.00 | 27.14 | 13 |
| **Synthetic OOP 5-Mesh (Headless)** | 106.67 | 100.00 | 7 119.63 | 10 013 |
| **3-Room Fly-Through OOP Base** | 40.44 | 36.77 | 14 434.18 | 10 056 |
| **3-Room Fly-Through OOP + LOD** | 65.68 | 59.21 | 9 515.93 | 10 056 |
| **3-Room Fly-Through DOD Base** | 396.72 | 369.00 | 212.39 | 56 |
| **3-Room Fly-Through DOD + LOD** | 394.20 | 369.41 | 153.31 | 56 |

At 10 000 rendered entities, the C++20 SoA simulation loop executes **343.1x faster** than GDScript (`23.92 µs` vs. `8 207.26 µs`), delivering a **12.2x higher frame rate** while reducing `SceneTree` node count from 10 020 to 20 and saving over 52 MB of process RAM. In the 3-room Fly-Through with trigonometric steering kinematics, Simulation LOD reduces C++ logic execution time by **27.8%** (`212.39 µs` to `153.31 µs`) and OOP logic time by **34.1%** (`14.43 ms` to `9.52 ms`).

### 2. Dynamic Ramp-Up 60 FPS Saturation Breaking Points

| Benchmark Mode | DOD Max Entities | OOP Max Entities | Capacity Multiplier | DOD Process RAM |
| :--- | :---: | :---: | :---: | :---: |
| **Rendered (5-Mesh)** | 326 667 | 17 391 | **18.8x** | 408.70 MB |
| **Headless (Pure CPU)** | 968 903 | 30 379 | **31.9x** | 417.12 MB |

## Build Instructions

### Prerequisites
* **Visual Studio 2022** (Desktop development with C++ workload, MSVC v143, CMake tools)
* **Godot Engine 4.6+** (Standard 64-bit edition)
* **Git** (with initialized `external/godot-cpp` submodule)

### Compiling the C++20 Core & GDExtension Bridge
1. Clone the repository with submodules:
   ```bash
   git clone --recurse-submodules [https://github.com/Kimhauta/kaharan-simulation-core.git](https://github.com/Kimhauta/kaharan-simulation-core.git)
2. Open the root folder in Visual Studio 2022 as a CMake project.
3. Select the x64-Release configuration and build the solution (Ctrl + Shift + B).
	- Builds kaharan_core.lib (static simulation core)
	- Builds kaharan_bench.exe (standalone native CLI benchmark)
	- Builds and copies simulation_bridge.dll directly into godot_project/bin/
### Running & Exporting the Godot Benchmark Suite
1. Open godot_project/project.godot in Godot 4.6.
2. Press F5 to launch the main menu, or export a standalone Windows Desktop (x86_64) executable with Export With Debug disabled.
3. All benchmark runs automatically generate timestamped session folders under benchmark_runs/ (or res://user_files/runs/ in the editor) containing manifest.json, summary.csv, and per-frame raw telemetry (raw_frames/).