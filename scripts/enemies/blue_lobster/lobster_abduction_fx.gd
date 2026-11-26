class_name LobsterAbductionFx
extends Node3D
## EL AGUA de la cinemática de la Langosta Azul (nodo Fx de
## LobsterEntrance.tscn). En el mapa: el agua brota del suelo alrededor de
## cada raider (chorros) y un remolino se cierra sobre él (una pared de agua
## que gira, sube y se achica), con gotas que saltan. En el fondo del mar: las
## burbujas que pasan mientras el equipo cae, la arena que levanta al tocar
## fondo y el estallido con que la langosta sale de la arena.
##
## La cinemática lleva el reloj y lo pasa en cada frame (show_abduction): aquí
## nada corre solo, así una pausa lo detiene todo junto. Los chorros y la
## pared son tramos de agua (un cuadro con water_column.gdshader, el mismo de
## los golpes de la langosta) repartidos en círculo en UN MultiMesh (nodo
## Water). Las partículas (nodos Drops, Bubbles, SandPuff, SandBurst y
## BubbleBurst) se ajustan en la escena; Drops es el molde de las gotas de
## cada raider.

@export_group("Chorros")
## Chorros que brotan alrededor de cada raider.
@export_range(1, 12) var geysers_per_raider: int = 6
## Metros mínimos de un chorro a su raider.
@export var geyser_ring_min: float = 3.2
## Metros máximos de un chorro a su raider.
@export var geyser_ring_max: float = 7.5
## Segundo del rapto en que brota el primer chorro.
@export var geyser_from: float = 0.1
## Segundos que tardan en brotar todos, uno tras otro.
@export var geyser_spread: float = 1.8
## Segundos que tarda un chorro en llegar a su altura.
@export var geyser_rise_seconds: float = 0.28
## Radio de un chorro, en metros.
@export var geyser_radius: float = 0.85
## Altura mínima de un chorro, en metros.
@export var geyser_height_min: float = 5.0
## Altura máxima de un chorro, en metros.
@export var geyser_height_max: float = 10.0
## Tramos de agua de cada chorro.
@export_range(3, 10) var geyser_segments: int = 6
## Sonido de cada chorro al brotar (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var geyser_sfx: StringName = &"abduction_geyser"

@export_group("Remolino")
## Segundo del rapto en que la pared de agua empieza a levantarse.
@export var wall_from: float = 1.5
## Segundo del rapto en que termina de cerrarse.
@export var wall_closed_at: float = 4.6
## Radio de la pared al levantarse, en metros.
@export var wall_radius_open: float = 10.5
## Radio de la pared ya cerrada, en metros.
@export var wall_radius_closed: float = 2.4
## Altura de la pared ya cerrada, en metros.
@export var wall_height: float = 12.0
## Tramos de agua de la pared de cada raider.
@export_range(6, 32) var wall_segments: int = 18
## Vueltas por segundo que da la pared al empezar.
@export var wall_turns_open: float = 0.25
## Vueltas por segundo que da la pared al cerrarse.
@export var wall_turns_closed: float = 0.9
## Grados que cada tramo se inclina hacia donde gira.
@export var wall_lean_degrees: float = 26.0
## Sonido del remolino al levantarse (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var wall_sfx: StringName = &"abduction_whirlpool"

@export_group("Fondo del mar")
## Metros por delante de la cámara donde nacen las burbujas del descenso.
@export var bubbles_ahead: float = 7.0
## Sonido al tocar fondo (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var land_sfx: StringName = &"seabed_landing"

## Dónde brota cada chorro: {at, height, from, turn}.
var _geysers: Array[Dictionary] = []
## Los pies de cada raider.
var _spots: Array[Vector3] = []
var _drops: Array[CPUParticles3D] = []
var _rng := RandomNumberGenerator.new()
var _wall_turn: float = 0.0
var _last_seconds: float = 0.0
var _sounded: int = 0
var _wall_sounded: bool = false

@onready var _water: MultiMeshInstance3D = $Water
@onready var _drops_mold: CPUParticles3D = $Drops
@onready var _bubbles: CPUParticles3D = $Bubbles
@onready var _sand_puff: CPUParticles3D = $SandPuff
@onready var _sand_burst: CPUParticles3D = $SandBurst
@onready var _bubble_burst: CPUParticles3D = $BubbleBurst


func _ready() -> void:
	top_level = true
	_water.visible = false
	_drops_mold.emitting = false
	clear()


# --- el rapto, en el mapa ---------------------------------------------------------

