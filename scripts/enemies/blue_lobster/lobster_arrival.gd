class_name LobsterArrival
extends Node
## La llegada de la Langosta Azul (nodo Arrival de BlueLobster.tscn). Trae la
## escena de la ENTRADA (el susto, LobsterEntrance) y la cuelga de la ARENA,
## no de la langosta: sigue ahí cuando ella ya murió, hasta que su canción
## termina de apagarse. Con entrada, la langosta llega sin que se la vea y sin
## barra, flecha ni marcador: todo eso aparece cuando empieza la pelea. Sin
## entrada, este nodo lleva la llegada simple de un jefe: aparece dentro de un
## anillo, ruge y, pasados plain_seconds, empieza a pelear.
## La llegada termina cuando alguien llama a BlueLobster.finish_entrance(): la
## entrada, o este nodo en la llegada simple.

@export_group("Entrada")
## Escena de la entrada: es la dueña del reloj de la llegada y de la canción. Vacío = llegada simple.
@export var entrance_scene: PackedScene = preload(
		"res://scenes/enemies/blue_lobster/LobsterEntrance.tscn")

@export_group("Llegada simple")
## Segundos que tarda en empezar a pelear desde que aparece.
@export var plain_seconds: float = 0.9
## Radio en metros del anillo con que aparece.
@export var plain_ring_radius: float = 3.5
## Rugido con que aparece (fila de Sfx.SOUND_LIBRARY).
@export var plain_roar_sfx: StringName = &"boss_roar"

var _boss: BlueLobster = null
var _entrance: LobsterEntrance = null
var _plain_left: float = 0.0


## Arranca la llegada con la langosta ya ubicada en la arena.
func begin(boss: BlueLobster) -> void:
	_boss = boss
	var stage := RunRoot.stage_parent(get_tree())
	if entrance_scene != null and stage != null:
		_entrance = entrance_scene.instantiate() as LobsterEntrance
		if _entrance != null:
			stage.add_child(_entrance)
	var seconds := _entrance.intro_seconds if _entrance != null else plain_seconds
	# Línea de log para los soaks: la llegada se mide desde aquí.
	print("%s entrance started: seconds=%.2f plain=%s at %.1fs" % [
			boss.boss_title, seconds, _entrance == null, RunState.stage_time])
	if _entrance != null:
		# Sin aviso: ni barra, ni flecha, ni marcador hasta que empiece la pelea.
		boss.hide_presence()
		_entrance.play(boss)
		return
	_plain_left = plain_seconds
	boss.pop_in(plain_ring_radius)
	Sfx.play(plain_roar_sfx)


## Un frame de física de la llegada: solo trabaja en la llegada simple.
func tick(delta: float) -> void:
	if _plain_left <= 0.0 or _boss == null:
		return
	_plain_left -= delta
	if _plain_left <= 0.0:
		_boss.finish_entrance(plain_seconds, false)


## La langosta murió: su canción se apaga de a poco.
func on_boss_dead() -> void:
	if _entrance != null and is_instance_valid(_entrance):
		_entrance.fade_out_song()
