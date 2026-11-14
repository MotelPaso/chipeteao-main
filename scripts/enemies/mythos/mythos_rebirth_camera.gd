class_name MythosRebirthCamera
extends Camera3D
## La cámara del renacer de Mythos (nodo Rebirth/Camera de
## MythosCinematic.tscn). La cinemática le dice dónde quedaron las cenizas y
## de qué lado está la party (frame) y después, en cada frame, cuánto avanzó
## el renacer (shoot). Con eso arma cuatro planos alrededor de las cenizas:
##   BRASA    a ras de suelo y de cerca: la brasa latiendo, cada vez más cerca
##   MAREA    una grúa que sube y se aleja: el fuego de la segunda fase
##            recorriendo el mapa
##   COLUMNA  desde abajo, subiendo la mirada por la columna de fuego
##   HÉROE    a ras de suelo, girando a su alrededor: Mythos renacido
## Elige el lado con menos escenografía entre ella y las cenizas
## (MythosSightline) y corre el plano héroe a un costado de la party.

enum Shot { EMBER, TIDE, PILLAR, HERO }

@export_group("Plano de la brasa")
## Fracción del renacer (0-1) hasta la que dura.
@export_range(0.0, 1.0) var ember_shot_until: float = 0.28
## Distancia a las cenizas al empezar, en metros.
@export var ember_distance_start: float = 9.5
## Distancia a las cenizas al terminar, en metros.
@export var ember_distance_end: float = 5.5
## Altura de la cámara, en metros sobre el suelo.
@export var ember_eye_height: float = 1.4
## Grados que gira alrededor de las cenizas durante el plano.
@export var ember_orbit_degrees: float = 32.0
## Campo de visión, en grados.
@export var ember_fov: float = 50.0

@export_group("Plano de la marea")
## Fracción del renacer (0-1) hasta la que dura.
@export_range(0.0, 1.0) var tide_shot_until: float = 0.62
## Distancia a las cenizas al empezar y al terminar, en metros.
@export var tide_distance_start: float = 14.0
@export var tide_distance_end: float = 48.0
## Altura de la cámara al empezar y al terminar, en metros sobre el suelo.
@export var tide_height_start: float = 6.0
@export var tide_height_end: float = 36.0
## Campo de visión, en grados.
@export var tide_fov: float = 66.0

@export_group("Plano de la columna")
## Fracción del renacer (0-1) hasta la que dura (el estallido).
@export_range(0.0, 1.0) var pillar_shot_until: float = 0.8
## Distancia a la columna, en metros.
@export var pillar_distance: float = 15.0
## Altura de la cámara, en metros sobre el suelo.
@export var pillar_eye_height: float = 1.6
## Altura a la que mira al empezar y al terminar, en metros (sube por la columna).
@export var pillar_look_start: float = 3.5
@export var pillar_look_end: float = 11.0
## Campo de visión, en grados.
@export var pillar_fov: float = 64.0

@export_group("Plano héroe")
## Distancia al jefe al empezar y al terminar, en metros.
@export var hero_distance_start: float = 24.0
@export var hero_distance_end: float = 17.0
## Altura de la cámara, en metros sobre el suelo (baja: lo mira desde abajo).
@export var hero_height: float = 1.8
## Grados que gira alrededor del jefe durante el plano.
@export var hero_orbit_degrees: float = 40.0
## Grados que el plano se corre hacia un costado de la party (así los raiders no quedan entre la cámara y el jefe).
@export var hero_side_degrees: float = 32.0
## Parte de la altura del jefe a la que mira (menos de 1 = el jefe queda arriba en pantalla y deja lugar al cartel).
@export_range(0.2, 1.0) var hero_look_fraction: float = 0.72
## Campo de visión al empezar y al terminar, en grados.
@export var hero_fov_start: float = 62.0
@export var hero_fov_end: float = 52.0

@export_group("Vista despejada")
## Grados hacia cada lado que prueba, de a uno, buscando un lado sin árboles en medio.
@export var clear_angles: Array[float] = [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0]
## Capas de física que tapan la vista (1 = suelo y escenografía).
@export_flags_3d_physics var clear_mask: int = 1
## Ancho de los pasillos que se miden, en metros.
@export var corridor_width: float = 10.0
## Metros mínimos entre la cámara y el suelo.
@export var ground_clearance: float = 1.2

var _point: Vector3 = Vector3.ZERO
var _away: Vector3 = Vector3.BACK
## Hacia qué costado de la party se corre el plano héroe (1 o -1).
var _hero_turn: float = 1.0
var _shake_strength: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 1.0
## Azar propio: el temblor no toca el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Fija el encuadre: `point` es donde quedaron las cenizas y `away` la
## dirección desde ahí hacia la party.
func frame(point: Vector3, away: Vector3) -> void:
	_point = point
	_hero_turn = _freer_turn(away)
	_away = _clearest_side(away)
	_shake_left = 0.0
	h_offset = 0.0
	v_offset = 0.0