## Prepara el rapto de los raiders parados en `spots` (sus pies).
func begin_abduction(spots: Array[Vector3]) -> void:
	clear()
	_spots = spots
	_rng.seed = 20261123
	_wall_turn = 0.0
	_last_seconds = 0.0
	_sounded = 0
	_wall_sounded = false
	var terrain := Terrain.find(get_tree())
	for spot: Vector3 in spots:
		for index: int in geysers_per_raider:
			var angle := TAU * (float(index) + _rng.randf()) / float(geysers_per_raider)
			var reach := _rng.randf_range(geyser_ring_min, geyser_ring_max)
			var at := spot + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
			if terrain != null:
				at.y = terrain.height_at(at.x, at.z)
			_geysers.append({"at": at, "turn": _rng.randf() * TAU,
					"height": _rng.randf_range(geyser_height_min, geyser_height_max),
					"from": geyser_from + geyser_spread * float(_geysers.size())
							/ float(maxi(spots.size() * geysers_per_raider - 1, 1))})
		var drops := _drops_mold.duplicate() as CPUParticles3D
		add_child(drops)
		drops.global_position = spot
		_drops.append(drops)
	var multimesh := _water.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = _geysers.size() * geyser_segments + spots.size() * wall_segments
	multimesh.custom_aabb = AABB(Vector3(-400.0, -20.0, -400.0), Vector3(800.0, 80.0, 800.0))
	_water.multimesh = multimesh
	_water.visible = true
	show_abduction(0.0)


## Un frame del rapto: lleva `seconds` segundos de su acto.
func show_abduction(seconds: float) -> void:
	if _spots.is_empty():
		return
	var multimesh := _water.multimesh
	var slot := 0
	for index: int in _geysers.size():
		var geyser := _geysers[index]
		var grown := clampf((seconds - float(geyser["from"])) / maxf(geyser_rise_seconds, 0.01),
				0.0, 1.0)
		if grown > 0.0 and index >= _sounded:
			_sounded = index + 1
			Sfx.play(geyser_sfx)
		# Sale disparado y frena al llegar arriba.
		var eased := 1.0 - (1.0 - grown) * (1.0 - grown)
		slot = _place_ring(multimesh, slot, geyser["at"], geyser_radius * (0.5 + 0.5 * eased),
				float(geyser["height"]) * eased, geyser_segments, float(geyser["turn"]), 0.0)
	var closing := clampf((seconds - wall_from) / maxf(wall_closed_at - wall_from, 0.01), 0.0, 1.0)
	if closing > 0.0 and not _wall_sounded:
		_wall_sounded = true
		Sfx.play(wall_sfx)
	_wall_turn += (seconds - _last_seconds) * TAU * lerpf(wall_turns_open, wall_turns_closed, closing)
	_last_seconds = seconds
	var eased_close := smoothstep(0.0, 1.0, closing)
	for spot: Vector3 in _spots:
		slot = _place_ring(multimesh, slot, spot,
				lerpf(wall_radius_open, wall_radius_closed, eased_close),
				wall_height * sqrt(closing), wall_segments, _wall_turn,
				deg_to_rad(wall_lean_degrees))
	for drops: CPUParticles3D in _drops:
		drops.emitting = seconds >= geyser_from


## El mapa deja de verse: el agua del rapto se va.
func end_abduction() -> void:
	_water.visible = false
	for drops: CPUParticles3D in _drops:
		drops.queue_free()
	_drops.clear()
	_geysers.clear()
	_spots.clear()


# --- el fondo del mar ---------------------------------------------------------------

## Enciende o apaga las burbujas que pasan mientras el equipo cae.
func set_descent(on: bool) -> void:
	_bubbles.emitting = on


## Un frame del descenso: las burbujas nacen por delante de `camera`.
func follow(camera: Camera3D) -> void:
	_bubbles.global_position = camera.global_position - camera.global_basis.z * bubbles_ahead


## El equipo toca fondo en `at`: la arena se levanta.
func land(at: Vector3) -> void:
	_burst(_sand_puff, at)
	Sfx.play(land_sfx)


## La langosta sale de la arena en `at`.
func erupt(at: Vector3) -> void:
	_burst(_sand_burst, at)
	_burst(_bubble_burst, at)


## Apaga todo ya (la cinemática terminó o la partida se va).
func clear() -> void:
	end_abduction()
	for particles: CPUParticles3D in [_bubbles, _sand_puff, _sand_burst, _bubble_burst]:
		particles.emitting = false


# --- privados ---------------------------------------------------------------------

func _burst(particles: CPUParticles3D, at: Vector3) -> void:
	particles.global_position = at
	particles.restart()
	particles.emitting = true


## Reparte `count` tramos de agua en círculo alrededor de `at`, a partir del
## lugar `slot` del MultiMesh: un anillo de `radius` metros y `height` de
## alto, girado `turn` radianes y con cada tramo inclinado `lean` radianes
## hacia donde gira. Con altura 0 los tramos no se ven. Devuelve el lugar
## que sigue.
func _place_ring(multimesh: MultiMesh, slot: int, at: Vector3, radius: float, height: float,
		count: int, turn: float, lean: float) -> int:
	if height <= 0.01:
		for index: int in count:
			multimesh.set_instance_transform(slot + index, Transform3D(Basis.from_scale(
					Vector3.ONE * 0.0001), at))
		return slot + count
	var width := TAU * radius / float(count) * 1.35
	for index: int in count:
		var angle := turn + TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		var up := (Vector3.UP + tangent * tan(lean)).normalized() if lean != 0.0 else Vector3.UP
		multimesh.set_instance_transform(slot + index, Transform3D(
				Basis(tangent * width, up * height, outward),
				at + outward * radius + up * height * 0.5))
	return slot + count
