class_name GroundCover
extends Node3D
## La vegetación baja del suelo de una arena: arbustos, matas de pasto,
## flores, hongos, piedras chicas y helechos, para que el suelo no sea un
## césped liso.
## No tiene colisión: nadie tropieza con una flor.
##
## Va como hija del scatter de la arena (así arde con el bosque en el
## infierno de Mythos). Parte el mapa en trozos de `chunk_size` metros y
## arma UNA malla por trozo (LowPolyMesh, color de vértice), unos pocos
## trozos por frame desde que empieza la etapa: armar todo de una vez sería
## un tirón al cargar el mapa.
##
## Cada trozo se siembra con la semilla de partida del scatter y su lugar en
## la cuadrícula: la misma semilla da la misma vegetación, y no saca ni un
## número del RNG de la partida.

## Grupo de este nodo: el harness lo salta al revisar props.
const GROUP: StringName = &"ground_cover"

@export_group("Reparto")
## Lado de cada trozo, en metros: una malla por trozo.
@export var chunk_size: float = 20.0
## Trozos que se arman por frame.
@export_range(1, 64) var chunks_per_frame: int = 6
## Metros que la vegetación guarda con un corte, una rampa o un puente.
@export var relief_clearance: float = 2.0
## Metros libres de vegetación alrededor del punto de aparición.
@export var spawn_clearance: float = 4.0

@export_group("Cantidades (por trozo)")
## Arbustos por trozo.
@export var bushes: int = 4
## Matas de pasto por trozo.
@export var tufts: int = 22
## Manchones de flores por trozo.
@export var flower_patches: int = 3
## Grupos de hongos por trozo.
@export var mushroom_groups: int = 1
## Grupos de piedras chicas por trozo.
@export var pebble_groups: int = 2
## Helechos por trozo.
@export var ferns: int = 6

@export_group("Tamaños")
## Radio mínimo de un arbusto, en metros.
@export var bush_radius_min: float = 0.45
## Radio máximo de un arbusto, en metros.
@export var bush_radius_max: float = 0.95
## Alto mínimo de una mata de pasto, en metros.
@export var tuft_height_min: float = 0.45
## Alto máximo de una mata de pasto, en metros.
@export var tuft_height_max: float = 1.0
## Alto de una flor, en metros.
@export var flower_height: float = 0.42
## Alto máximo del sombrero de un hongo sobre el suelo, en metros.
@export var mushroom_height: float = 0.7
## Largo mínimo de una hoja de helecho, en metros.
@export var fern_reach_min: float = 0.8
## Largo máximo de una hoja de helecho, en metros.
@export var fern_reach_max: float = 1.5

@export_group("Colores")
## Verde oscuro de los arbustos.
@export var bush_dark: Color = Color(0.15, 0.45, 0.25)
## Verde claro de los arbustos.
@export var bush_bright: Color = Color(0.3, 0.63, 0.33)
## Verde de las matas de pasto.
@export var tuft_color: Color = Color(0.36, 0.64, 0.33)
## Colores de las flores: cada manchón toma uno.
@export var flower_colors: Array[Color] = [Color(0.96, 0.95, 0.88), Color(0.98, 0.82, 0.28),
		Color(0.93, 0.48, 0.62), Color(0.62, 0.5, 0.9)]
## Colores del sombrero de los hongos: cada grupo toma uno.
@export var mushroom_caps: Array[Color] = [Color(0.8, 0.2, 0.16), Color(0.92, 0.55, 0.18)]
## Color del pie de los hongos.
@export var mushroom_stem: Color = Color(0.9, 0.87, 0.78)
## Color de las piedras chicas.
@export var pebble_color: Color = Color(0.5, 0.52, 0.54)
## Verde de los helechos.
@export var fern_color: Color = Color(0.2, 0.52, 0.3)

