extends StaticBody3D
## Árbol del reparto (raíz de Tree.tscn). Al entrar en juego reemplaza el
## nodo TreeModel de la escena por uno de los dos modelos de abajo, con una
## escala al azar. El TreeModel de Tree.tscn es solo la vista previa del
## editor: editarlo no cambia el juego; estos exports sí.
## Saca tres números del RNG global de la partida, siempre en este orden
## (modelo, ancho, alto): no agregues ni reordenes sorteos.

@export_group("Modelos")
## Pino ancho y robusto.
@export var wide_model: PackedScene = preload("res://assets/models/survival/tree.glb")
## Pino alto.
@export var tall_model: PackedScene = preload("res://assets/models/survival/tree-tall.glb")
## Probabilidad (0-1) de que salga el pino ancho; si no, el alto.
@export_range(0.0, 1.0) var wide_chance: float = 0.55

@export_group("Escala")
## Escala base del modelo, antes de la variación al azar.
@export var base_scale: float = 3.8
## Rango del multiplicador de ancho (X y Z) sobre base_scale: hasta más del
## doble de ancho.
@export var width_scale_min: float = 1.0
@export var width_scale_max: float = 2.3
## Rango del multiplicador de alto (Y) sobre base_scale: árboles de ~5.5 m
## a ~10 m.
@export var height_scale_min: float = 0.85
@export var height_scale_max: float = 1.55


func _ready() -> void:
	# Quita la vista previa de la escena para poner la variante al azar.
	var preview := get_node_or_null("TreeModel")
	if preview != null:
		preview.free()
	var chosen_scene: PackedScene = wide_model if randf() < wide_chance else tall_model
	var model := chosen_scene.instantiate() as Node3D
	model.name = "TreeModel"
	add_child(model)
	var width_var := randf_range(width_scale_min, width_scale_max)
	var height_var := randf_range(height_scale_min, height_scale_max)
	model.scale = Vector3(base_scale * width_var, base_scale * height_var, base_scale * width_var)