## Hacia dónde queda el centro del plano héroe, desde las cenizas: hacia ahí
## mira Mythos al renacer.
func hero_side() -> Vector3:
	return _away.rotated(Vector3.UP, deg_to_rad(_hero_turn * hero_side_degrees))


## Tiembla con `strength` (metros de pantalla) durante `seconds`.
func shake(strength: float, seconds: float) -> void:
	_shake_strength = strength
	_shake_total = maxf(seconds, 0.01)
	_shake_left = _shake_total


## Coloca la cámara para el avance `progress` (0-1) del renacer.
## `body_height` es la altura del cuerpo del jefe sobre el suelo, ahora.
func shoot(progress: float, body_height: float, delta: float) -> void:
	var from := _point
	var look := _point
	if progress < ember_shot_until:
		var u := _span(progress, 0.0, ember_shot_until)
		from = _ember_eye(_away, u)
		look = _point + Vector3.UP * 0.6
		fov = ember_fov
	elif progress < tide_shot_until:
		var u := smoothstep(0.0, 1.0, _span(progress, ember_shot_until, tide_shot_until))
		from = _point + _away * lerpf(tide_distance_start, tide_distance_end, u) \
				+ Vector3.UP * lerpf(tide_height_start, tide_height_end, u)
		look = _point + Vector3.UP * 2.0
		fov = tide_fov
	elif progress < pillar_shot_until:
		var u := _span(progress, tide_shot_until, pillar_shot_until)
		from = _pillar_eye(_away)
		look = _point + Vector3.UP * lerpf(pillar_look_start, pillar_look_end, u)
		fov = pillar_fov
	else:
		var u := _span(progress, pillar_shot_until, 1.0)
		from = _hero_eye(_away, u)
		look = _point + Vector3.UP * clampf(body_height, 3.0, 40.0) * hero_look_fraction
		fov = lerpf(hero_fov_start, hero_fov_end, smoothstep(0.0, 1.0, u))
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		from.y = maxf(from.y, terrain.height_at(from.x, from.z) + ground_clearance)
	look_at_from_position(from, look)
	_shake_left = maxf(_shake_left - delta, 0.0)
	var jolt := _shake_strength * _shake_left / _shake_total
	h_offset = _rng.randf_range(-jolt, jolt)
	v_offset = _rng.randf_range(-jolt, jolt)


# --- dónde se para en cada plano si filma desde el lado `side` ------------------------

func _ember_eye(side: Vector3, u: float) -> Vector3:
	var angle := deg_to_rad(lerpf(-0.5, 0.5, u) * ember_orbit_degrees)
	return _point + side.rotated(Vector3.UP, angle) \
			* lerpf(ember_distance_start, ember_distance_end, u) + Vector3.UP * ember_eye_height


func _pillar_eye(side: Vector3) -> Vector3:
	return _point + side * pillar_distance + Vector3.UP * pillar_eye_height


func _hero_eye(side: Vector3, u: float) -> Vector3:
	var angle := deg_to_rad(_hero_turn
			* (hero_side_degrees + lerpf(-0.5, 0.5, u) * hero_orbit_degrees))
	return _point + side.rotated(Vector3.UP, angle) \
			* lerpf(hero_distance_start, hero_distance_end, u) + Vector3.UP * hero_height


# --- vista despejada ------------------------------------------------------------------

## De los lados de clear_angles, el que tiene menos estorbo entre la cámara y
## las cenizas en los planos a ras de suelo (a igualdad, el primero).
func _clearest_side(away: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var terrain := Terrain.find(get_tree())
	var best := away
	var best_crowd := 1000.0
	for degrees: float in clear_angles:
		var side := away.rotated(Vector3.UP, deg_to_rad(degrees))
		var crowd := 0.0
		for eye: Vector3 in [_ember_eye(side, 0.0), _pillar_eye(side), _hero_eye(side, 0.0),
				_hero_eye(side, 0.5), _hero_eye(side, 1.0)]:
			var ground := terrain.height_at(eye.x, eye.z) if terrain != null else eye.y
			crowd += MythosSightline.crowd_between(get_tree(), space, eye, _point, ground,
					corridor_width, clear_mask)
		if crowd < best_crowd:
			best_crowd = crowd
			best = side
		if crowd <= 0.0:
			break
	return best


## De los dos costados de la party, el que deja el plano héroe más lejos de
## los raiders (1 o -1).
func _freer_turn(away: Vector3) -> float:
	var best := 1.0
	var best_room := -1.0
	for turn: float in [1.0, -1.0]:
		_hero_turn = turn
		var eye := _hero_eye(away, 0.5)
		var room := 1000.0
		for group: StringName in [&"player", &"downed_players"]:
			for node: Node in get_tree().get_nodes_in_group(group):
				var body := node as Node3D
				if body != null:
					room = minf(room, body.global_position.distance_to(eye))
		if room > best_room:
			best_room = room
			best = turn
	return best


func _span(value: float, from: float, to: float) -> float:
	return clampf((value - from) / maxf(to - from, 0.0001), 0.0, 1.0)
