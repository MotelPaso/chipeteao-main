class_name PropFootprints
extends RefCounted
## La huella en planta de los props con colisión de una arena (troncos,
## rocas, tocones): una grilla que responde «¿este punto cae sobre un prop?»
## con una sola lectura. La consulta `arena_bounds.can_place`, para que un
## portal, un cofre o un spawn nunca queden encima de un tronco, donde nadie
## los alcanza.
##
## Ninguna escena usa este script: lo que alguien podría querer tocar está
## en las constantes de aquí arriba.

# --- edita aquí --------------------------------------------------------------
## Lado de cada celda de la grilla, en metros.
const CELL: float = 1.0
## Aire que se deja alrededor de la colisión de cada prop, en metros: el
## ancho de un raider, para que lo colocado al lado se pueda pisar.
const SKIRT: float = 0.6
# -----------------------------------------------------------------------------

var _half: float = 0.0
var _side: int = 0
var _taken := PackedByteArray()
## Hasta dónde llega la colisión de cada escena ya medida (metros a escala 1).
var _reach_by_scene: Dictionary = {}


## Prepara la grilla para una arena de `half_extent` metros de medio lado.
## Sin esta llamada la huella queda apagada: todo punto responde libre.
func setup(half_extent: float) -> void:
	_half = half_extent
	_side = ceili(half_extent * 2.0 / CELL)
	_taken = PackedByteArray()
	_taken.resize(_side * _side)


## Anota la huella de `prop`, ya colocado y escalado (escala uniforme).
func add(prop: Node3D) -> void:
	if _side == 0:
		return
	var key := prop.scene_file_path
	if not _reach_by_scene.has(key):
		_reach_by_scene[key] = _measure(prop)
	var reach: float = _reach_by_scene[key]
	if reach > 0.0:
		_mark(Vector2(prop.position.x, prop.position.z), reach * prop.scale.x + SKIRT)


## True si `xz` queda fuera de la huella de todo prop anotado.
func is_clear(xz: Vector2) -> bool:
	if _side == 0:
		return true
	var ix := floori((xz.x + _half) / CELL)
	var iz := floori((xz.y + _half) / CELL)
	if ix < 0 or iz < 0 or ix >= _side or iz >= _side:
		return true
	return _taken[iz * _side + ix] == 0


## Marca toda celda que toca el disco de `radius` metros alrededor de `xz`.
func _mark(xz: Vector2, radius: float) -> void:
	var first_x := maxi(floori((xz.x - radius + _half) / CELL), 0)
	var last_x := mini(floori((xz.x + radius + _half) / CELL), _side - 1)
	var first_z := maxi(floori((xz.y - radius + _half) / CELL), 0)
	var last_z := mini(floori((xz.y + radius + _half) / CELL), _side - 1)
	for iz in range(first_z, last_z + 1):
		for ix in range(first_x, last_x + 1):
			var low := Vector2(ix * CELL - _half, iz * CELL - _half)
			var nearest := xz.clamp(low, low + Vector2(CELL, CELL))
			if nearest.distance_to(xz) <= radius:
				_taken[iz * _side + ix] = 1


## Hasta dónde llega en planta la colisión de `prop` desde su origen, en
## metros a escala 1; 0 si no tiene. Mira las formas hijas directas del
## cuerpo, que es como vienen las escenas de props.
static func _measure(prop: Node3D) -> float:
	var reach := 0.0
	for node: Node in prop.get_children():
		var holder := node as CollisionShape3D
		if holder == null or holder.disabled or holder.shape == null:
			continue
		var offset := Vector2(holder.position.x, holder.position.z).length()
		reach = maxf(reach, offset + _shape_reach(holder.shape))
	return reach


## Radio en planta de una forma de colisión, en metros.
static func _shape_reach(shape: Shape3D) -> float:
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return Vector2(size.x, size.z).length() * 0.5
	if shape is ConvexPolygonShape3D:
		var far := 0.0
		for point: Vector3 in (shape as ConvexPolygonShape3D).points:
			far = maxf(far, Vector2(point.x, point.z).length())
		return far
	return 0.0
