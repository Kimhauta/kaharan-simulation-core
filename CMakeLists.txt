cmake_minimum_required(VERSION 3.22)
project(KaharanSimulationCore VERSION 0.1.0 LANGUAGES CXX C)

# Pakotetaan moderni C++20-standardi
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# MSVC-optimoinnit ja varoitustasot Windowsille
if(MSVC)
    add_compile_options(/W4 /permissive- /utf-8)
endif()

# ==============================================================================
# 1. PURE C++ SIMULATION CORE (The Headless Sanctuary)
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
# Määritetään käytettävä Godot API -versio ENNEN alihakemiston latausta
set(GODOTCPP_API_VERSION "4.6" CACHE STRING "Godot API Version")
set(GODOTCPP_DEFAULT_API_VERSION "4.6" CACHE STRING "Godot Default API Version")

# Lisätään virallinen godot-cpp CMake-alimoduuli
add_subdirectory(extern/godot-cpp)

# Luodaan jaettu kirjasto (.dll / .so) GDExtensionia varten
add_library(simulation_bridge SHARED
    bridge/src/register_types.cpp
)

target_include_directories(simulation_bridge PRIVATE
    bridge/include
)

# Linkitetään C++ -ydin ja Godot-sidokset
target_link_libraries(simulation_bridge PRIVATE
    simulation_core
    godot::cpp
)

# Ohjataan käännetty .dll ja .pdb suoraan Godot-projektin bin-kansioon
set_target_properties(simulation_bridge PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/godot_project/bin"
    OUTPUT_NAME "simulation_bridge"
)