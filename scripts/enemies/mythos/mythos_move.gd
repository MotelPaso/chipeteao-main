class_name MythosMove
extends Node
## Base de un ataque de Mythos. Cada ataque es un nodo hijo de
## Mythos.tscn > Moves con sus propios valores: Mythos elige el próximo que
## esté listo, llama a begin() y después a tick() en cada frame de física
## hasta que devuelve true.
## La agresividad de Mythos (0-1, sale de StageBossScaling) acorta las
## esperas y suma proyectiles o zonas: cada ataque dice cuánto.

@export_group("Ritmo")
## Vida (1 = la primera) desde la que Mythos usa este ataque.
@export var unlock_life: int = 1
## Segundos de espera entre un uso y el siguiente, con agresividad 0.
@export var cooldown: float = 8.0
## Multiplicador de esa espera con agresividad 1 (0.6 = 40 % más seguido).
@export var cooldown_at_full_aggression: float = 0.6
## Fracción de la espera que corre antes del primer uso de cada vida (0-1).
@export_range(0.0, 1.0) var first_use_fraction: float = 0.5
## Distancia mínima al raider, en metros, para usarlo.
@export var min_range: float = 0.0
## Distancia máxima al raider, en metros, para usarlo.
@export var max_range: float = 40.0

## El jefe que lleva este ataque (lo pone Mythos en su _ready).
var boss: Mythos = null

var _cooldown_left: float = 0.0


## Mythos lo llama una vez, al aparecer.
func setup(owner_boss: Mythos) -> void:
	boss = owner_boss
	reset_cooldown()


## Deja la espera de primer uso (al aparecer y en cada renacer).
func reset_cooldown() -> void:
	_cooldown_left = cooldown * first_use_fraction


func tick_cooldown(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## True si Mythos puede usarlo ahora, en su vida `life` y a `distance`
## metros del raider.
func is_ready(life: int, distance: float) -> bool:
	return life >= unlock_life and _cooldown_left <= 0.0 \
			and distance >= min_range and distance <= max_range


## Arranca la espera hasta el próximo uso, acortada por la agresividad.
func start_cooldown() -> void:
	_cooldown_left = cooldown * aggression_lerp(1.0, cooldown_at_full_aggression)


## `calm` con agresividad 0 y `fierce` con agresividad 1.
func aggression_lerp(calm: float, fierce: float) -> float:
	return lerpf(calm, fierce, boss.aggression if boss != null else 0.0)


## `base` más la parte de `extra_at_full` que toca a la agresividad actual.
func aggression_count(base: int, extra_at_full: int) -> int:
	return base + roundi(float(extra_at_full) * (boss.aggression if boss != null else 0.0))


## Virtual: empieza el ataque contra `target`.
func begin(_target: Node3D) -> void:
	pass


## Virtual: un frame de física del ataque. Devuelve true cuando terminó.
func tick(_delta: float) -> bool:
	return true


## Virtual: el ataque se corta a la mitad (Mythos cae en cenizas o muere).
func cancel() -> void:
	pass


## Virtual: multiplica los números de daño del ataque.
func scale_damage(_multiplier: float) -> void:
	pass
