class_name HellDressing
extends RefCounted
## Las copias de material con que arde una arena para HellTransformation: el
## suelo y una por tipo de superficie de los props. Las crea, las pone como
## override en las mallas y después escribe en todas el mismo uniform
## (write). Ningún prop recibe nodos nuevos: el bosque entero son estas pocas
## copias.
##
## NUNCA toca un recurso compartido: el material del suelo se duplica y los
## props reciben copias de `prop_material` como override, así los materiales
## de la escena y de los modelos glb quedan como estaban para la vuelta
## siguiente, los otros mapas y el fondo del menú.

## El shader de suelo que sabe quemarse. Por ruta y no con preload: un
## Shader guardado en una constante de script se libera tarde al cerrar.
const GROUND_SHADER_PATH := "res://assets/shaders/forest_ground.gdshader"
## Grupos cuyos nodos son props que arden (scatter, mesetas, formaciones).
const PROP_GROUPS: Array[StringName] = [&"arena_bounds", &"scatter_keepout"]

## Las copias que llevan el frente: el suelo y una por tipo de superficie.
var _materials: Array[ShaderMaterial] = []
## Copias de prop_material ya hechas, por tipo de superficie.
var _prop_copies: Dictionary[String, ShaderMaterial] = {}
var _props_dressed: int = 0
var _prop_material: ShaderMaterial = null
var _grass_flame_amount: float = 0.0


## Viste el suelo y los props de `arena`. `prop_material` es el material con
## que arden los props y `grass_flame_amount` cuánto arde lo verde que no es
## un árbol (0-1).
func dress(tree: SceneTree, arena: Node3D, prop_material: ShaderMaterial,
		grass_flame_amount: float) -> void:
	_prop_material = prop_material
	_grass_flame_amount = grass_flame_amount
	_dress_ground(tree)
	if prop_material != null:
		_dress_props(tree, arena)


## Escribe un uniform en todas las copias.
func write(parameter: StringName, value: Variant) -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(parameter, value)


func material_count() -> int:
	return _materials.size()


## Mallas que recibieron una copia.
func props_dressed() -> int:
	return _props_dressed


## El suelo: una copia propia del material del Terrain, si es el del bosque.
func _dress_ground(tree: SceneTree) -> void:
	var terrain := Terrain.find(tree)
	if terrain == null:
		return
	for node: Node in terrain.find_children("*", "MeshInstance3D", true, false):
		var view := node as MeshInstance3D
		var material := view.material_override as ShaderMaterial
		if material == null or material.shader == null \
				or material.shader.resource_path != GROUND_SHADER_PATH:
			continue
		var copy := material.duplicate() as ShaderMaterial
		view.material_override = copy
		_materials.append(copy)


## Los props: cada malla del scatter y de las mesetas puestas a mano recibe
## como override la copia que toca a su tipo de superficie.
func _dress_props(tree: SceneTree, arena: Node3D) -> void:
	var roots: Array[Node] = []
	for group: StringName in PROP_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			# Los interactuables (cofres, santuarios) no arden: siguen leyéndose.
			if arena.is_ancestor_of(node) and not node is Interactable:
				roots.append(node)
	for root: Node in roots:
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			_dress_mesh(node as MeshInstance3D)


func _dress_mesh(view: MeshInstance3D) -> void:
	if view == null or view.mesh == null:
		return
	if view.material_override != null:
		var whole := _burnt_copy(view.material_override)
		if whole != null:
			view.material_override = whole
			_props_dressed += 1
		return
	var dressed := false
	for surface: int in view.mesh.get_surface_count():
		var copy := _burnt_copy(view.get_active_material(surface))
		if copy != null:
			view.set_surface_override_material(surface, copy)
			dressed = true
	if dressed:
		_props_dressed += 1


## La copia de prop_material para una superficie como `source`, o null si no
## es un material que se sepa quemar. Una copia por TIPO: todos los modelos
## que comparten la textura colormap usan la misma.
func _burnt_copy(source: Material) -> ShaderMaterial:
	var base := source as BaseMaterial3D
	if base == null:
		return null
	var key := "flat:%s" % base.albedo_color.to_html()
	var mode := 1
	if base.albedo_texture != null:
		key = "texture:%d" % base.albedo_texture.get_instance_id()
		mode = 0
	elif base.vertex_color_use_as_albedo:
		key = "vertex:%s" % base.albedo_color.to_html()
		mode = 2
	if _prop_copies.has(key):
		return _prop_copies[key]
	var copy := _prop_material.duplicate() as ShaderMaterial
	copy.set_shader_parameter(&"source_mode", mode)
	copy.set_shader_parameter(&"flat_color", base.albedo_color)
	copy.set_shader_parameter(&"roughness", base.roughness)
	# Solo los modelos con textura (árboles) arden enteros y pierden el
	# follaje al enfriarse.
	copy.set_shader_parameter(&"leaves_fall", 1.0 if mode == 0 else 0.0)
	copy.set_shader_parameter(&"flame_amount", 1.0 if mode == 0 else _grass_flame_amount)
	if mode == 0:
		copy.set_shader_parameter(&"colormap", base.albedo_texture)
	_prop_copies[key] = copy
	_materials.append(copy)
	return copy
