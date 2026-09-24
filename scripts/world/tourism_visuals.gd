class_name TourismVisuals
extends Node3D
## Visuales 3D de su fase (esqueleto). world.gd llama setup(world) al iniciar.

var world: Node3D


func setup(p_world: Node3D) -> void:
	world = p_world
