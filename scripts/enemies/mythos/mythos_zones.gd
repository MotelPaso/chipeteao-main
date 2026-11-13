class_name MythosZones
extends Node
## Las zonas de fuego de Mythos (nodo Zones de Mythos.tscn). Saca cada
## FireZone de Pools con un tope de zonas vivas y nunca encima de un raider,
## en pie o caído, y las apaga todas cuando Mythos muere.
## Los ataques no llaman aquí directo: le piden la zona a
## Mythos.spawn_fire_zone(), que antes lleva el punto a suelo caminable.

@export_group("Zonas de fuego")
## Escena de la zona de fuego (FireZone, sale de Pools).
@export var fire_zone_scene: PackedScene = preload("res://scenes/fx/FireZone.tscn")
## Tope de zonas de fuego vivas a la vez.
@export var max_live_zones: int = 16
## Metros libres que una zona nueva deja entre su borde y cualquier raider en pie.
@export var raider_clearance: float = 1.2
## Metros libres que una zona nueva deja entre su borde y un raider caído.
@export var downed_clearance: float = 2.5


## Marca una zona de fuego en `at` (un punto ya sobre el suelo) si cabe bajo
## el tope y no nace encima de un raider. Devuelve true si salió.
func mark(at: Vector3, radius: float, warn_seconds: float, burn_seconds: float,
		dps: float) -> bool:
	if fire_zone_scene == null \
			or get_tree().get_node_count_in_group(FireZone.GROUP) >= max_live_zones:
		return false
	if not _clear_of_raiders(at, radius):
		return false
	var zone := Pools.acquire_scene(fire_zone_scene) as FireZone
	if zone == null:
		return false
	zone.mark(at, radius, warn_seconds, burn_seconds, dps)
	return true


## Apaga todas las zonas de fuego vivas.
func extinguish_all() -> void:
	get_tree().call_group(FireZone.GROUP, "extinguish")


## True si una zona de `radius` en `at` deja libres a todos los raiders: en
## pie con raider_clearance y caídos con downed_clearance.
func _clear_of_raiders(at: Vector3, radius: float) -> bool:
	for group: StringName in [&"player", &"downed_players"]:
		var clearance := raider_clearance if group == &"player" else downed_clearance
		var reach := radius + clearance
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var to_body := body.global_position - at
			to_body.y = 0.0
			if to_body.length_squared() < reach * reach:
				return false
	return true
