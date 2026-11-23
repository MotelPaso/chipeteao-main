class_name GroundedProps
extends Node3D
## Apoya sobre el suelo a cada hijo Node3D cuando la arena arranca. En la
## escena, la X y la Z de cada hijo son las suyas y su Y es CUÁNTO SOBRESALE
## del suelo: 0 = a ras, negativo = más hundido. Así una cobertura o un
## naufragio se mueve en el editor sin calcular la altura de la arena.
##
## Va en una arena de jefe (scenes/world/boss_arenas/), después del Terrain.


func _ready() -> void:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return
	terrain.ensure_built()
	for child: Node in get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		var at := prop.global_position
		prop.global_position = Vector3(at.x, at.y + terrain.height_at(at.x, at.z), at.z)
