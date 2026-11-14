class_name MythosArrival
extends Node
## La llegada de Mythos (nodo Arrival de Mythos.tscn). Trae la cinemática y
## la transformación del mapa y las cuelga de la ARENA, no de Mythos: siguen
## ahí cuando él ya murió (la canción se apaga sola y el bosque queda
## quemado). Con cinemática, lo que el fénix hace en pantalla lo lleva ella
## (su nodo Entrance); sin cinemática este nodo lleva la entrada simple:
## Mythos baja del cielo en plain_arrival_seconds.
## La calma termina cuando alguien llama a Mythos.finish_calm(): la
## cinemática, o este nodo en la entrada simple.

@export_group("Llegada")
## Escena de la cinemática de llegada: es la dueña de la calma y de la canción. Vacío = entrada simple.
@export var cinematic_scene: PackedScene = preload(
		"res://scenes/enemies/mythos/MythosCinematic.tscn")
## Escena que quema el mapa mientras llega. Vacío = el mapa no cambia.
@export var transformation_scene: PackedScene = preload(
		"res://scenes/enemies/mythos/HellTransformation.tscn")
## Segundos de la entrada simple, cuando llega sin cinemática.
@export var plain_arrival_seconds: float = 1.2
## Altura en metros desde la que baja en la entrada simple.
@export var plain_arrival_height: float = 70.0

var _boss: Mythos = null
var _cinematic: MythosCinematic = null
var _transformation: HellTransformation = null
var _calm_seconds: float = 0.0
var _plain_left: float = 0.0


## Arranca la calma con Mythos ya ubicado en la arena.
func begin(boss: Mythos) -> void:
	_boss = boss
	var stage := RunRoot.stage_parent(get_tree())
	if transformation_scene != null and stage != null:
		_transformation = transformation_scene.instantiate() as HellTransformation
		if _transformation != null:
			stage.add_child(_transformation)
	if cinematic_scene != null and stage != null:
		_cinematic = cinematic_scene.instantiate() as MythosCinematic
		if _cinematic != null:
			stage.add_child(_cinematic)
	# Con cinemática, ella lleva el reloj de la calma y llama a finish_calm().
	_calm_seconds = _cinematic.calm_seconds if _cinematic != null else plain_arrival_seconds
	_plain_left = 0.0 if _cinematic != null else plain_arrival_seconds
	if _cinematic == null:
		_descend(0.0)
	# Línea de log para los soaks: la calma se mide desde aquí.
	print("%s calm started: seconds=%.2f at %.1fs" % [
			boss.boss_title, _calm_seconds, RunState.stage_time])
	if _transformation != null:
		# El bosque empieza a arder cuando Mythos golpea el suelo; en la
		# entrada simple, enseguida.
		var front_delay := _cinematic.impact_seconds() if _cinematic != null else 0.0
		_transformation.begin(boss.global_position, _calm_seconds, front_delay)
	if _cinematic != null:
		_cinematic.play(boss, _transformation)


## Un frame de física de la llegada: solo trabaja en la entrada simple.
func tick(delta: float) -> void:
	if _plain_left <= 0.0 or _boss == null:
		return
	_plain_left -= delta
	_descend(1.0 - _plain_left / maxf(_calm_seconds, 0.01))
	if _plain_left <= 0.0:
		_boss.finish_calm(_calm_seconds, false)


## La última muerte de Mythos: el mapa se enfría y la canción se apaga.
func on_boss_dead() -> void:
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.cool_down()
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.fade_out_song()


## La entrada simple con avance `progress` (0-1): baja frenando, rápido en lo
## alto y suave al llegar a su altura de vuelo.
func _descend(progress: float) -> void:
	var rig := _boss.rig
	var ease_out := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 3.0)
	var height := lerpf(plain_arrival_height, rig.hover_height, ease_out)
	rig.fly_at(_boss.global_position + Vector3.UP * height, _boss.global_rotation.y,
			rig.fly_pitch_degrees, 0.0)


## Destello a pantalla completa (el de la cinemática); sin cinemática no hace nada.
func flash() -> void:
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.flash()
