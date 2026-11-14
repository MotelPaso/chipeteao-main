class_name MythosCinematicCamera
extends Camera3D
## La cámara de la cinemática de Mythos (nodo Camera de MythosCinematic.tscn).
## La cinemática le dice dónde aterriza el jefe, de qué lado está la party y
## el radio del anillo de fuego (frame) y después, en cada frame, cuánto
## avanzó la calma y dónde va el fénix (shoot). Con eso arma cuatro planos:
##   COMETA  a ras de suelo, junto al anillo: lo ve bajar del cielo con un
##           teleobjetivo que se abre, hasta que le pasa por al lado
##   ANILLO  una grúa alta: el anillo de fuego entero alrededor de la party
##   CIELO   a ras de suelo, mirando hacia arriba: el ascenso, la picada y
##           el golpe contra el suelo
##   HÉROE   a ras de suelo, girando despacio a su alrededor y acercándose,
##           mirándolo desde abajo
## Al fijar el encuadre prueba varios lados y se queda con el que tiene
## menos árboles, rocas y lomas entre la cámara y el jefe: mide el PASILLO
## que va de la cámara a lo que mira, a la altura de los troncos (la copa de
## un árbol tapa aunque su tronco quede al costado). También tiembla cuando
## la cinemática se lo pide (shake).

enum Shot { COMET, RING, SKY, HERO }

## Lugares que prueban, de a uno, los planos a ras de suelo buscando uno sin
## árboles delante: metros hacia un costado (x) y metros hacia atrás (y).
const OPEN_SPOT_STEPS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(8.0, 0.0),
		Vector2(-8.0, 0.0), Vector2(0.0, 8.0), Vector2(8.0, 8.0), Vector2(-8.0, 8.0),
		Vector2(0.0, -8.0), Vector2(8.0, -8.0), Vector2(-8.0, -8.0), Vector2(16.0, 0.0),
		Vector2(-16.0, 0.0), Vector2(16.0, 8.0), Vector2(-16.0, 8.0), Vector2(16.0, -8.0),
		Vector2(-16.0, -8.0), Vector2(0.0, 16.0), Vector2(8.0, 16.0), Vector2(-8.0, 16.0),
		Vector2(24.0, 0.0), Vector2(-24.0, 0.0), Vector2(24.0, 8.0), Vector2(-24.0, 8.0)]
## El pasillo que tiene que estar libre es una caja a la altura de los
## troncos: metros sobre el suelo de su centro y su alto.
const CORRIDOR_HEIGHT: float = 2.6
const CORRIDOR_THICKNESS: float = 1.4
## Cuánto estorba cada cosa que pisa el pasillo: lo mínimo (lejos), lo que
## suma si está pegada a la cámara y lo que cuenta una loma del terreno.
const CROWD_FAR: float = 0.25
const CROWD_NEAR: float = 1.0
const CROWD_TERRAIN: float = 0.5

@export_group("Plano del cometa")
## Fracción de la calma (0-1) hasta la que dura (un poco después de que entra al anillo: ahí le pasa por al lado).
@export_range(0.0, 1.0) var comet_shot_until: float = 0.245
## Dónde se para la cámara sobre la recta por la que baja, pasado el anillo, en veces el radio del anillo.
@export var comet_ahead: float = 0.75
## Metros hacia afuera del anillo.
@export var comet_outside: float = 5.0
## Altura de la cámara, en metros sobre el punto de llegada.
@export var comet_eye_height: float = 2.6
## Campo de visión al empezar, en grados (cerrado: lo trae de lejos).
@export var comet_fov_start: float = 34.0
## Campo de visión cuando le pasa por al lado, en grados.
@export var comet_fov_end: float = 68.0

@export_group("Plano del anillo")
## Fracción de la calma (0-1) hasta la que dura.
@export_range(0.0, 1.0) var ring_shot_until: float = 0.47
## Distancia de la cámara al punto de llegada, en veces el radio del anillo.
@export var ring_back: float = 1.35
## Altura de la cámara, en veces el radio del anillo.
@export var ring_eye_height: float = 0.8
## Cuánto se corre la mirada desde el centro del anillo hacia la cámara, en veces el radio (así entra el anillo entero).
@export var ring_look_shift: float = 0.25
## Grados que la cámara gira alrededor del punto de llegada durante el plano.
@export var ring_orbit_degrees: float = 16.0
## Cuánto se va la mirada detrás del fénix (0 = fija en el centro del anillo, 1 = lo sigue del todo).
@export_range(0.0, 1.0) var ring_follow: float = 0.25
## Campo de visión, en grados.
@export var ring_fov: float = 62.0

