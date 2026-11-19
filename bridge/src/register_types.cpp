/**
 * @file register_types.cpp
 * @brief Implementation of GDExtension initialization hooks and C ABI entry point.
 */

#include "register_types.hpp"
#include "bridge/simulation_bridge.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_kaharan_bridge_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    ClassDB::register_class<kaharan::bridge::SimulationBridge>();
}

void uninitialize_kaharan_bridge_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
    /**
     * @brief Dynamic library C ABI entry point invoked by Godot Engine 4 on load.
     *
     * @param p_get_proc_address Function pointer resolver provided by the host engine.
     * @param p_library          Opaque pointer to the loaded GDExtension library instance.
     * @param r_initialization   Initialization configuration struct populated by this binding.
     * @return True if GDExtension initialization succeeded; false otherwise.
     */
    GDExtensionBool GDE_EXPORT kaharan_bridge_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        const GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization* r_initialization
    ) {
        godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

        init_obj.register_initializer(initialize_kaharan_bridge_module);
        init_obj.register_terminator(uninitialize_kaharan_bridge_module);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

        return init_obj.init();
    }
}