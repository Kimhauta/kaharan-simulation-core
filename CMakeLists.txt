cmake_minimum_required(VERSION 3.22)
project(KaharanSimulationCore VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
    add_compile_options(/W4 /permissive- /utf-8)
endif()

# ==============================================================================
# 1. PURE C++ SIMULATION CORE (Headless, nolla Godot-riippuvuutta)
# ==============================================================================
add_library(simulation_core STATIC
    core/src/simulation.cpp
)

target_include_directories(simulation_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/core/include>
    $<INSTALL_INTERFACE:include>
)

# ==============================================================================
# 2. STANDALONE BENCHMARK RUNNER (CLI A/B-testit)
# ==============================================================================
add_executable(simulation_benchmark
    benchmark/src/main_bench.cpp
)

target_link_libraries(simulation_benchmark PRIVATE
    simulation_core
)

# ==============================================================================
# 3. GODOT-CPP SUBMODULE & GDEXTENSION BRIDGE
# ==============================================================================
set(GODOTCPP_API_VERSION "4.6" CACHE STRING "Godot API Version")
set(GODOTCPP_DEFAULT_API_VERSION "4.6" CACHE STRING "Godot Default API Version")

add_subdirectory(extern/godot-cpp)

# Siltaan kuuluvat VAIN register_types.cpp ja simulation_bridge.cpp
add_library(simulation_bridge SHARED
    bridge/src/register_types.cpp
    bridge/src/simulation_bridge.cpp
)

target_include_directories(simulation_bridge PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge/include
    ${CMAKE_CURRENT_SOURCE_DIR}/bridge/src
)

target_link_libraries(simulation_bridge PRIVATE
    simulation_core
    godot::cpp
)

# Varmistetaan, että tulostuskansio on olemassa MSVC-linkittäjää varten
file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin")

set_target_properties(simulation_bridge PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    OUTPUT_NAME "simulation_bridge"
)