@export_group("Plano del cielo")
## Fracción de la calma (0-1) hasta la que dura (un poco después del golpe).
@export_range(0.0, 1.0) var sky_shot_until: float = 0.725
## Distancia al punto de llegada, en veces el radio del anillo (menos de 1 = desde adentro del anillo, que si no tapa el golpe).
@export var sky_back: float = 0.8
## Metros que la cámara se corre hacia un lado.
@export var sky_side: float = 7.0
## Altura de la cámara, en metros sobre el punto de llegada (por encima de la onda de fuego del golpe).
@export var sky_eye_height: float = 3.0
## Altura mínima a la que mira, en metros sobre el punto de llegada (así el golpe no queda en el borde de abajo).
@export var sky_min_look: float = 5.0
## Campo de visión con el fénix cerca del suelo, en grados.
@export var sky_fov: float = 60.0
## Campo de visión con el fénix en lo alto, en grados (cerrado: se lo ve abrir las alas).
@export var sky_fov_high: float = 32.0
## Altura del fénix, en metros, a la que el plano queda cerrado del todo.
@export var sky_zoom_height: float = 52.0

@export_group("Plano héroe")
## Distancia al jefe al empezar el plano héroe, en metros.
@export var hero_distance_start: float = 20.0
## Distancia al jefe al terminar el plano héroe, en metros.
@export var hero_distance_end: float = 14.0
## Altura de la cámara en el plano héroe, en metros sobre el suelo (baja: lo mira desde abajo).
@export var hero_height: float = 1.8
## Grados que la cámara gira alrededor del jefe durante el plano héroe.
@export var hero_orbit_degrees: float = 44.0
## Grados que el plano héroe se corre hacia un costado de la party (así los raiders no quedan entre la cámara y el jefe).
@export var hero_side_degrees: float = 34.0
## Parte de la altura del jefe a la que mira la cámara en el plano héroe (menos de 1 = el jefe queda arriba en pantalla y deja lugar al cartel).
@export_range(0.2, 1.0) var hero_look_fraction: float = 0.68
## Campo de visión al empezar el plano héroe, en grados.
@export var camera_fov: float = 60.0
## Campo de visión al final del plano héroe, en grados (más cerrado = más imponente).
@export var hero_fov: float = 50.0

@export_group("Vista despejada")
## Grados hacia cada lado que prueba, de a uno, buscando un lado sin árboles en medio.
@export var clear_angles: Array[float] = [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0]
## Capas de física que tapan la vista (1 = suelo y escenografía).
@export_flags_3d_physics var clear_mask: int = 1
## Largo del pasillo sin árboles que buscan delante el plano del cometa y el del cielo, en metros.
@export var open_spot_reach: float = 26.0
## Ancho de los pasillos que se miden, en metros (la copa de un árbol es más ancha que su tronco).
@export var open_spot_width: float = 10.0

@export_group("Lente")
## Rapidez con que la mirada alcanza al fénix en los planos que lo siguen (por segundo).
@export var track_speed: float = 12.0
## Metros mínimos entre la cámara y el suelo.
@export var ground_clearance: float = 1.4

var _boss_point: Vector3 = Vector3.ZERO
var _away: Vector3 = Vector3.BACK
var _radius: float = 30.0
## Dónde se paran el plano del cometa y el del cielo: un lugar sin troncos delante.
var _comet_from: Vector3 = Vector3.ZERO
var _sky_from: Vector3 = Vector3.ZERO
## Hacia qué costado de la party se corre el plano héroe (1 o -1).
var _hero_turn: float = 1.0
## Plano en curso (un valor de Shot; -1 antes del primero).
var _shot: int = -1
## Adónde mira ahora y adónde quiere mirar.
var _look: Vector3 = Vector3.ZERO
var _aim: Vector3 = Vector3.ZERO
var _shake_strength: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 1.0
## Azar propio: el temblor no toca el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Fija el encuadre: `boss_point` es donde aterriza el jefe, `away` la
## dirección desde ahí hacia la party y `ring_radius` el radio del anillo de
## fuego, en metros.
func frame(boss_point: Vector3, away: Vector3, ring_radius: float) -> void:
	_boss_point = boss_point
	_radius = ring_radius
	_hero_turn = _freer_turn(away)
	_away = _clearest_side(away)
	# El cometa llega de frente y pasa hacia el lado del anillo.
	_comet_from = _open_spot(_comet_eye(_away), [-_away, Vector3.UP.cross(_away)])
	_sky_from = _open_spot(_sky_eye(_away), [-_away])
	_shot = -1
	fov = camera_fov
	_shake_left = 0.0
	h_offset = 0.0
	v_offset = 0.0


