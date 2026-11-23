class_name Outline
extends RefCounted
## Borde negro de silueta para personajes y enemigos: suma el material de
## borde (assets/materials/outline.tres, shader outline.gdshader) como
## next_pass de cada superficie opaca bajo un nodo. El grosor y el color se
## editan en ese .tres. Lo llama EnemyBase (los jugables no llevan borde).

const OUTLINE_MATERIAL: ShaderMaterial = preload("res://assets/materials/outline.tres")

## Copias con borde de los materiales compartidos de las mallas (id del
## material original -> copia): una sola copia por material, no una por cuerpo.
static var _outlined: Dictionary[int, Material] = {}


## Pone el borde a todas las mallas bajo `root` (y a `root` si es una malla).
static func apply(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		_apply_mesh(root as MeshInstance3D)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		_apply_mesh(node as MeshInstance3D)


static func _apply_mesh(mesh_node: MeshInstance3D) -> void:
	if mesh_node.mesh == null:
		return
	# Un material propio del nodo ya es de este cuerpo: se le engancha el
	# borde directo. Los de la malla son compartidos: se usa una copia.
	if mesh_node.material_override != null:
		_add_pass(mesh_node.material_override)
		return
	for surface: int in mesh_node.mesh.get_surface_count():
		var own := mesh_node.get_surface_override_material(surface)
		if own != null:
			_add_pass(own)
			continue
		var shared := mesh_node.mesh.surface_get_material(surface)
		if shared != null and _wants_outline(shared):
			mesh_node.set_surface_override_material(surface, _outlined_copy(shared))


static func _add_pass(material: Material) -> void:
	if _wants_outline(material) and material.next_pass == null:
		material.next_pass = OUTLINE_MATERIAL


## Los transparentes (gel, brillos, fuego) no llevan borde: se vería la
## cáscara negra a través de ellos. En un shader propio, escribir ALPHA lo
## delata como transparente.
static func _wants_outline(material: Material) -> bool:
	if material == OUTLINE_MATERIAL:
		return false
	var standard := material as BaseMaterial3D
	if standard != null:
		return standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	var custom := material as ShaderMaterial
	if custom != null and custom.shader != null:
		return not custom.shader.code.contains("ALPHA")
	return true


static func _outlined_copy(shared: Material) -> Material:
	var key := shared.get_instance_id()
	if not _outlined.has(key):
		var copy := shared.duplicate() as Material
		copy.next_pass = OUTLINE_MATERIAL
		_outlined[key] = copy
	return _outlined[key]