var _terrain: Terrain = null
var _bounds: Node = null
var _half: float = 0.0
var _per_side: int = 0
var _next: int = 0
var _seed: int = 0
var _faces: int = 0
var _spent_usec: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	# Ajuste del jugador (Ajustes > Pasto y piedras).
	visible = SaveData.show_ground_cover
	set_process(false)
	# El scatter coloca sus props y las estructuras del relieve en
	# Arena._ready, después de este _ready: se empieza un frame más tarde.
	_begin.call_deferred()


func _begin() -> void:
	_terrain = Terrain.find(get_tree())
	_bounds = get_parent()
	if _terrain == null or _bounds == null or not _bounds.has_method(&"can_grow"):
		return
	_half = _terrain.size * 0.5
	_per_side = ceili(_terrain.size / chunk_size)
	_seed = int(_bounds.call(&"run_seed")) if _bounds.has_method(&"run_seed") else 0
	set_process(true)


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	for step in chunks_per_frame:
		if _next >= _per_side * _per_side:
			break
		_build_chunk(_next % _per_side, _next / _per_side)
		_next += 1
	_spent_usec += Time.get_ticks_usec() - started
	if _next >= _per_side * _per_side:
		set_process(false)
		print("Ground cover: %d chunks, %d faces in %d ms" % [get_child_count(), _faces,
				_spent_usec / 1000])


