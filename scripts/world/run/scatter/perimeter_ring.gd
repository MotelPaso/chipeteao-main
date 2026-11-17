class_name PerimeterRing
extends RefCounted
## La franja del borde de una arena: recorre los cuatro lados del suelo
## plantando props grandes (y algún acento) con jitter, para que el límite
## se lea como paisaje y no como vacío. Los valores son exports del scatter
## (grupo «Borde»): se cambian en la arena, no aquí.

## Metros que el faldón de roca de una formación asoma de sus celdas más el
## medio tronco de un prop del borde (ver _in_formation_skirt).
const EDGE_SKIRT: float = 3.0

var _scatter: ArenaScatter = null
var _rng: RandomNumberGenerator = null
var _mask: ArenaMask = null
## Con relieve por zonas un prop del borde tampoco va en el faldón de una
## formación: quedaría asomando de la roca.
var _skip_skirts: bool = false


func _init(scatter: ArenaScatter, rng: RandomNumberGenerator, mask: ArenaMask,
		skip_skirts: bool) -> void:
	_scatter = scatter
	_rng = rng
	_mask = mask
	_skip_skirts = skip_skirts


## Planta la franja. Queda fuera del cuadrado interior, así que no revisa
## distancias con los props de dentro.
func plant() -> void:
	if _main() == null:
		return
	var slot := 0
	var outer := _scatter.arena_half_extent - _scatter.perimeter_edge_margin_min
	var t := -outer + 1.0
	while t <= outer - 1.0:
		_plant_prop(Vector3(t + _jitter(), 0.0, -_band_depth()), slot)
		_plant_prop(Vector3(t + _jitter(), 0.0, _band_depth()), slot + 1)
		_plant_prop(Vector3(-_band_depth(), 0.0, t + _jitter()), slot + 2)
		_plant_prop(Vector3(_band_depth(), 0.0, t + _jitter()), slot + 3)
		slot += 4
		t += _scatter.perimeter_step


## Desvío al azar de un prop del borde a lo largo de su lado.
func _jitter() -> float:
	return _rng.randf_range(-_scatter.perimeter_jitter, _scatter.perimeter_jitter)


## Distancia al centro, en metros, de un prop del borde (dentro de la franja).
func _band_depth() -> float:
	return _rng.randf_range(_scatter.arena_half_extent - _scatter.perimeter_edge_margin_max,
			_scatter.arena_half_extent - _scatter.perimeter_edge_margin_min)


func _plant_prop(pos: Vector3, slot: int) -> void:
	var gap := _scatter.perimeter_corner_gap
	var corner := _scatter.arena_half_extent - gap
	if gap > 0.0 and absf(pos.x) > corner and absf(pos.z) > corner:
		return
	if _skip_skirts and _in_formation_skirt(Vector2(pos.x, pos.z)):
		return
	var accent := _accent()
	var every := _scatter.perimeter_rock_every
	if accent != null and every > 0 and slot % every == 0:
		_scatter.spawn_prop(accent, pos, _rng.randf_range(_scatter.perimeter_accent_scale_min,
				_scatter.perimeter_accent_scale_max))
	else:
		_scatter.spawn_prop(_main(), pos, _rng.randf_range(_scatter.perimeter_scale_min,
				_scatter.perimeter_scale_max))


## True si `xz` cae en una formación o en el faldón que asoma de sus celdas
## (EDGE_SKIRT metros). Los puntos de prueba se recortan a la arena: junto al
## muro, "fuera del mapa" no es roca.
func _in_formation_skirt(xz: Vector2) -> bool:
	var limit := _scatter.arena_half_extent - 0.1
	for index in 9:
		var probe := xz
		if index > 0:
			probe += Vector2.from_angle(float(index) * TAU / 8.0) * EDGE_SKIRT
		probe = probe.clamp(Vector2(-limit, -limit), Vector2(limit, limit))
		if not _mask.is_walkable(probe):
			return true
	return false


## El prop del borde: el propio de la arena o, si no tiene, su árbol.
func _main() -> PackedScene:
	if _scatter.perimeter_scene != null:
		return _scatter.perimeter_scene
	return _scatter.tree_scene


## El acento del borde: el propio de la arena o, si no tiene, su roca.
func _accent() -> PackedScene:
	if _scatter.perimeter_accent_scene != null:
		return _scatter.perimeter_accent_scene
	return _scatter.rock_scene
