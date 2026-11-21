class_name MythosMove
extends Node
## Base de un ataque de Mythos. Cada ataque es un nodo hijo de
## Mythos.tscn > Moves con sus propios valores: Mythos elige el próximo que
## esté listo, llama a begin() y después a tick() en cada frame de física
## hasta que devuelve true.
## La agresividad de Mythos (0-1, sale de StageBossScaling) acorta las
## esperas y suma proyectiles o zonas: cada ataque dice cuánto.
## Cada ataque dice además desde dónde se usa (stance): en vuelo o posado
## en tierra. La Picada lo posa (Mythos.land) y el Aletazo lo hace despegar.
## Con flight_factor Mythos sigue volando alrededor del raider mientras lo
## hace, y con chain_to otro ataque sale pegado a este, sin pausa (un combo).

## Desde dónde puede usar Mythos un ataque.
enum Stance { AIR, GROUND, ANY }

@export_group("Ritmo")
## Desde dónde lo usa: en vuelo (AIR), posado en tierra (GROUND) o en cualquiera de los dos (ANY).
@export var stance: Stance = Stance.AIR
## Vida (1 = la primera) desde la que Mythos usa este ataque.
@export var unlock_life: int = 1
## Vida desde la que DEJA de usarlo, porque otro ataque lo reemplaza (0 = lo usa hasta el final).
@export var retire_life: int = 0
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
## Grito de Mythos al empezar este ataque (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var call_sfx: StringName = &""
## Fracción de su vuelo que mantiene mientras hace este ataque (0 = se queda quieto en el aire, 1 = sigue girando igual de rápido).
@export_range(0.0, 1.0) var flight_factor: float = 0.0

@export_group("Combo")
## Ataque (nombre de un nodo hermano) que sale pegado a este, sin pausa entre los dos (vacío = ninguno).
@export var chain_to: StringName = &""
## Vida (1 = la primera) desde la que encadena ese ataque.
@export var chain_from_life: int = 1
## Probabilidad (0-1) de encadenarlo cada vez que termina.
@export_range(0.0, 1.0) var chain_chance: float = 1.0

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


## True si Mythos puede usarlo ahora: en su vida `life`, a `distance` metros
## del raider y volando o posado (`grounded`).
func is_ready(life: int, distance: float, grounded: bool) -> bool:
	return fits(life, grounded) and _cooldown_left <= 0.0 \
			and distance >= min_range and distance <= max_range


## True si este ataque es de la vida `life` y de la postura de ahora, sin
## mirar su espera ni la distancia (lo que alcanza para salir encadenado).
func fits(life: int, grounded: bool) -> bool:
	if stance != Stance.ANY and (stance == Stance.GROUND) != grounded:
		return false
	if retire_life > 0 and life >= retire_life:
		return false
	return life >= unlock_life


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


## Virtual: un frame de pelea, se esté usando o no este ataque. Para lo que
## un ataque hace de fondo (la lluvia de la última vida).
func tick_always(_delta: float, _life: int) -> void:
	pass


## Virtual: el ataque se corta a la mitad (Mythos cae en cenizas o muere).
func cancel() -> void:
	pass


## Virtual: multiplica los números de daño del ataque.
func scale_damage(_multiplier: float) -> void:
	pass
