class_name MythosVoice
extends Node
## La voz de Mythos (nodo Voice de Mythos.tscn): sus gritos de pájaro. Grita
## al empezar la pelea, al empezar cada ataque (el grito es un valor de cada
## ataque: MythosMove.call_sfx), cuando un golpe le duele, al morir, y suelta
## llamados sueltos mientras pelea. Todos son filas de Sfx.SOUND_LIBRARY.

@export_group("Gritos")
## Grito al empezar la pelea.
@export var arrival_sfx: StringName = &"phoenix_cry"
## Llamado suelto mientras pelea (vacío = no llama).
@export var call_sfx: StringName = &"phoenix_call"
## Segundos mínimos entre dos llamados sueltos.
@export var call_min_seconds: float = 6.0
## Segundos máximos entre dos llamados sueltos.
@export var call_max_seconds: float = 11.0
## Chillido cuando un solo golpe le saca mucha vida.
@export var hurt_sfx: StringName = &"phoenix_hurt"
## Fracción de su vida máxima (0-1) que tiene que sacarle un golpe para que chille.
@export_range(0.0, 1.0) var hurt_fraction: float = 0.03
## Segundos mínimos entre dos chillidos.
@export var hurt_cooldown: float = 1.6
## Grito de su última muerte.
@export var death_sfx: StringName = &"phoenix_death"

## Azar propio: los llamados sueltos no tocan el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _call_left: float = 0.0
var _hurt_left: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_call_left = _rng.randf_range(call_min_seconds, call_max_seconds)


func fight_started() -> void:
	Sfx.play(arrival_sfx)


## Un frame de pelea: cada tanto suelta un llamado.
func tick(delta: float) -> void:
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_call_left -= delta
	if _call_left > 0.0:
		return
	_call_left = _rng.randf_range(call_min_seconds, call_max_seconds)
	if not call_sfx.is_empty():
		Sfx.play(call_sfx)


## Empieza un ataque: suena su grito, y los llamados sueltos esperan.
func move_started(move: MythosMove) -> void:
	if move.call_sfx.is_empty():
		return
	Sfx.play(move.call_sfx)
	_call_left = maxf(_call_left, call_min_seconds * 0.5)


## Un golpe le sacó `amount` de `max_hp`. True si le dolió lo bastante para chillar.
func hurt(amount: float, max_hp: float) -> bool:
	if _hurt_left > 0.0 or amount < max_hp * hurt_fraction:
		return false
	_hurt_left = hurt_cooldown
	Sfx.play(hurt_sfx)
	return true


func died() -> void:
	Sfx.play(death_sfx)
