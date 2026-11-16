class_name LobsterVoice
extends Node
## La voz de la Langosta Azul (nodo Voice de BlueLobster.tscn): chasquidos,
## siseos y gruñidos. Ruge al empezar la pelea, suena al empezar cada ataque
## (el sonido es un valor de cada ataque: LobsterMove.call_sfx), sisea cuando
## un golpe le duele, gruñe al morir y suelta tableteos sueltos mientras
## pelea. Todos son filas de Sfx.SOUND_LIBRARY.

@export_group("Sonidos")
## Rugido al empezar la pelea.
@export var roar_sfx: StringName = &"lobster_roar"
## Tableteo suelto mientras pelea (vacío = no suena).
@export var call_sfx: StringName = &"lobster_chitter"
## Segundos mínimos entre dos tableteos sueltos.
@export var call_min_seconds: float = 5.0
## Segundos máximos entre dos tableteos sueltos.
@export var call_max_seconds: float = 9.0
## Siseo cuando un solo golpe le saca mucha vida.
@export var hurt_sfx: StringName = &"lobster_hiss"
## Fracción de su vida máxima (0-1) que tiene que sacarle un golpe para que sisee.
@export_range(0.0, 1.0) var hurt_fraction: float = 0.03
## Segundos mínimos entre dos siseos.
@export var hurt_cooldown: float = 1.5
## Gruñido de su muerte.
@export var death_sfx: StringName = &"lobster_death"

## Azar propio: los tableteos sueltos no tocan el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _call_left: float = 0.0
var _hurt_left: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_call_left = _rng.randf_range(call_min_seconds, call_max_seconds)


func fight_started() -> void:
	Sfx.play(roar_sfx)


## Un frame de pelea: cada tanto suelta un tableteo. True si acaba de sonar.
func tick(delta: float) -> bool:
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_call_left -= delta
	if _call_left > 0.0:
		return false
	_call_left = _rng.randf_range(call_min_seconds, call_max_seconds)
	if call_sfx.is_empty():
		return false
	Sfx.play(call_sfx)
	return true


## Empieza un ataque: suena su aviso, y los tableteos sueltos esperan.
func move_started(move: LobsterMove) -> void:
	if move.call_sfx.is_empty():
		return
	Sfx.play(move.call_sfx)
	_call_left = maxf(_call_left, call_min_seconds * 0.5)


## Un golpe le sacó `amount` de `max_hp`. True si le dolió lo bastante para sisear.
func hurt(amount: float, max_hp: float) -> bool:
	if _hurt_left > 0.0 or amount < max_hp * hurt_fraction:
		return false
	_hurt_left = hurt_cooldown
	Sfx.play(hurt_sfx)
	return true


func died() -> void:
	Sfx.play(death_sfx)
