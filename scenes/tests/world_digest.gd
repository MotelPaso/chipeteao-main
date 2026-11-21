class_name WorldDigest
extends RefCounted
## Tres medidas del mundo recién construido, una línea cada una, para
## comparar una arena antes y después de un cambio sin mirar una sola foto:
##
##   World digest: <mapa> nodes=<n> hash=<16 hex>
##       la transformación (al milímetro) de cada prop, formación, meseta y
##       POI bajo la arena. Mismo hash = mismo mundo.
##   Hell skip: <mapa> meshes=<n> total=<n>
##       mallas bajo la arena que la regla de HellDressing dejaría sin quemar.
##   Ground slope: <mapa> p95=<grados> max=<grados> cells=<n>
##       percentil 95 de la pendiente del suelo caminable, en celdas de 1 m.
##
## CONGELADO: estas líneas son la línea base de otros cambios. No se les
## cambia el cálculo ni el formato; una medida nueva va en su propia línea.
## ArenaProbe llama a report() al empezar cada etapa.

## El shader de suelo que HellDressing sabe quemar (su GROUND_SHADER_PATH).
const GROUND_SHADER_PATH := "res://assets/shaders/forest_ground.gdshader"
## Grupos cuyos nodos son props que arden (los PROP_GROUPS de HellDressing).
const PROP_GROUPS: Array[StringName] = [&"arena_bounds", &"scatter_keepout"]
## Lado de la celda donde se mide la pendiente, en metros.
const SLOPE_CELL: float = 1.0
## Milímetros por metro: la resolución del digest.
const MILLI: float = 1000.0


## Imprime las tres líneas para `arena` (la arena viva de la etapa).
static func report(tree: SceneTree, arena: Node3D) -> void:
	if tree == null or arena == null:
		return
	var map_id := String(arena.get("map_id"))
	var rows := world_rows(arena)
	print("World digest: %s nodes=%d hash=%s" % [
			map_id, rows.size(), "\n".join(rows).sha256_text().left(16)])
	var skipped := hell_skipped(tree, arena)
	print("Hell skip: %s meshes=%d total=%d" % [map_id, skipped[0], skipped[1]])
	var slope := ground_slope(tree, arena)
	print("Ground slope: %s p95=%.2f max=%.2f cells=%d" % [
			map_id, slope["p95"], slope["max"], slope["cells"]])


## Una fila por prop, formación, meseta y POI bajo `arena`, en orden de
## árbol: de qué escena o script sale y su transformación global al milímetro.
## Sin nombres de nodo: los automáticos llevan un contador global que cambia
## con cualquier nodo creado antes.
static func world_rows(arena: Node3D) -> PackedStringArray:
	var rows := PackedStringArray()
	_collect_rows(arena, arena, rows)
	return rows


## [mallas que HellDressing dejaría sin quemar, mallas en total] bajo `arena`.
## Repite la regla de HellDressing sin tocar ningún material: bajo el
## Terrain arde la malla cuyo override es un ShaderMaterial del shader de
## suelo; bajo un nodo de PROP_GROUPS que no sea Interactable arde la malla
## con un BaseMaterial3D (como override o en alguna superficie).
static func hell_skipped(tree: SceneTree, arena: Node3D) -> Array[int]:
	var burning: Dictionary[int, bool] = {}
	for node: Node in tree.get_nodes_in_group(&"terrain"):
		if not arena.is_ancestor_of(node):
			continue
		for child: Node in node.find_children("*", "MeshInstance3D", true, false):
			var view := child as MeshInstance3D
			var material := view.material_override as ShaderMaterial
			if material != null and material.shader != null \
					and material.shader.resource_path == GROUND_SHADER_PATH:
				burning[view.get_instance_id()] = true
	for group: StringName in PROP_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			if not arena.is_ancestor_of(node) or node is Interactable:
				continue
			for child: Node in node.find_children("*", "MeshInstance3D", true, false):
				var view := child as MeshInstance3D
				if _prop_burns(view):
					burning[view.get_instance_id()] = true
	var total := arena.find_children("*", "MeshInstance3D", true, false).size()
	return [total - burning.size(), total]


