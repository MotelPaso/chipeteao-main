class_name MythosZones
extends Node
## Las zonas de fuego de Mythos (nodo Zones de Mythos.tscn). Saca cada
## FireZone de Pools con un tope de zonas vivas y las apaga todas cuando
## Mythos muere. Una zona nunca nace junto a un raider caído (hay que poder
## reanimarlo) ni pisando un círculo a salvo. Sobre un raider EN PIE solo nace si el ataque lo pide
## (on_raiders) y con un aviso de al menos min_warn_on_raiders segundos.
## Los ataques no llaman aquí directo: le piden la zona a
## Mythos.spawn_fire_zone(), que antes lleva el punto a suelo caminable.

@export_group("Zonas de fuego")
## Escena de la zona de fuego (FireZone, sale de Pools).
@export var fire_zone_scene: PackedScene = preload("res://scenes/fx/FireZone.tscn")
## Tope de zonas de fuego vivas a la vez.
@export var max_live_zones: int = 40
## Metros libres que una zona deja entre su borde y cualquier raider en pie, cuando el ataque no apunta a los raiders.
@export var raider_clearance: float = 1.2
## Metros libres que una zona nueva deja entre su borde y un raider caído.
@export var downed_clearance: float = 2.5
## Aviso mínimo, en segundos, de una zona que nace bajo un raider en pie.
@export var min_warn_on_raiders: float = 0.7


## Marca una zona de fuego en `at` (un punto ya sobre el suelo) si cabe bajo
## el tope y respeta a los raiders. Devuelve true si salió.
func mark(at: Vector3, radius: float, warn_seconds: float, burn_seconds: float,
		dps: float, on_raiders: bool = false) -> bool:
	if fire_zone_scene == null \
			or get_tree().get_node_count_in_group(FireZone.GROUP) >= max_live_zones:
		return false
	if not _clear_of(&"downed_players", at, radius + downed_clearance) \
			or SafeCircle.overlaps_any(get_tree(), at, radius):
		return false
	if not on_raiders and not _clear_of(&"player", at, radius + raider_clearance):
		return false
	var zone := Pools.acquire_scene(fire_zone_scene) as FireZone
	if zone == null:
		return false
	var warn := maxf(warn_seconds, min_warn_on_raiders) if on_raiders else warn_seconds
	zone.mark(at, radius, warn, burn_seconds, dps)
	return true


## Apaga todas las zonas de fuego vivas.
func extinguish_all() -> void:
	get_tree().call_group(FireZone.GROUP, "extinguish")


## True si ningún cuerpo del grupo queda a menos de `reach` metros de `at`.
func _clear_of(group: StringName, at: Vector3, reach: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group(group):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - at
		to_body.y = 0.0
		if to_body.length_squared() < reach * reach:
			return false
	return true
