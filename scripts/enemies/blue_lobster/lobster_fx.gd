class_name LobsterFx
extends Node
## Los EFECTOS de los golpes de la Langosta Azul (nodo Fx de BlueLobster.tscn).
## Los ataques dicen QUÉ pasó y dónde (un pinzazo, el remate, la caída del
## Salto, una réplica, una salida de la Emboscada, por dónde pasó embistiendo
## o cavando, el barrido de la cola); aquí se decide qué se ve: chorros de
## agua (WaterBurst), ondas en el suelo (ImpactRipple), medialunas (SlashArc)
## y salpicones de arena (SplashBurst). Todo sale de Pools y se va solo; nada
## de esto daña a nadie.
## Los tamaños de chorro van como (radio, alto) en metros.

@export_group("Escenas")
## Chorro de agua (WaterBurst). Vacío = sin chorros.
@export var burst_scene: PackedScene = preload("res://scenes/fx/WaterBurst.tscn")
## Onda en el suelo (ImpactRipple). Vacío = sin ondas.
@export var ripple_scene: PackedScene = preload("res://scenes/fx/ImpactRipple.tscn")
## Salpicón de arena y gotas (SplashBurst). Vacío = sin salpicones.
@export var splash_scene: PackedScene = preload("res://scenes/fx/SplashBurst.tscn")

@export_group("Colores")
## Color de la onda que deja cada golpe en el suelo.
@export var ripple_color: Color = Color(1.0, 0.4, 0.42)
## Color de las medialunas (las pinzas que se cierran, el remolino de la cola).
@export var arc_color: Color = Color(1.0, 0.84, 0.88)

@export_group("Tenazas")
## Chorro de cada pinzazo (radio, alto).
@export var snap_burst: Vector2 = Vector2(0.8, 3.4)
## Tamaño del salpicón de cada pinzazo (1 = el de la escena).
@export var snap_splash: float = 0.8
## Segundos que tardan en cerrarse las dos medialunas de la pinza.
@export var snap_arc_seconds: float = 0.2
## Grados que barre cada medialuna al cerrarse.
@export var snap_arc_degrees: float = 150.0
## Chorro de cada pinza en el remate (radio, alto).
@export var slam_burst: Vector2 = Vector2(1.5, 7.5)
## Tamaño del salpicón de cada pinza en el remate.
@export var slam_splash: float = 1.6

@export_group("Salto")
## Chorro al despegar (radio, alto).
@export var takeoff_burst: Vector2 = Vector2(1.1, 3.6)
## Chorro de la caída (radio, alto).
@export var landing_burst: Vector2 = Vector2(2.6, 12.0)
## Tamaño del salpicón de la caída.
@export var landing_splash: float = 2.6
## Chorro de cada réplica (radio, alto).
@export var aftershock_burst: Vector2 = Vector2(1.5, 5.5)
## Tamaño del salpicón de cada réplica.
@export var aftershock_splash: float = 1.2

@export_group("Corona")
## Chorros chicos que brotan en corona alrededor de un golpe demoledor (la caída del Salto, la última salida de la Emboscada). 0 = sin corona.
@export var crown_count: int = 9
## A qué fracción del radio del golpe brotan (0-1).
@export_range(0.1, 1.5) var crown_at: float = 0.72
## Chorro de cada uno (radio, alto).
@export var crown_burst: Vector2 = Vector2(0.7, 5.0)
## Segundos entre el golpe y el primer chorro de la corona, y entre cada chorro y el siguiente.
@export var crown_delay: float = 0.06
@export var crown_step: float = 0.018

@export_group("Embestida")
## Metros entre un chorro y el siguiente en la estela.
@export var charge_wake_spacing: float = 2.4
## Metros a cada lado del cuerpo donde brotan (alternan de lado).
@export var charge_wake_side: float = 1.7
## Chorro de la estela (radio, alto).
@export var charge_wake_burst: Vector2 = Vector2(0.6, 3.0)
## Chorro cuando la embestida le da a un raider (radio, alto).
@export var charge_hit_burst: Vector2 = Vector2(1.0, 3.6)
## Chorro del derrape al final de cada pasada (radio, alto).
@export var skid_burst: Vector2 = Vector2(1.1, 3.2)
## Tamaño del salpicón del derrape.
@export var skid_splash: float = 1.2

