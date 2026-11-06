extends StaticBody3D
## Árbol del reparto: al entrar en juego reemplaza el TreeModel de Tree.tscn
## por uno de dos pinos al azar, con una escala aleatoria. Saca números del
## RNG global de la partida: no cambies cuántos ni en qué orden.

const MODEL_TALL: PackedScene = preload("res://assets/models/survival/tree-tall.glb")
const MODEL_WIDE: PackedScene = preload("res://assets/models/survival/tree.glb")

func _ready() -> void:
	# Quita el TreeModel de la escena para poner la variante aleatoria.
	var old_model := get_node_or_null("TreeModel")
	if old_model != null:
		old_model.free()

	# 55% de probabilidad de pino ancho y robusto; si no, pino alto.
	var chosen_scene: PackedScene = MODEL_WIDE if randf() < 0.55 else MODEL_TALL
	var model := chosen_scene.instantiate() as Node3D
	model.name = "TreeModel"
	add_child(model)

	# Variación de tamaño bien marcada para que se note a simple vista.
	var base_scale := 3.8
	var width_var := randf_range(1.0, 2.3)   # hasta más del doble de ancho
	var height_var := randf_range(0.85, 1.55) # árboles de ~5.5 m a ~10 m

	model.scale = Vector3(base_scale * width_var, base_scale * height_var, base_scale * width_var)
