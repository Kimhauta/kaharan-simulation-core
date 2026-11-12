#include <iostream>
#include <iomanip>
#include <chrono>
#include <vector>
#include "core/simulation.hpp"

void run_benchmark_for_count(size_t entity_count, bool steering, bool lod_enabled, int test_frames = 2000) {
    kaharan::core::SimulationWorld world;
    constexpr float DELTA = 0.0166667f;

    world.set_steering_enabled(steering);
    world.set_lod_enabled(lod_enabled);
    world.set_observer_position({ 0.0f, 4.5f, 0.0f });
    world.set_lod_thresholds(25.0f, 55.0f);
    world.spawn_test_agents(entity_count);

    // Lyhyt lämmittely
    for (int w = 0; w < 100; ++w) {
        world.tick(DELTA);
    }

    auto start_time = std::chrono::high_resolution_clock::now();
    for (int frame = 0; frame < test_frames; ++frame) {
        world.tick(DELTA);
    }
    auto end_time = std::chrono::high_resolution_clock::now();

    std::chrono::duration<double, std::micro> total_us = end_time - start_time;
    double avg_us = total_us.count() / static_cast<double>(test_frames);
    double avg_ms = avg_us / 1000.0;
    double theoretical_fps = 1000.0 / avg_ms;

    std::cout << std::left << std::setw(10) << entity_count
        << " | Steer: " << (steering ? "ON " : "OFF")
        << " | LOD: " << (lod_enabled ? "ON " : "OFF")
        << " | Avg tick: " << std::fixed << std::setprecision(2) << std::setw(8) << avg_us << " us"
        << " (" << std::setprecision(4) << avg_ms << " ms)"
        << " | Max CPU Hz: " << std::setprecision(0) << theoretical_fps << " FPS"
        << std::endl;
}

int main() {
    std::cout << "====================================================================================" << std::endl;
    std::cout << " Kaharan Simulation Core - Standalone Native C++20 Micro-Benchmark (Zero Godot)     " << std::endl;
    std::cout << "====================================================================================" << std::endl;

    const std::vector<size_t> test_loads = { 1000, 5000, 10000, 25000, 50000, 100000 };

    std::cout << "\n--- 1. Linear Kinematics (Matches Synthetic & Ramp-Up Core) ---" << std::endl;
    for (size_t count : test_loads) {
        run_benchmark_for_count(count, false, false, 2000);
    }

    std::cout << "\n--- 2. Steering Kinematics + Simulation LOD (Matches 3-Room Fly-Through) ---" << std::endl;
    for (size_t count : { size_t(10000), size_t(25000), size_t(100000) }) {
        run_benchmark_for_count(count, true, false, 2000);
        run_benchmark_for_count(count, true, true, 2000);
    }

    std::cout << "====================================================================================" << std::endl;
    return 0;
}