@export_group("Coletazo")
## Medialunas que giran con la cola en cada giro.
@export var sweep_arcs: int = 3
## Metros sobre el suelo a los que pasan las medialunas (las del Coletazo y las de las Tenazas).
@export var arc_height: float = 0.8

@export_group("Emboscada")
## Tamaño del salpicón al enterrarse.
@export var dig_splash: float = 1.3
## Metros entre un borbotón y el siguiente sobre el túnel.
@export var tunnel_wake_spacing: float = 2.0
## Borbotón del túnel (radio, alto).
@export var tunnel_wake_burst: Vector2 = Vector2(0.45, 1.5)
## Tamaño del salpicón de cada borbotón del túnel.
@export var tunnel_wake_splash: float = 0.45
## Chorro de cada salida (radio, alto).
@export var eruption_burst: Vector2 = Vector2(1.7, 7.5)
## Tamaño del salpicón de cada salida.
@export var eruption_splash: float = 2.0
## Chorro de la última salida (radio, alto).
@export var final_eruption_burst: Vector2 = Vector2(2.7, 12.5)
## Tamaño del salpicón de la última salida.
@export var final_eruption_splash: float = 3.2

## Metros que faltan para el próximo chorro de la estela en curso, y de qué lado va.
var _wake_left: float = 0.0
var _wake_side: float = 1.0
## Chorros que salen un instante después: cada entrada es [segundos, punto, tamaño].
var _later: Array[Array] = []

@onready var _boss: LobsterBody = get_parent() as LobsterBody


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	for index: int in range(_later.size() - 1, -1, -1):
		var entry := _later[index]
		entry[0] = float(entry[0]) - delta
		if float(entry[0]) <= 0.0:
			_later.remove_at(index)
			_burst(entry[1], entry[2])
	if _later.is_empty():
		set_process(false)


# --- lo que dicen los ataques -----------------------------------------------------

## El ataque en curso se cortó: lo que iba a brotar un instante después ya no sale.
func clear() -> void:
	_later.clear()
	set_process(false)


## Un pinzazo cerró en `mark` (radio `radius`), viniendo desde `toward`: las
## dos mandíbulas de la pinza se cierran sobre el disco.
func snap(mark: Vector3, radius: float, toward: Vector3) -> void:
	_ripple(mark, radius)
	_burst(mark, snap_burst)
	_splash(mark, snap_splash)
	var side := Vector3(-toward.z, 0.0, toward.x)
	_arc(mark, side, radius, snap_arc_degrees, snap_arc_seconds, false)
	_arc(mark, -side, radius, snap_arc_degrees, snap_arc_seconds, true)


## El remate: las dos pinzas bajaron sobre `spots` (radio `radius` cada una).
func slam(spots: Array[Vector3], radius: float) -> void:
	for spot: Vector3 in spots:
		_ripple(spot, radius)
		_burst(spot, slam_burst)
		_splash(spot, slam_splash)


## Despegó del suelo en `at` para el Salto.
func takeoff(at: Vector3) -> void:
	_burst(at, takeoff_burst)
	_splash(at, 1.0)


## Cayó del Salto en `at`, con un golpe de `radius` metros.
func landing(at: Vector3, radius: float) -> void:
	_ripple(at, radius)
	_burst(at, landing_burst)
	_splash(at, landing_splash)
	_crown(at, radius)


## Una réplica del Salto en `at`.
func aftershock(at: Vector3, radius: float) -> void:
	_ripple(at, radius * 0.6)
	_burst(at, aftershock_burst)
	_splash(at, aftershock_splash)


## Empieza una pasada de la Embestida: la estela arranca de cero.
func charge_started() -> void:
	_wake_left = 0.0


