/**
 * @file register_types.hpp
 * @brief GDExtension module lifecycle declarations for Godot Engine 4.
 */

#pragma once

#include <godot_cpp/core/class_db.hpp>

 /**
  * @brief Registers Kaharan GDExtension classes with Godot's ClassDB.
  *
  * @param p_level Current engine initialization stage.
  */
void initialize_kaharan_bridge_module(godot::ModuleInitializationLevel p_level);

/**
 * @brief Cleans up Kaharan GDExtension resources during engine shutdown.
 *
 * @param p_level Current engine deinitialization stage.
 */
void uninitialize_kaharan_bridge_module(godot::ModuleInitializationLevel p_level);