## El lado desde el que filma (a ras de suelo, desde el jefe): el más despejado.
func side() -> Vector3:
	return _away


## Hacia dónde queda el centro del plano héroe, desde el jefe: hacia ahí mira
## Mythos cuando sale de la columna de fuego.
func hero_side() -> Vector3:
	return _away.rotated(Vector3.UP, deg_to_rad(_hero_turn * hero_side_degrees))


## Tiembla con `strength` (metros de pantalla) durante `seconds`.
func shake(strength: float, seconds: float) -> void:
	_shake_strength = strength
	_shake_total = maxf(seconds, 0.01)
	_shake_left = _shake_total


## Coloca la cámara para el avance `progress` (0-1) de la calma. `bird` es
## dónde va el fénix y `body_height` la altura de su cuerpo sobre el suelo,
## ahora. Devuelve el punto al que mira.
func shoot(progress: float, bird: Vector3, body_height: float, delta: float) -> Vector3:
	var shot := _shot_at(progress)
	var cut := shot != _shot
	_shot = shot
	var from := _boss_point
	match shot:
		Shot.COMET:
			from = _shoot_comet(progress, bird)
		Shot.RING:
			from = _shoot_ring(progress, bird)
		Shot.SKY:
			from = _shoot_sky(bird)
		_:
			from = _shoot_hero(progress, body_height)
	# Los planos que siguen al fénix lo alcanzan de a poco; un corte, de golpe.
	var follows := shot == Shot.COMET or shot == Shot.SKY
	if cut or not follows or delta <= 0.0:
		_look = _aim
	else:
		_look = _look.lerp(_aim, Juice.damp(track_speed, delta))
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		from.y = maxf(from.y, terrain.height_at(from.x, from.z) + ground_clearance)
	look_at_from_position(from, _look)
	_shake_left = maxf(_shake_left - delta, 0.0)
	var jolt := _shake_strength * _shake_left / _shake_total
	h_offset = _rng.randf_range(-jolt, jolt)
	v_offset = _rng.randf_range(-jolt, jolt)
	return _look


# --- planos -----------------------------------------------------------------------

func _shot_at(progress: float) -> Shot:
	if progress < comet_shot_until:
		return Shot.COMET
	if progress < ring_shot_until:
		return Shot.RING
	if progress < sky_shot_until:
		return Shot.SKY
	return Shot.HERO


## Lo sigue mientras baja; el teleobjetivo se abre a medida que se acerca.
func _shoot_comet(progress: float, bird: Vector3) -> Vector3:
	var u := progress / maxf(comet_shot_until, 0.01)
	fov = lerpf(comet_fov_start, comet_fov_end, smoothstep(0.3, 1.0, u))
	_aim = bird
	return _comet_from


## Grúa alta que gira apenas: mira al centro del anillo y un poco al fénix.
func _shoot_ring(progress: float, bird: Vector3) -> Vector3:
	var u := _span(progress, comet_shot_until, ring_shot_until)
	fov = ring_fov
	_aim = (_boss_point + _away * (_radius * ring_look_shift)).lerp(bird, ring_follow)
	var angle := deg_to_rad(lerpf(-0.5, 0.5, u) * ring_orbit_degrees)
	return _boss_point + _away.rotated(Vector3.UP, angle) * (_radius * ring_back) \
			+ Vector3.UP * (_radius * ring_eye_height)


## Desde abajo y desde afuera del anillo: lo sigue al cielo, cerrando el
## plano a medida que sube, y de vuelta al suelo.
func _shoot_sky(bird: Vector3) -> Vector3:
	var high := (bird.y - _boss_point.y) / maxf(sky_zoom_height, 0.01)
	fov = lerpf(sky_fov, sky_fov_high, smoothstep(0.25, 1.0, high))
	_aim = bird
	_aim.y = maxf(_aim.y, _boss_point.y + sky_min_look)
	return _sky_from


## A ras de suelo, girando despacio y acercándose.
func _shoot_hero(progress: float, body_height: float) -> Vector3:
	var u := _span(progress, sky_shot_until, 1.0)
	fov = lerpf(camera_fov, hero_fov, smoothstep(0.0, 1.0, u))
	_aim = _boss_point + Vector3.UP * clampf(body_height, 3.0, 40.0) * hero_look_fraction
	return _hero_eye(_away, u)


## Dónde se para la cámara en cada plano si filma desde el lado `side`.
func _comet_eye(side: Vector3) -> Vector3:
	return _boss_point - Vector3.UP.cross(side) * (_radius + comet_outside) \
			+ side * (_radius * comet_ahead) + Vector3.UP * comet_eye_height


