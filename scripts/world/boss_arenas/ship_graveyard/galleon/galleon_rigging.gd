class_name GalleonRigging
extends RefCounted
## Arma el aparejo y los herrajes de un GalleonWreck: los mástiles (uno en pie
## con su verga y jirones de vela, otro caído sobre la arena), la roda y el
## bauprés de la proa, el timón de la popa y las portas con sus cañones. Lo crea GalleonWreck con
## .new(); los valores que se ajustan son exports de GalleonWreck, que esta
## clase lee del barco que recibe.

## Dónde se plantan los mástiles, en fracción del largo: el primero en pie, el segundo caído.
const MAST_SPOTS_STERN: Array[float] = [0.36, 0.6]
const MAST_SPOTS_BOW: Array[float] = [0.42, 0.2]
## Lados de los palos (mástiles, vergas, cañones).
const POLE_SIDES: int = 6
## Metros que el pie de un mástil baja dentro del casco.
const MAST_FOOT_DEPTH: float = 2.0
## Metros del mástil caído que quedan por dentro de la borda donde se apoya.
const FALLEN_OVERHANG: float = 1.5
## Metros que la punta del mástil caído se hunde en la arena.
const FALLEN_SINK: float = 0.2
## Astillas en la punta de un palo quebrado.
const SPLINTERS: int = 3
## Cuánto se mecen los jirones de vela hacia los lados, en metros.
const RAG_SWAY: float = 0.8
## Alto de las portas, en fracción del alto del casco.
const PORT_HEIGHT: float = 0.66
## Hasta qué fracción del largo llegan las portas.
const PORT_END: float = 0.86

var _wreck: GalleonWreck
var _mesh: LowPolyMesh
var _rng: RandomNumberGenerator


## `wreck` da las medidas y los colores; `mesh` recibe las caras; `rng` es el
## generador del barco, así la misma semilla da el mismo aparejo.
func _init(wreck: GalleonWreck, mesh: LowPolyMesh, rng: RandomNumberGenerator) -> void:
	_wreck = wreck
	_mesh = mesh
	_rng = rng


## Los mástiles del barco: el primero en pie, el segundo caído.
func build_masts() -> void:
	var spots := MAST_SPOTS_STERN if _wreck.half == GalleonWreck.Half.STERN else MAST_SPOTS_BOW
	for i in mini(_wreck.mast_count, spots.size()):
		var x := _wreck.length * spots[i]
		var foot := Vector3(x, _wreck.shape_at(x).z - _wreck.deck_drop, 0.0)
		if i == 0:
			_standing_mast(foot)
		else:
			_fallen_mast(foot)


## La roda que sube en punta y el bauprés quebrado.
func build_bow() -> void:
	var length := _wreck.length
	var shape := _wreck.shape_at(length)
	pole(Vector3(length - 0.3, shape.y + 0.2, 0.0),
			Vector3(length + 0.6, shape.z + _wreck.stem_rise, 0.0), 0.35, 0.25,
			_wreck.dark_plank, false)
	var foot_x := length - 2.0
	var foot := Vector3(foot_x, _wreck.shape_at(foot_x).z + 0.2, 0.0)
	var angle := deg_to_rad(_wreck.bowsprit_angle)
	pole(foot, foot + Vector3(cos(angle), sin(angle), 0.0) * _wreck.bowsprit_length, 0.35, 0.25,
			_wreck.dark_plank, true)


## El timón partido de la popa, girado de costado, con sus dos herrajes.
func build_rudder() -> void:
	var length := _wreck.length
	var shape := _wreck.shape_at(length)
	var height := _wreck.hull_height * _rng.randf_range(0.45, 0.65)
	var turn := Basis(Vector3.UP, deg_to_rad(_rng.randf_range(-25.0, 25.0)))
	var hinge := Vector3(length, shape.y + height * 0.5 - 0.3, 0.0)
	_mesh.block(Transform3D(turn, hinge + turn * Vector3(0.75, 0.0, 0.0)),
			Vector3(1.5, height, 0.35), _wreck.rot_plank)
	for strap: float in [-0.3, 0.3]:
		_mesh.block(Transform3D(turn, hinge + Vector3.UP * height * strap),
				Vector3(0.5, 0.25, 0.5), _wreck.iron_color)


