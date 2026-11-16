class_name LobsterMove
extends Node
## Base de un ataque de la Langosta Azul. Cada ataque es un nodo hijo de
## BlueLobster.tscn > Moves con sus propios valores: la langosta elige el
## próximo que esté listo (LobsterMoveset), llama a begin() y después a tick()
## en cada frame de física hasta que devuelve true.
## La agresividad de la langosta (0-1, sale de StageBossScaling) acorta las
## esperas y los avisos y suma golpes: cada ataque dice cuánto.
## El cuerpo viaja en todos los ataques: lo llevan con boss.walk() (camina) o
## con boss.glide_to() (un salto, un túnel, una embestida).

@export_group("Ritmo")
## Segundos de espera entre un uso y el siguiente, con agresividad 0.
@export var cooldown: float = 9.0
## Multiplicador de esa espera con agresividad 1 (0.6 = 40 % más seguido).
@export var cooldown_at_full_aggression: float = 0.6
## Fracción de la espera que corre antes del primer uso (0-1).
@export_range(0.0, 1.0) var first_use_fraction: float = 0.5
## Distancia mínima al raider, en metros, para usarlo.
@export var min_range: float = 0.0
## Distancia máxima al raider, en metros, para usarlo.
@export var max_range: float = 40.0
## Sonido de la langosta al empezar este ataque (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var call_sfx: StringName = &""

## La langosta que lleva este ataque (la pone ella en su _ready).
var boss: BlueLobster = null

var _cooldown_left: float = 0.0


## La langosta lo llama una vez, al aparecer.
func setup(owner_boss: BlueLobster) -> void:
	boss = owner_boss
	_cooldown_left = cooldown * first_use_fraction


func tick_cooldown(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## True si puede usarlo ahora, a `distance` metros del raider.
func is_ready(distance: float) -> bool:
	return _cooldown_left <= 0.0 and distance >= min_range and distance <= max_range


## Arranca la espera hasta el próximo uso, acortada por la agresividad.
func start_cooldown() -> void:
	_cooldown_left = cooldown * aggression_lerp(1.0, cooldown_at_full_aggression)


## `calm` con agresividad 0 y `fierce` con agresividad 1.
func aggression_lerp(calm: float, fierce: float) -> float:
	return lerpf(calm, fierce, boss.aggression if boss != null else 0.0)


## `base` más la parte de `extra_at_full` que toca a la agresividad actual.
func aggression_count(base: int, extra_at_full: int) -> int:
	return base + roundi(float(extra_at_full) * (boss.aggression if boss != null else 0.0))


## Nombre del ataque para el harness: el del nodo, en minúsculas.
func state_name() -> StringName:
	return StringName(String(name).to_snake_case())


## True si `target` sigue siendo un raider al que apuntar.
func has_target(target: Node3D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree()


## Devuelve al pool un disco de aviso que este ataque todavía tiene en pantalla
## (el ataque se corta, o el disco ya cumplió). Los discos vuelven solos al
## pool al terminar: quien guarda uno lo suelta ANTES de ese momento.
func release_disc(disc: TelegraphDisc) -> void:
	if disc != null and is_instance_valid(disc) and disc.is_inside_tree():
		Pools.release(disc)


## Virtual: empieza el ataque contra `target`.
func begin(_target: Node3D) -> void:
	pass


## Virtual: un frame de física del ataque. Devuelve true cuando terminó.
func tick(_delta: float) -> bool:
	return true


## Virtual: el ataque se corta a la mitad (la langosta muere).
func cancel() -> void:
	pass


## Virtual: multiplica los números de daño del ataque.
func scale_damage(_multiplier: float) -> void:
	pass