func _sky_eye(side: Vector3) -> Vector3:
	return _boss_point + side * (_radius * sky_back) + Vector3.UP.cross(side) * sky_side \
			+ Vector3.UP * sky_eye_height


func _hero_eye(side: Vector3, u: float) -> Vector3:
	var angle := deg_to_rad(_hero_turn
			* (hero_side_degrees + lerpf(-0.5, 0.5, u) * hero_orbit_degrees))
	return _boss_point + side.rotated(Vector3.UP, angle) \
			* lerpf(hero_distance_start, hero_distance_end, u) + Vector3.UP * hero_height


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


# --- vista despejada --------------------------------------------------------------

## De los lados de clear_angles, el que tiene menos estorbo entre la cámara
## y el punto de llegada en el plano del cielo y en el plano héroe (a
## igualdad, el primero de la lista). Tiene que correr ANTES de congelar el
## mundo: congelada, la escenografía sale de la física y nada la toca.
func _clearest_side(away: Vector3) -> Vector3:
	var terrain := Terrain.find(get_tree())
	var best := away
	var best_crowd := 1000.0
	for degrees: float in clear_angles:
		var side := away.rotated(Vector3.UP, deg_to_rad(degrees))
		var crowd := 0.0
		for eye: Vector3 in _eyes(side):
			var to_boss := _boss_point - eye
			to_boss.y = 0.0
			var ground := terrain.height_at(eye.x, eye.z) if terrain != null else eye.y
			crowd += _crowd(eye, to_boss.normalized(), ground, to_boss.length())
		if crowd < best_crowd:
			best_crowd = crowd
			best = side
		if crowd <= 0.0:
			break
	return best


## De los lugares de OPEN_SPOT_STEPS alrededor de `base`, el que tiene menos
## estorbo en los pasillos que salen hacia cada dirección de `views` (a
## igualdad, el primero). Los pasos se miden respecto de la primera
## dirección. Corre antes de congelar el mundo, igual que _clearest_side.
func _open_spot(base: Vector3, views: Array[Vector3]) -> Vector3:
	var terrain := Terrain.find(get_tree())
	var sideways := Vector3.UP.cross(views[0]).normalized()
	var best := base
	var best_crowd := 1000.0
	for step: Vector2 in OPEN_SPOT_STEPS:
		var eye := base + sideways * step.x - views[0] * step.y
		var ground := terrain.height_at(eye.x, eye.z) if terrain != null else _boss_point.y
		eye.y = maxf(eye.y, ground + ground_clearance)
		var crowd := 0.0
		for view: Vector3 in views:
			crowd += _crowd(eye, view, ground, open_spot_reach)
		if crowd < best_crowd:
			best_crowd = crowd
			best = eye
		if crowd <= 0.0:
			break
	return best


## Cuánto estorba lo que pisa el pasillo de `reach` metros que sale de `eye`
## hacia `view`, a la altura de los troncos sobre el suelo `ground`: cada
## tronco, roca o meseta suma más cuanto más cerca de la cámara está (0 =
## pasillo libre).
func _crowd(eye: Vector3, view: Vector3, ground: float, reach: float) -> float:
	var box := BoxShape3D.new()
	box.size = Vector3(open_spot_width, CORRIDOR_THICKNESS, reach)
	var center := eye + view * (reach * 0.5)
	center.y = ground + CORRIDOR_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = clear_mask
	query.transform = Transform3D(Basis.looking_at(view, Vector3.UP), center)
	var crowd := 0.0
	var seen: Dictionary[int, bool] = {}
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := hit.get("collider") as Node3D
		# Un cuerpo con varias formas (el terreno, una formación) cuenta una vez.
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if body is Terrain:
			crowd += CROWD_TERRAIN
			continue
		var offset := body.global_position - eye
		offset.y = 0.0
		var near := 1.0 - clampf(offset.length() / maxf(reach, 0.01), 0.0, 1.0)
		crowd += CROWD_FAR + CROWD_NEAR * near * near
	return crowd


## Los puntos desde donde la cámara mira al jefe si se para del lado `side`:
## el del plano del cielo y tres del giro del plano héroe.
func _eyes(side: Vector3) -> Array[Vector3]:
	return [_sky_eye(side), _hero_eye(side, 0.0), _hero_eye(side, 0.5), _hero_eye(side, 1.0)]


func _span(value: float, from: float, to: float) -> float:
	return clampf((value - from) / maxf(to - from, 0.0001), 0.0, 1.0)
