#include <iostream>
#include <chrono>
#include <vector>
#include "core/simulation.hpp"

void run_benchmark_for_count(size_t entity_count, int test_frames = 1000) {
    kaharan::core::SimulationWorld world;
    constexpr float DELTA = 0.01666f;

    world.spawn_test_agents(entity_count);

    auto start_time = std::chrono::high_resolution_clock::now();

    for (int frame = 0; frame < test_frames; ++frame) {
        world.tick(DELTA);
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> total_duration = end_time - start_time;

    double avg_frame_ms = total_duration.count() / test_frames;
    double avg_frame_us = avg_frame_ms * 1000.0;

    std::cout << "Entities: " << entity_count
        << " | Total: " << total_duration.count() << " ms"
        << " | Avg tick: " << avg_frame_ms << " ms (" << avg_frame_us << " us)"
        << std::endl;
}

int main() {
    std::cout << "======================================================" << std::endl;
    std::cout << " Kaharan Simulation Core - Micro-Benchmark Runner     " << std::endl;
    std::cout << "======================================================" << std::endl;

    const std::vector<size_t> test_loads = { 1000, 3000, 5000 };

    for (size_t count : test_loads) {
        run_benchmark_for_count(count, 1000);
    }

    std::cout << "======================================================" << std::endl;
    return 0;
}