## Embistiendo, el cuerpo pasó de `from` a `to`: va dejando una estela de
## chorros a los lados.
func charge_trail(from: Vector3, to: Vector3) -> void:
	_trail(from, to, charge_wake_spacing, charge_wake_side, charge_wake_burst, 0.0)


## La embestida le dio a un raider en `at`.
func charge_hit(at: Vector3) -> void:
	_burst(at, charge_hit_burst)
	_ripple(at, charge_hit_burst.x * 2.5)


## Derrapó al final de una pasada, en `at`.
func skid(at: Vector3) -> void:
	_burst(at, skid_burst)
	_splash(at, skid_splash)


## La cola empieza a barrer `radius` metros alrededor de `center`, en
## `seconds` segundos: unas medialunas giran con ella.
func sweep(center: Vector3, radius: float, clockwise: bool, seconds: float) -> void:
	var count := maxi(sweep_arcs, 0)
	for index: int in count:
		var heading := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / float(count))
		_arc(center, heading, radius, 360.0, seconds, clockwise)


## La cola golpeó: el barrido llegó hasta `radius` metros de `center`.
func sweep_hit(center: Vector3, radius: float) -> void:
	_ripple(center, radius)


## Se entierra en `at`.
func dig(at: Vector3) -> void:
	_splash(at, dig_splash)
	_ripple(at, 2.0)


## Bajo tierra, el cuerpo pasó de `from` a `to`: el suelo borbotea encima.
func tunnel_trail(from: Vector3, to: Vector3) -> void:
	_trail(from, to, tunnel_wake_spacing, 0.0, tunnel_wake_burst, tunnel_wake_splash)


## Salió de la tierra en `at` con un golpe de `radius` metros; `final` si es
## la última salida de la cadena (la grande).
func eruption(at: Vector3, radius: float, final: bool) -> void:
	_ripple(at, radius)
	_burst(at, final_eruption_burst if final else eruption_burst)
	_splash(at, final_eruption_splash if final else eruption_splash)
	if final:
		_crown(at, radius)


# --- privados ---------------------------------------------------------------------

func _burst(at: Vector3, size: Vector2) -> void:
	WaterBurst.spawn(burst_scene, at, size.x, size.y)


func _ripple(at: Vector3, radius: float) -> void:
	ImpactRipple.spawn(ripple_scene, at, radius, ripple_color)


func _splash(at: Vector3, size: float) -> void:
	SplashBurst.spawn(splash_scene, at, size)


## Una medialuna que barre `degrees` grados alrededor de `center`, a `radius`
## metros, partiendo centrada hacia `heading`.
func _arc(center: Vector3, heading: Vector3, radius: float, degrees: float, seconds: float,
		mirror: bool) -> void:
	var arc := Pools.acquire_scene(Pools.SLASH_ARC_SCENE) as SlashArc
	if arc != null:
		arc.play(center + Vector3.UP * arc_height, heading, radius, arc_color, degrees,
				seconds, mirror)


## Una corona de chorros chicos alrededor de `at`, uno detrás del otro.
func _crown(at: Vector3, radius: float) -> void:
	var count := maxi(crown_count, 0)
	for index: int in count:
		var angle := TAU * float(index) / float(count)
		var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * radius * crown_at
		_later.append([crown_delay + crown_step * float(index), _on_floor(spot), crown_burst])
	if count > 0:
		set_process(true)


## Deja un chorro cada `spacing` metros del tramo recorrido, a `side` metros
## del cuerpo, alternando de lado.
func _trail(from: Vector3, to: Vector3, spacing: float, side: float, burst: Vector2,
		splash: float) -> void:
	var step := to - from
	step.y = 0.0
	var length := step.length()
	if length < 0.001:
		return
	_wake_left -= length
	if _wake_left > 0.0:
		return
	_wake_left = maxf(spacing, 0.2)
	var along := step / length
	var at := _on_floor(to + Vector3(-along.z, 0.0, along.x) * side * _wake_side)
	_wake_side = -_wake_side
	_burst(at, burst)
	if splash > 0.0:
		_splash(at, splash)


func _on_floor(point: Vector3) -> Vector3:
	return _boss.floor_point(point) if _boss != null else point
