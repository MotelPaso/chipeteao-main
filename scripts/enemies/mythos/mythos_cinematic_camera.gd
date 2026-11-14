class_name MythosCinematicCamera
extends Camera3D
## La cámara de la cinemática de Mythos (nodo Camera de MythosCinematic.tscn).
## La cinemática le dice dónde aterriza el jefe y de qué lado está la party
## (frame) y después, en cada frame, cuánto avanzó la calma (shoot). Con eso
## arma tres planos seguidos:
##   GENERAL  desde lo alto, avanzando sobre el bosque mientras él baja como
##            un cometa
##   SUBIDA   cámara baja mirando hacia arriba, siguiéndolo en la caída
##   HÉROE    cámara a ras de suelo que gira despacio a su alrededor y se le
##            acerca, mirándolo desde abajo
## Al fijar el encuadre prueba varios lados y se queda con el que tiene
## menos árboles y lomas entre la cámara y el jefe. También tiembla cuando
## la cinemática se lo pide (shake).

@export_group("Plano general")
## Fracción de la calma (0-1) hasta la que dura el plano general.
@export_range(0.0, 1.0) var wide_until: float = 0.36
## Altura de la cámara en el plano general, en metros sobre el punto de llegada.
@export var wide_height: float = 30.0
## Distancia al punto de llegada al empezar el plano general, en metros.
@export var wide_distance: float = 56.0
## Metros que la cámara avanza durante el plano general.
@export var wide_push: float = 16.0

@export_group("Plano de subida")
## Fracción de la calma (0-1) hasta la que dura el plano de subida.
@export_range(0.0, 1.0) var follow_until: float = 0.64
## Distancia al punto de llegada en el plano de subida, en metros.
@export var follow_distance: float = 24.0
## Altura de la cámara en el plano de subida, en metros sobre el suelo.
@export var follow_height: float = 2.6

@export_group("Plano héroe")
## Distancia al jefe al empezar el plano héroe, en metros.
@export var hero_distance_start: float = 20.0
## Distancia al jefe al terminar el plano héroe, en metros.
@export var hero_distance_end: float = 14.0
## Altura de la cámara en el plano héroe, en metros sobre el suelo (baja: lo mira desde abajo).
@export var hero_height: float = 1.8
## Grados que la cámara gira alrededor del jefe durante el plano héroe.
@export var hero_orbit_degrees: float = 44.0
## Parte de la altura del jefe a la que mira la cámara en el plano héroe (menos de 1 = el jefe queda arriba en pantalla y deja lugar al cartel).
@export_range(0.2, 1.0) var hero_look_fraction: float = 0.68

@export_group("Vista despejada")
## Grados hacia cada lado que prueba, de a uno, buscando un lado sin árboles en medio.
@export var clear_angles: Array[float] = [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0]
## Altura sobre el suelo del punto del jefe que tiene que verse, en metros.
@export var clear_target_height: float = 5.0
## Capas de física que tapan la vista (1 = suelo y escenografía).
@export_flags_3d_physics var clear_mask: int = 1

@export_group("Lente")
## Campo de visión de la cámara, en grados.
@export var camera_fov: float = 60.0
## Campo de visión al final del plano héroe, en grados (más cerrado = más imponente).
@export var hero_fov: float = 50.0
## Metros mínimos entre la cámara y el suelo.
@export var ground_clearance: float = 1.4

var _boss_point: Vector3 = Vector3.ZERO
var _away: Vector3 = Vector3.BACK
var _shake_strength: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 1.0
## Azar propio: el temblor no toca el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Fija el encuadre: `boss_point` es donde aterriza el jefe y `away` la
## dirección desde ahí hacia la party.
func frame(boss_point: Vector3, away: Vector3) -> void:
	_boss_point = boss_point
	_away = _clearest_side(away)
	fov = camera_fov
	_shake_left = 0.0
	h_offset = 0.0
	v_offset = 0.0


## Tiembla con `strength` (metros de pantalla) durante `seconds`.
func shake(strength: float, seconds: float) -> void:
	_shake_strength = strength
	_shake_total = maxf(seconds, 0.01)
	_shake_left = _shake_total


## Coloca la cámara para el avance `progress` (0-1) de la calma. `body_height`
## es la altura del cuerpo del jefe sobre el suelo, ahora. Devuelve el punto
## al que mira.
func shoot(progress: float, body_height: float, delta: float) -> Vector3:
	var from := Vector3.ZERO
	var look := _boss_point + Vector3.UP * clampf(body_height, 3.0, 40.0)
	var floor_height := _boss_point.y
	if progress < wide_until:
		var u := progress / maxf(wide_until, 0.01)
		from = _boss_point + _away * (wide_distance - wide_push * u) + Vector3.UP * wide_height
		look = _boss_point + Vector3.UP * clampf(body_height * 0.55, 5.0, 30.0)
		fov = camera_fov
	elif progress < follow_until:
		from = _boss_point + _away.rotated(Vector3.UP, deg_to_rad(-18.0)) * follow_distance
		from.y = floor_height + follow_height
		fov = camera_fov
	else:
		var u := (progress - follow_until) / maxf(1.0 - follow_until, 0.01)
		var angle := deg_to_rad(lerpf(-0.5, 0.5, u) * hero_orbit_degrees)
		from = _boss_point + _away.rotated(Vector3.UP, angle) \
				* lerpf(hero_distance_start, hero_distance_end, u)
		from.y = floor_height + hero_height
		look = _boss_point + Vector3.UP * clampf(body_height, 3.0, 40.0) * hero_look_fraction
		fov = lerpf(camera_fov, hero_fov, smoothstep(0.0, 1.0, u))
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		from.y = maxf(from.y, terrain.height_at(from.x, from.z) + ground_clearance)
	look_at_from_position(from, look)
	_shake_left = maxf(_shake_left - delta, 0.0)
	var jolt := _shake_strength * _shake_left / _shake_total
	h_offset = _rng.randf_range(-jolt, jolt)
	v_offset = _rng.randf_range(-jolt, jolt)
	return look


## De los lados de clear_angles, el que deja ver al jefe desde más puntos
## del plano de subida y del plano héroe (a igualdad, el primero de la lista).
## Tiene que correr ANTES de congelar el mundo: congelada, la escenografía
## sale de la física y ningún rayo la toca.
func _clearest_side(away: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var target := _boss_point + Vector3.UP * clear_target_height
	var best := away
	var best_blocked := 1000
	for degrees: float in clear_angles:
		var side := away.rotated(Vector3.UP, deg_to_rad(degrees))
		var blocked := 0
		for eye: Vector3 in _eyes(side):
			var query := PhysicsRayQueryParameters3D.create(eye, target, clear_mask)
			if not space.intersect_ray(query).is_empty():
				blocked += 1
		if blocked < best_blocked:
			best_blocked = blocked
			best = side
		if blocked == 0:
			break
	return best


## Los puntos desde donde la cámara mira al jefe si se para del lado `side`:
## el del plano de subida y tres del giro del plano héroe.
func _eyes(side: Vector3) -> Array[Vector3]:
	var eyes: Array[Vector3] = [_boss_point + side.rotated(Vector3.UP, deg_to_rad(-18.0))
			* follow_distance + Vector3.UP * follow_height]
	for u: float in [0.0, 0.5, 1.0]:
		var angle := deg_to_rad(lerpf(-0.5, 0.5, u) * hero_orbit_degrees)
		eyes.append(_boss_point + side.rotated(Vector3.UP, angle)
				* lerpf(hero_distance_start, hero_distance_end, u) + Vector3.UP * hero_height)
	return eyes