## Portas oscuras en ambos costados, con algún cañón asomando.
func build_gun_ports() -> void:
	var count := _wreck.gun_ports
	if count <= 0:
		return
	var first := _wreck.break_ragged + 1.5
	var last := _wreck.length * PORT_END
	var half_size := _wreck.port_size * 0.5
	for side: float in [-1.0, 1.0]:
		var cannons: Array[int] = []
		for c in mini(_wreck.cannon_count, count):
			cannons.append(_rng.randi() % count)
		for p in count:
			var x := lerpf(first, last, (float(p) + 0.5) / float(count))
			var shape := _wreck.shape_at(x)
			var dh := half_size / (shape.z - shape.y)
			var lift := Vector3(0.0, 0.0, side * GalleonWreck.PANEL_LIFT)
			var centre := _wreck.surface_point(x, PORT_HEIGHT, side)
			_mesh.plate(_wreck.surface_point(x - half_size, PORT_HEIGHT - dh, side) + lift,
					_wreck.surface_point(x + half_size, PORT_HEIGHT - dh, side) + lift,
					_wreck.surface_point(x + half_size, PORT_HEIGHT + dh, side) + lift,
					_wreck.surface_point(x - half_size, PORT_HEIGHT + dh, side) + lift,
					_wreck.opening_color, Vector3(x, centre.y, 0.0))
			if cannons.has(p):
				_cannon(centre, side)


## Una viga de sección `size` (ancho, grueso) entre `a` y `b`.
func beam(a: Vector3, b: Vector3, size: Vector2, color: Color) -> void:
	var span := (b - a).length()
	if span < 0.01:
		return
	var along := (b - a) / span
	var helper := Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.UP
	var across := helper.cross(along).normalized()
	var basis := Basis(along.cross(across), along, across)
	_mesh.block(Transform3D(basis, (a + b) * 0.5), Vector3(size.x, span + size.y, size.y), color)


## Un palo de `a` (radio `r0`) a `b` (radio `r1`); `splinter` le deja astillas en la punta.
func pole(a: Vector3, b: Vector3, r0: float, r1: float, color: Color, splinter: bool) -> void:
	var axis := (b - a).normalized()
	var helper := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(helper).normalized()
	var v := axis.cross(u)
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for index in POLE_SIDES:
		var angle := TAU * float(index) / float(POLE_SIDES)
		var spoke := u * cos(angle) + v * sin(angle)
		lower.append(a + spoke * r0)
		upper.append(b + spoke * r1)
	_mesh.band(lower, upper, color)
	_mesh.cap(lower, color, a + axis * r0)
	_mesh.cap(upper, color, b - axis * r1)
	if not splinter:
		return
	for n in SPLINTERS:
		var index := _rng.randi() % POLE_SIDES
		var p := upper[index]
		var q := upper[(index + 1) % POLE_SIDES]
		var tip := (p + q) * 0.5 + axis * r1 * _rng.randf_range(1.5, 3.5)
		var inside := (p + q + b + tip) * 0.25
		_mesh.triangle(p, q, tip, color, inside)
		_mesh.triangle(q, b, tip, color, inside)
		_mesh.triangle(b, p, tip, color, inside)


