extends StaticBody3D

const MODEL_TALL: PackedScene = preload("res://assets/models/survival/tree-tall.glb")
const MODEL_WIDE: PackedScene = preload("res://assets/models/survival/tree.glb")

func _ready() -> void:
	# Eliminar el TreeModel estático para poner la variante aleatoria
	var old_model := get_node_or_null("TreeModel")
	if old_model != null:
		old_model.free()

	# 50% de probabilidad de ser el pino ancho y robusto o el pino alto
	var chosen_scene: PackedScene = MODEL_WIDE if randf() < 0.55 else MODEL_TALL
	var model := chosen_scene.instantiate() as Node3D
	model.name = "TreeModel"
	add_child(model)

	# Variación de tamaño bien marcada para que se noten a simple vista:
	var base_scale := 3.8
	var width_var := randf_range(1.0, 2.3)   # Hasta más del doble de ancho
	var height_var := randf_range(0.85, 1.55) # Árboles desde 5.5 m hasta 10 m

	model.scale = Vector3(base_scale * width_var, base_scale * height_var, base_scale * width_var)
