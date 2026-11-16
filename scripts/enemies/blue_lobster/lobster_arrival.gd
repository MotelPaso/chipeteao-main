class_name LobsterArrival
extends Node
## La llegada de la Langosta Azul (nodo Arrival de BlueLobster.tscn). Es la
## llegada simple de un jefe: aparece dentro de un anillo, ruge y, pasados
## plain_seconds, empieza a pelear (BlueLobster.finish_entrance).

@export_group("Llegada simple")
## Segundos que tarda en empezar a pelear desde que aparece.
@export var plain_seconds: float = 0.9
## Radio en metros del anillo con que aparece.
@export var plain_ring_radius: float = 3.5
## Rugido con que aparece (fila de Sfx.SOUND_LIBRARY).
@export var plain_roar_sfx: StringName = &"boss_roar"

var _boss: BlueLobster = null
var _plain_left: float = 0.0


## Arranca la llegada con la langosta ya ubicada en la arena.
func begin(boss: BlueLobster) -> void:
	_boss = boss
	_plain_left = plain_seconds
	boss.pop_in(plain_ring_radius)
	Sfx.play(plain_roar_sfx)
	# Línea de log para los soaks: la llegada se mide desde aquí.
	print("%s entrance started: seconds=%.2f plain=true at %.1fs" % [
			boss.boss_title, plain_seconds, RunState.stage_time])


## Un frame de física de la llegada simple.
func tick(delta: float) -> void:
	if _plain_left <= 0.0 or _boss == null:
		return
	_plain_left -= delta
	if _plain_left <= 0.0:
		_boss.finish_entrance(plain_seconds, false)


## La langosta murió.
func on_boss_dead() -> void:
	pass