## Pendiente del suelo caminable de la arena: {p95, max, cells}, en grados.
## Recorre celdas de SLOPE_CELL metros; cuenta las que la máscara da por
## caminables y `skip` (opcional, recibe el Vector2 del centro) no descarta.
## La pendiente sale de Terrain.height_at por diferencias centrales.
static func ground_slope(tree: SceneTree, arena: Node3D,
		skip: Callable = Callable()) -> Dictionary:
	var result := {"p95": 0.0, "max": 0.0, "cells": 0}
	var terrain: Terrain = null
	for node: Node in tree.get_nodes_in_group(&"terrain"):
		if arena.is_ancestor_of(node):
			terrain = node as Terrain
	var bounds: Node = null
	for node: Node in tree.get_nodes_in_group(&"arena_bounds"):
		if arena.is_ancestor_of(node) and node.has_method(&"is_walkable"):
			bounds = node
	if terrain == null or bounds == null:
		return result
	var half := terrain.size * 0.5
	var cells := int(round(terrain.size / SLOPE_CELL))
	var reach := SLOPE_CELL * 0.5
	var slopes := PackedFloat32Array()
	for iz in cells:
		var z := -half + (float(iz) + 0.5) * SLOPE_CELL
		for ix in cells:
			var x := -half + (float(ix) + 0.5) * SLOPE_CELL
			var center := Vector2(x, z)
			if not bool(bounds.call(&"is_walkable", center)):
				continue
			if skip.is_valid() and bool(skip.call(center)):
				continue
			var dx := (terrain.height_at(x + reach, z) - terrain.height_at(x - reach, z)) / SLOPE_CELL
			var dz := (terrain.height_at(x, z + reach) - terrain.height_at(x, z - reach)) / SLOPE_CELL
			slopes.append(rad_to_deg(atan(sqrt(dx * dx + dz * dz))))
	if slopes.is_empty():
		return result
	slopes.sort()
	var last := slopes.size() - 1
	result["p95"] = slopes[int(float(last) * 0.95)]
	result["max"] = slopes[last]
	result["cells"] = slopes.size()
	return result


## Baja por el árbol de la arena y anota las filas que cuentan. No entra en
## un Interactable (sus piezas internas no son mundo) ni en lo que ya se va.
static func _collect_rows(node: Node, arena: Node3D, rows: PackedStringArray) -> void:
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var spot := child as Node3D
		if spot != null and _counts(spot):
			rows.append(_row(spot))
		if child is Interactable or child is CharacterBody3D:
			continue
		# Bajo un prop del scatter no hay más mundo que el propio prop.
		if node.is_in_group(&"arena_bounds"):
			continue
		_collect_rows(child, arena, rows)


## True si `spot` es un prop, una formación, una meseta o un POI: hijo
## directo del scatter, un Interactable, un grupo de autor o una pieza suya.
static func _counts(spot: Node3D) -> bool:
	if spot is Interactable:
		return true
	if spot.is_in_group(&"scatter_keepout"):
		return true
	var parent := spot.get_parent()
	if parent == null:
		return false
	if parent.is_in_group(&"arena_bounds"):
		return true
	return parent.is_in_group(&"scatter_keepout") and not (parent is Interactable)


static func _row(spot: Node3D) -> String:
	var kind := spot.scene_file_path
	if kind.is_empty():
		var script := spot.get_script() as Script
		kind = script.resource_path if script != null else spot.get_class()
	var at := spot.global_transform
	return "%s %d %d %d %d %d %d %d %d %d %d %d %d" % [kind,
			roundi(at.origin.x * MILLI), roundi(at.origin.y * MILLI), roundi(at.origin.z * MILLI),
			roundi(at.basis.x.x * MILLI), roundi(at.basis.x.y * MILLI), roundi(at.basis.x.z * MILLI),
			roundi(at.basis.y.x * MILLI), roundi(at.basis.y.y * MILLI), roundi(at.basis.y.z * MILLI),
			roundi(at.basis.z.x * MILLI), roundi(at.basis.z.y * MILLI), roundi(at.basis.z.z * MILLI)]


## La regla de HellDressing._dress_mesh para una malla de prop.
static func _prop_burns(view: MeshInstance3D) -> bool:
	if view == null or view.mesh == null:
		return false
	if view.material_override != null:
		return view.material_override is BaseMaterial3D
	for surface: int in view.mesh.get_surface_count():
		if view.get_active_material(surface) is BaseMaterial3D:
			return true
	return false
