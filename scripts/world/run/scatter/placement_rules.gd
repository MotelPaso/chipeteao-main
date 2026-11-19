extends RefCounted
## Las preguntas «¿se puede poner algo aquí?» de una arena: can_place,
## can_build, can_grow y nearest_place, que el scatter reenvía con los mismos
## nombres por el grupo "arena_bounds", más las que usa el reparto interior.
## Junta la máscara, el relieve por zonas, las mesetas, los claros de las
## estructuras del relieve y la huella de los props. Los márgenes son exports
## del scatter (formation_clearance, mesa_footprint_gap, relief_mesa_keepout):
## se cambian en la arena, no aquí. Ninguna escena usa este script;
## scatter.gd lo precarga como PlacementRules.

## Huella de los props con colisión; solo se enciende con relieve por zonas.
var footprints := PropFootprints.new()
## Claros que ocupan las estructuras del relieve, como (x, radio, z). Los
## pone place_props() del scatter al levantarlas.
var structure_sites := PackedVector3Array()

## Copias de los exports del scatter que estas preguntas leen en cada
## llamada (sus tooltips explican cada uno), tomadas en setup().
var _formation_clearance := 0.0
var _mesa_footprint_gap := 0.0
var _relief_mesa_keepout := 0.0
var _mask: ArenaMask = null
var _mesas: MesaBuilder.Plan = null
## Centros planos de las mesetas de la etapa.
var _mesa_sites := PackedVector2Array()
## El Terrain de la arena, o null.
var _terrain: Terrain = null


## Conecta las preguntas a la máscara `mask` y a las mesetas `mesas` de
## `scatter`, ya armadas en su _enter_tree, y a su Terrain `terrain`, y copia
## sus márgenes.
func setup(scatter: ArenaScatter, mask: ArenaMask, mesas: MesaBuilder.Plan,
		terrain: Terrain) -> void:
	_formation_clearance = scatter.formation_clearance
	_mesa_footprint_gap = scatter.mesa_footprint_gap
	_relief_mesa_keepout = scatter.relief_mesa_keepout
	_mask = mask
	_mesas = mesas
	_mesa_sites = mesas.sites()
	_terrain = terrain


## True si en `xz` se puede COLOCAR algo (un POI, un spawn, un cofre, un
## jefe): celda abierta de la máscara y, con relieve por zonas, a `margin`
## metros o más de todo corte, rampa y puente, fuera de las mesetas y de las
## estructuras, y nunca encima de un prop con colisión. Es la pregunta de
## quien pone cosas; is_walkable sigue siendo solo la máscara.
func can_place(xz: Vector2, margin: float) -> bool:
	return can_grow(xz, margin) and footprints.is_clear(xz)


## True si en `xz` se puede levantar una ESTRUCTURA del director (un POI, un
## portal, un evento): lo mismo que can_place, a `margin` metros o más de la
## roca de la máscara y de las mesetas en todo mapa y, con relieve por
## zonas, fuera del cañón, que es río. Lo que cae donde murió alguien y los
## spawns siguen con can_place: pueden quedar en el cañón.
func can_build(xz: Vector2, margin: float) -> bool:
	if not can_place(xz, margin) or in_canyon(xz):
		return false
	var rock_gap := maxf(_formation_clearance, margin)
	return _mask.rock_distance(xz, rock_gap) >= rock_gap \
			and _mesas.is_clear(xz, maxf(_mesa_footprint_gap, margin))


## True si en `xz` puede crecer la vegetación del suelo: lo mismo que
## can_place, salvo que el pasto sí llega hasta el pie de un tronco.
func can_grow(xz: Vector2, margin: float) -> bool:
	if not _mask.is_walkable(xz):
		return false
	if _terrain == null or not _terrain.has_relief():
		return true
	# Con relieve por zonas, además fuera del faldón de roca que cada
	# formación asoma más allá de sus celdas y de las estructuras del relieve.
	return _mask.clear_of(xz, _formation_clearance) and structures_clear(xz) \
			and ReliefDressing.clear(_terrain, xz, margin, _mesa_sites, _relief_mesa_keepout) \
			and _mesas.is_clear(xz, _mesa_footprint_gap)


## El punto donde se puede colocar algo más cercano a `xz` (ver can_place):
## el mismo `xz` si sirve. Para lo que cae donde murió alguien. Sin RNG.
## Con `also`, el punto además tiene que pasar esa pregunta (recibe el XZ):
## un spawn pide que debajo haya suelo y no la punta de algo.
func nearest_place(xz: Vector2, margin: float, also: Callable) -> Vector2:
	if not also.is_valid():
		return ReliefDressing.nearest(xz, margin, can_place)
	return ReliefDressing.nearest(xz, margin, func(at: Vector2, gap: float) -> bool:
		return can_place(at, gap) and bool(also.call(at)))


## True si `xz` cae dentro del cañón del relieve por zonas, rampas incluidas.
func in_canyon(xz: Vector2) -> bool:
	return _terrain != null and _terrain.has_relief() \
			and _terrain.relief_layout().level_at(xz) == -1


## True si `xz` queda a `margin` metros o más de todo corte, rampa y puente
## del relieve por zonas (siempre, en una arena sin él).
func relief_clear(xz: Vector2, margin: float) -> bool:
	return ReliefDressing.clear(_terrain, xz, margin)


## True si `xz` queda fuera del claro de toda estructura del relieve.
func structures_clear(xz: Vector2) -> bool:
	for site: Vector3 in structure_sites:
		if Vector2(site.x, site.z).distance_to(xz) < site.y:
			return false
	return true