## El mástil en pie: quebrado arriba, con su cofa, su verga y jirones de vela.
func _standing_mast(foot: Vector3) -> void:
	var w := _wreck
	var height := _rng.randf_range(w.mast_height_min, w.mast_height_max)
	var top := foot + Vector3(_rng.randf_range(-0.4, 0.4), height, _rng.randf_range(-0.4, 0.4))
	pole(foot + Vector3.DOWN * MAST_FOOT_DEPTH, top, w.mast_radius, w.mast_radius * 0.7,
			w.dark_plank, true)
	_mesh.block(Transform3D(Basis.IDENTITY, foot.lerp(top, 0.55)), Vector3(2.6, 0.4, 2.6),
			w.dark_plank)
	var droop := w.yard_droop * _rng.randf_range(0.5, 1.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var middle := foot.lerp(top, 0.78)
	var end_a := middle + Vector3(0.0, droop * 0.5, -w.yard_length * 0.5)
	var end_b := middle + Vector3(0.0, -droop * 0.5, w.yard_length * 0.5)
	pole(end_a, end_b, 0.22, 0.16, w.dark_plank, false)
	for n in w.sail_rags:
		var s0 := _rng.randf_range(0.05, 0.8)
		var s1 := minf(s0 + _rng.randf_range(0.1, 0.22), 0.97)
		_rag(end_a.lerp(end_b, s0) + Vector3.DOWN * 0.2, end_a.lerp(end_b, s1) + Vector3.DOWN * 0.2,
				_rng.randf_range(w.rag_length_min, w.rag_length_max))


## El mástil caído: su muñón en la cubierta y el palo apoyado en la borda, con
## la punta en la arena. Su inclinación sale de su largo y del alto de la borda.
func _fallen_mast(foot: Vector3) -> void:
	var w := _wreck
	pole(foot + Vector3.DOWN * MAST_FOOT_DEPTH, foot + Vector3.UP * 1.2, w.mast_radius,
			w.mast_radius * 0.9, w.dark_plank, true)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var shape := w.shape_at(foot.x)
	var radius := w.mast_radius * 0.9
	var rest := Vector3(foot.x, shape.z + radius,
			side * shape.x * GalleonWreck.PROFILE[GalleonWreck.PROFILE.size() - 1].x)
	var outside := maxf(w.fallen_mast_length - FALLEN_OVERHANG, 1.0)
	var drop := minf(rest.y + FALLEN_SINK, outside * 0.95)
	var reach := sqrt(outside * outside - drop * drop)
	var yaw := _rng.randf_range(-0.25, 0.25)
	var tip := rest + Vector3(sin(yaw) * reach, -drop, side * cos(yaw) * reach)
	var dir := (tip - rest).normalized()
	pole(rest - dir * FALLEN_OVERHANG, tip, radius, w.mast_radius * 0.6, w.rot_plank, true)
	var hang := rest + dir * outside * 0.35
	_rag(hang, hang + dir * 1.5, minf(_rng.randf_range(w.rag_length_min, w.rag_length_max),
			hang.y * 0.8))


## Un jirón de vela que cuelga del borde a-b, de unos `drop` metros, con el borde de abajo roto.
func _rag(a: Vector3, b: Vector3, drop: float) -> void:
	var sway := Vector3(_rng.randf_range(-RAG_SWAY, RAG_SWAY), 0.0, 0.0)
	var low_a := a + Vector3.DOWN * drop * _rng.randf_range(0.5, 0.85) + sway * 0.6
	var low_mid := a.lerp(b, _rng.randf_range(0.3, 0.7)) + Vector3.DOWN * drop + sway
	var low_b := b + Vector3.DOWN * drop * _rng.randf_range(0.4, 0.8) + sway * 0.8
	var centre := (a + b + low_a + low_mid + low_b) / 5.0
	var normal := (b - a).cross(low_mid - a).normalized()
	var tone := _wreck.sail_color.darkened(_rng.randf_range(0.0, 0.15))
	# Las dos caras: la vela se ve de ambos lados.
	for flip: float in [1.0, -1.0]:
		var inside := centre + normal * flip
		_mesh.triangle(a, b, low_b, tone, inside)
		_mesh.triangle(a, low_b, low_mid, tone, inside)
		_mesh.triangle(a, low_mid, low_a, tone, inside)


## Un cañón que asoma de la porta en `centre` hacia el costado `side`, con su boca.
func _cannon(centre: Vector3, side: float) -> void:
	var muzzle := centre + Vector3(0.0, -0.15, side * _wreck.cannon_length)
	pole(centre - Vector3(0.0, 0.0, side * 0.5), muzzle, 0.2, 0.17, _wreck.iron_color, false)
	pole(muzzle - Vector3(0.0, 0.0, side * 0.25), muzzle, 0.26, 0.26, _wreck.iron_color, false)
