# Kaharan Simulation Core

> High-performance, Data-Oriented C++20 simulation engine extension for Godot 4 via GDExtension.

Developed as an engineering thesis project at **Lapin AMK** (Lapland University of Applied Sciences). The project investigates the performance advantages and integration patterns of Data-Oriented Design (DOD) and Structure-of-Arrays (SoA) memory architectures against traditional Object-Oriented SceneTree paradigms in modern game engines.

---

## Architecture Overview

The system is decoupled into three isolated layers:

+-------------------------------------------------------------------+
|               1. Pure C++ Core (Simulation Core)                  |
|  - Headless & cache-coherent Structure-of-Arrays (SoA) registry   |
|  - Zero engine dependencies, 12-byte aligned math primitives      |
|  - Auto-vectorized linear physics compute loops (__restrict)      |
+-------------------------------------------------------------------+
|
v
+-------------------------------------------------------------------+
|                 2. GDExtension Bridge Layer                       |
|  - Minimal C-ABI entry point binding to Godot 4 ClassDB           |
|  - Direct batch synchronization into Godot MultiMesh buffers      |
|  - High-precision telemetry (std::chrono microsecond timing)      |
+-------------------------------------------------------------------+
|
v
+-------------------------------------------------------------------+
|                   3. Godot 4 Presentation Layer                   |
|  - Hardware-accelerated GPU instancing (MultiMeshInstance3D)      |
|  - 1 draw call for thousands of entities                          |
|  - GDScript telemetry monitoring & visual feedback                |
+-------------------------------------------------------------------+

### Key Architectural Highlights
* **Structure-of-Arrays (SoA) Registry:** Entity data (`positions`, `velocities`, `SimulationLOD`) is held in packed contiguous memory vectors. Updating 5,000 entities reads uninterrupted 12-byte blocks, preventing CPU cache misses and pointer dereferencing overhead.
* **Auto-Vectorization:** SIMD-friendly linear compute loop compiled with MSVC `/O2` and pointer aliasing restrictions (`__restrict`).
* **Direct MultiMesh Synchronization:** Bypasses individual Godot node overhead by writing raw transform matrices directly to GPU instance buffers in C++.

---

## Performance & Micro-Benchmarks

Micro-benchmark executed on a standalone CLI runner (`simulation_benchmark.exe`) across 1,000 tick iterations with identical deterministic seeds:

### Standalone C++ Simulation Tick Performance

| Entity Count | Debug (`/Od`) Frame Avg | Release (`/O2`) Frame Avg | Compiler Speedup | Release Time / Entity |
| :--- | :--- | :--- | :--- | :--- |
| **1,000** | 7.92 µs (0.0079 ms) | **1.56 µs** (0.0016 ms) | **5.06×** | ~1.56 ns |
| **3,000** | 22.69 µs (0.0227 ms) | **4.64 µs** (0.0046 ms) | **4.89×** | ~1.55 ns |
| **5,000** | 40.70 µs (0.0407 ms) | **8.32 µs** (0.0083 ms) | **4.89×** | ~1.66 ns |

### Real-Time In-Engine Performance (Godot 4.6.3 Forward+ Vulkan)
* **Entities:** 5,000 active bouncing agents
* **Target FPS:** 60 FPS (16.67 ms frame budget)
* **C++ Simulation Tick:** ~12–48 µs (0.012–0.048 ms)
* **Frame Budget Utilization:** < 0.3% of total frame budget consumed by simulation compute

---

## Repository Structure

```
kaharan-simulation-core/
├── core/                       # Pure C++ Headless Simulation Core
│   ├── include/core/
│   │   ├── common.hpp          # EntityID, Vec3 (12B), SimulationLOD
│   │   ├── registry.hpp        # Structure-of-Arrays (SoA) Registry
│   │   └── simulation.hpp      # SimulationWorld definition
│   └── src/
│       └── simulation.cpp      # Vectorized tick() and boundary logic
├── bridge/                     # Godot GDExtension Bridge
│   ├── include/bridge/
│   │   └── simulation_bridge.hpp # Godot Node wrapping SimulationWorld
│   └── src/
│       ├── simulation_bridge.cpp # MultiMesh direct sync & telemetry API
│       ├── register_types.hpp
│       └── register_types.cpp    # GDExtension entry point & ClassDB bindings
├── benchmark/                  # Standalone CLI Benchmarking Suite
│   └── src/
│       └── main_bench.cpp      # std::chrono micro-benchmark runner
├── godot_project/              # Godot 4 Project
│   ├── bin/                    # Compiled DLL and .gdextension descriptor
│   ├── test_scene.tscn         # Visualization scene (Camera, MultiMesh)
│   ├── test_scene.gd           # Telemetry logging script
│   └── project.godot
├── extern/
│   └── godot-cpp/              # Godot C++ GDExtension bindings submodule
└── CMakeLists.txt              # Unified root build configuration
```
---

## Build Instructions

### Prerequisites
* **Visual Studio 2022** (with *Desktop development with C++* and *C++ CMake tools for Windows*)
* **CMake 3.22+**
* **Git**
* **Godot Engine 4.x** (tested on Godot v4.6.3 Forward+)

### 1. Clone Repository & Submodules
```PowerShell
git clone --recursive [https://github.com/](https://github.com/)<your-username>/kaharan-simulation-core.git
cd kaharan-simulation-core
(If cloned non-recursively, initialize submodules via git submodule update --init --recursive).
```

### 2. Build via Visual Studio 2022
1. Open the project folder in Visual Studio (File -> Open -> Folder...).
2. Select build configuration: x64-Release (or x64-Debug).
3. Build the entire project: Ctrl + Shift + B (or Build -> Build All).
4. The build pipeline outputs:
    - CLI Runner: out/build/x64-Release/simulation_benchmark.exe
    - GDExtension: godot_project/bin/simulation_bridge.dll

### 3. Run Micro-Benchmarks
Select simulation_benchmark.exe as the startup target in Visual Studio and run (Ctrl + F5), or run directly from terminal:

```PowerShell
.\out\build\x64-Release\simulation_benchmark.exe
```
### 4. Run in Godot Engine
1. Launch Godot Engine 4.
2. Import the godot_project/project.godot file.
3. Open test_scene.tscn and press F6 (Run Current Scene).
4. 5,000 simulated agents will render via MultiMeshInstance3D with real-time microsecond telemetry printed to the output console.

## Example GDScript Usage
```GDScript
extends Node3D

@onready var bridge: SimulationBridge = $SimulationBridge
@onready var mmi: MultiMeshInstance3D = $MultiMeshInstance3D

func _ready() -> void:
    # Spawn 5,000 agents into contiguous C++ SoA buffers
    bridge.spawn_agents(5000)

func _process(_delta: float) -> void:
    # Blit positions directly from C++ memory to GPU instance transform buffer
    bridge.sync_to_multimesh(mmi.multimesh)
    
    # Query performance telemetry
    var tick_time_us = bridge.get_last_tick_microseconds()
    print("C++ simulation tick: %.2f us" % tick_time_us)
```

## Roadmap & Thesis Milestones
[x] Pure C++ Structure-of-Arrays (SoA) entity registry
[x] Vectorized contiguous memory simulation loop
[x] Standalone CLI micro-benchmarking suite
[x] GDExtension bridge binding to Godot 4.6
[x] Single-draw-call GPU visualization via MultiMeshInstance3D
[ ] Direct A/B baseline comparison against traditional Godot Node3D SceneTree hierarchies
[ ] Simulation Level-of-Detail (Simulation LOD) and amortized scheduling
[ ] Empirical thesis evaluation chapter and CSV dataset export