## Arma la malla del trozo (cx, cz) de la cuadrícula.
func _build_chunk(cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed ^ (cx * 73856093) ^ (cz * 19349663) ^ 0x436F7672
	var mesh := LowPolyMesh.new(rng.randi())
	var corner := Vector2(-_half + float(cx) * chunk_size, -_half + float(cz) * chunk_size)
	for index in bushes:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_bush(mesh, rng, at)
	for index in tufts:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_tuft(mesh, rng, at)
	for index in flower_patches:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_flowers(mesh, rng, at)
	for index in mushroom_groups:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_mushrooms(mesh, rng, at)
	for index in pebble_groups:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_pebbles(mesh, rng, at)
	for index in ferns:
		var at := _spot(rng, corner)
		if at != Vector3.INF:
			_add_fern(mesh, rng, at)
	if mesh.is_empty():
		return
	_faces += mesh.face_count()
	var view := mesh.instance("Cover_%d_%d" % [cx, cz])
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


## Un punto al azar del trozo que empieza en `corner`, apoyado en el suelo,
## o Vector3.INF si ahí no va vegetación: roca, un corte, una rampa, un
## puente, el fondo del cañón, una estructura o el claro del spawn.
func _spot(rng: RandomNumberGenerator, corner: Vector2) -> Vector3:
	var xz := corner + Vector2(rng.randf(), rng.randf()) * chunk_size
	if xz.length() < spawn_clearance or not bool(_bounds.call(&"can_grow", xz, relief_clearance)):
		return Vector3.INF
	if _terrain.relief_layout() != null and _terrain.relief_layout().level_at(xz) < 0:
		return Vector3.INF
	return Vector3(xz.x, _terrain.height_at(xz.x, xz.y), xz.y)


## `at` corrido hasta `reach` metros en el plano y vuelto a apoyar en el suelo.
func _near(rng: RandomNumberGenerator, at: Vector3, reach: float) -> Vector3:
	var x := at.x + rng.randf_range(-reach, reach)
	var z := at.z + rng.randf_range(-reach, reach)
	return Vector3(x, _terrain.height_at(x, z), z)


## Un arbusto: dos o tres bultos de hojas pegados, de distinto tamaño.
func _add_bush(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	var radius := rng.randf_range(bush_radius_min, bush_radius_max)
	for lump in rng.randi_range(2, 3):
		var center := _near(rng, at, radius * 0.7 * float(lump)) + Vector3.UP * radius * 0.5
		mesh.blob(center, Vector3(radius, radius * rng.randf_range(0.7, 0.95), radius),
				bush_dark.lerp(bush_bright, rng.randf()), 6, 3, 0.22)
		radius *= rng.randf_range(0.6, 0.85)


## Una mata: hojas en punta que se abren desde un mismo pie.
func _add_tuft(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	var height := rng.randf_range(tuft_height_min, tuft_height_max)
	var turn := rng.randf() * TAU
	for blade in 4:
		var angle := turn + TAU * float(blade) / 4.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * 0.09
		var tip := at + out * height * 0.55 + Vector3.UP * height
		mesh.triangle(at + side, at - side, tip, tuft_color, at + Vector3.DOWN)


## Un manchón de flores de un mismo color: un rombo sobre un tallo invisible.
func _add_flowers(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	var color := flower_colors[rng.randi() % flower_colors.size()]
	for flower in rng.randi_range(6, 10):
		var foot := _near(rng, at, 1.3)
		var head := foot + Vector3.UP * flower_height * rng.randf_range(0.7, 1.2)
		var size := rng.randf_range(0.13, 0.21)
		var turn := rng.randf() * TAU
		var a := head + Vector3(cos(turn), 0.0, sin(turn)) * size
		var b := head + Vector3(cos(turn + TAU / 3.0), 0.0, sin(turn + TAU / 3.0)) * size
		var c := head + Vector3(cos(turn + TAU * 2.0 / 3.0), 0.0, sin(turn + TAU * 2.0 / 3.0)) * size
		mesh.triangle(a, b, c, color, head + Vector3.DOWN)
		# El tallo: una hoja fina del pie a la flor.
		mesh.triangle(foot, a, b, tuft_color, (foot + c) * 0.5)


## Un grupo de hongos: pie claro y sombrero de color.
func _add_mushrooms(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	var cap := mushroom_caps[rng.randi() % mushroom_caps.size()]
	for mushroom in rng.randi_range(2, 3):
		var foot := _near(rng, at, 0.7)
		var height := mushroom_height * rng.randf_range(0.45, 1.0)
		var width := height * rng.randf_range(0.55, 0.8)
		var lower := mesh.ring(foot + Vector3.DOWN * 0.1, width * 0.2, 4, rng.randf() * TAU)
		var upper := mesh.ring(foot + Vector3.UP * height * 0.75, width * 0.16, 4, rng.randf() * TAU)
		mesh.band(lower, upper, mushroom_stem)
		var brim := mesh.ring(foot + Vector3.UP * height * 0.7, width, 5, rng.randf() * TAU, 0.08)
		var top := foot + Vector3.UP * height
		for index in brim.size():
			mesh.triangle(top, brim[index], brim[(index + 1) % brim.size()], cap,
					foot + Vector3.UP * height * 0.5)


func _add_pebbles(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	for pebble in rng.randi_range(2, 3):
		var radius := rng.randf_range(0.14, 0.34)
		var center := _near(rng, at, 0.8) + Vector3.UP * radius * 0.2
		mesh.blob(center, Vector3(radius, radius * 0.6, radius * rng.randf_range(0.7, 1.0)),
				pebble_color, 4, 3, 0.2)


## Un helecho: un abanico de hojas que suben, se abren y caen en la punta.
func _add_fern(mesh: LowPolyMesh, rng: RandomNumberGenerator, at: Vector3) -> void:
	var fronds := rng.randi_range(5, 7)
	var turn := rng.randf() * TAU
	var tone := fern_color.lerp(bush_bright, rng.randf_range(0.0, 0.45))
	for frond in fronds:
		var angle := turn + TAU * (float(frond) + rng.randf_range(-0.2, 0.2)) / float(fronds)
		var reach := rng.randf_range(fern_reach_min, fern_reach_max)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var bend := at + out * reach * 0.5 + Vector3.UP * reach * 0.55
		var tip := at + out * reach + Vector3.UP * reach * 0.22
		var below := bend + Vector3.DOWN
		mesh.quad(at + side * 0.05, at - side * 0.05, bend - side * reach * 0.2,
				bend + side * reach * 0.2, tone, below)
		mesh.triangle(bend + side * reach * 0.2, bend - side * reach * 0.2, tip, tone, below)
