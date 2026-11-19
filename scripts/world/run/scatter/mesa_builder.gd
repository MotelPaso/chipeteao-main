class_name MesaBuilder
extends RefCounted
## Las mesetas de una arena: sortea cada una entera, dónde va, su escala, su
## giro y la cara de su rampa (plan), y las levanta (build). Los valores son
## exports del scatter (grupo «Mesetas»): se cambian en la arena, no aquí. El
## plan existe desde el _enter_tree del scatter, así lo que se coloca antes
## de levantarlas (los POI del director) ya esquiva su huella.

## Cara de la plataforma donde puede ir la rampa (dirección a escala 1, en
## el espacio de la plataforma) y el giro que la deja subiendo hacia ella.
const RAMP_SIDES: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
const RAMP_TURNS: Array[float] = [PI, PI * 0.5, 0.0, -PI * 0.5]


## Una meseta planeada: dónde va, su escala, su giro, la cara de su rampa y
## su huella en planta, un rectángulo girado por pieza (plataforma y rampa).
class Mesa:
	extends RefCounted
	var site := Vector2.ZERO
	var scale := 1.0
	var angle := 0.0
	## Índice de RAMP_SIDES donde va la rampa, o -1 sin rampa.
	var side := -1
	## Por pieza: del plano del mundo (x, z) al plano propio de la pieza, y
	## su medio lado en metros, ya a escala.
	var frames: Array[Transform2D] = []
	var halves := PackedVector2Array()
	## Metros del sitio al punto más lejano de la huella.
	var reach := 0.0

	## True si cada pieza de la huella queda a `gap` metros o más de toda
	## celda de roca de `mask`.
	func clear_of_rock(mask: ArenaMask, gap: float) -> bool:
		for piece in frames.size():
			if not mask.box_clear(frames[piece], halves[piece], gap):
				return false
		return true


## Las mesetas planeadas de una etapa. `bounds` guarda, por meseta, el
## círculo que encierra su huella (x, radio, z): casi todo punto queda lejos
## de todas, y para él la pregunta es una pasada por un arreglo plano.
class Plan:
	extends RefCounted
	var mesas: Array[Mesa] = []
	var bounds := PackedVector3Array()

	## Suma `mesa` al plan, con el círculo que encierra su huella.
	func add(mesa: Mesa) -> void:
		mesas.append(mesa)
		bounds.append(Vector3(mesa.site.x, mesa.reach, mesa.site.y))

	## Los centros (x, z) de las mesetas, en el orden en que se sortearon.
	func sites() -> PackedVector2Array:
		var result := PackedVector2Array()
		for mesa: Mesa in mesas:
			result.append(mesa.site)
		return result

	## True si `xz` queda a `gap` metros o más de la huella de toda meseta: su
	## plataforma y su rampa, a su escala y con su giro.
	func is_clear(xz: Vector2, gap: float) -> bool:
		for index in bounds.size():
			var bound := bounds[index]
			# Fuera del círculo que encierra la huella con su margen.
			if Vector2(bound.x, bound.z).distance_to(xz) >= bound.y + gap * 1.5:
				continue
			var mesa := mesas[index]
			for piece in mesa.frames.size():
				var local := mesa.frames[piece] * xz
				var half := mesa.halves[piece]
				if absf(local.x) < half.x + gap and absf(local.y) < half.y + gap:
					return false
		return true


## Sortea las mesetas de `scatter` con su RNG, cada una entera: el centro y,
## si el centro sirve (ver _site_ok), su escala, su giro y la cara de su
## rampa, en ese orden. Se queda con ella solo si toda su huella (plataforma
## y rampa, a su escala y con su giro) guarda mesa_clearance de la roca de
## `mask`. Corre en el _enter_tree del scatter; build() ya no tira nada.
static func plan(scatter: ArenaScatter, rng: RandomNumberGenerator, mask: ArenaMask,
		terrain: Terrain) -> Plan:
	var result := Plan.new()
	if scatter.mesa_count <= 0 or scatter.mesa_platform_scene == null:
		return result
	var plat_box := _local_box(scatter.mesa_platform_scene)
	var ramp_box := Rect2()
	if scatter.mesa_ramp_scene != null:
		ramp_box = _local_box(scatter.mesa_ramp_scene)
	var authored := _authored_spots(scatter)
	# Mitad del cuadrado donde se sortean los centros, en metros.
	var half := scatter.arena_half_extent - scatter.mesa_edge_margin
	for attempt in scatter.mesa_count * 40:
		if result.mesas.size() >= scatter.mesa_count:
			break
		var site := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if not _site_ok(scatter, terrain, site, authored, result.sites()):
			continue
		var mesa := _shape(scatter, rng, site, plat_box, ramp_box)
		if not scatter.mask_enabled or mesa.clear_of_rock(mask, scatter.mesa_clearance):
			result.add(mesa)
	return result


## Levanta plataforma + rampa de cada meseta de `planned` y devuelve los
## sitios donde quedó una. El claro ya es plano (el Terrain leyó los sitios),
## así la rampa toca suelo parejo en sus dos extremos en vez de flotar en uno.
static func build(scatter: ArenaScatter, planned: Plan) -> PackedVector2Array:
	var built := PackedVector2Array()
	if scatter.mesa_platform_scene == null:
		return built
	var chests_left := scatter.mesa_chest_count
	for mesa: Mesa in planned.mesas:
		var plat := scatter.mesa_platform_scene.instantiate() as Node3D
		if plat == null:
			continue
		scatter.add_child(plat)
		plat.position = Vector3(mesa.site.x, scatter.ground_height(mesa.site.x, mesa.site.y),
				mesa.site.y)
		plat.rotation.y = mesa.angle
		plat.scale = Vector3.ONE * mesa.scale
		if chests_left > 0 and ReliefDressing.place_chest(scatter, scatter.mesa_chest_scene,
				plat, scatter.mesa_deck_height * mesa.scale):
			chests_left -= 1
		if mesa.side >= 0:
			_add_ramp(scatter, plat, mesa)
		built.append(mesa.site)
	return built


## True si `site` sirve de centro de meseta: a mesa_min_spacing o más del
## spawn, de los spots de autor (`authored`) y de las otras mesetas (`sites`),
## y a relief_mesa_clearance de todo corte del relieve por zonas de `terrain`.
static func _site_ok(scatter: ArenaScatter, terrain: Terrain, site: Vector2,
		authored: Array[Vector2], sites: PackedVector2Array) -> bool:
	if site.length() < scatter.mesa_min_spacing:
		return false
	if not _far_from(site, authored, scatter.mesa_min_spacing) \
			or not _far_from(site, sites, scatter.mesa_min_spacing):
		return false
	return ReliefDressing.clear(terrain, site, scatter.relief_mesa_clearance)


## Una meseta en `site` con la escala, el giro y la cara de la rampa que tira
## `rng`, y su huella: un rectángulo por pieza (`plat_box` y `ramp_box` son la
## colisión de la plataforma y de la rampa a escala 1).
static func _shape(scatter: ArenaScatter, rng: RandomNumberGenerator, site: Vector2,
		plat_box: Rect2, ramp_box: Rect2) -> Mesa:
	var mesa := Mesa.new()
	mesa.site = site
	mesa.scale = rng.randf_range(scatter.mesa_scale_min, scatter.mesa_scale_max)
	mesa.angle = rng.randf_range(0.0, TAU)
	_add_piece(mesa, site, mesa.angle, plat_box)
	if scatter.mesa_ramp_scene != null:
		mesa.side = rng.randi_range(0, 3)
		_add_piece(mesa, _ramp_site(scatter, mesa), mesa.angle + RAMP_TURNS[mesa.side], ramp_box)
	return mesa


## Los spots de autor de la arena de `scatter` (keepouts que no son POI), en
## orden de grupo.
static func _authored_spots(scatter: ArenaScatter) -> Array[Vector2]:
	var authored: Array[Vector2] = []
	for node: Node in scatter.get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable) and scatter.owner_arena_contains(spot):
			authored.append(Vector2(spot.position.x, spot.position.z))
	return authored


## La rampa de `mesa`, pegada a la cara elegida de su plataforma `plat`.
static func _add_ramp(scatter: ArenaScatter, plat: Node3D, mesa: Mesa) -> void:
	var ramp := scatter.mesa_ramp_scene.instantiate() as Node3D
	if ramp == null:
		return
	scatter.add_child(ramp)
	# plat.transform ya lleva la escala de la meseta.
	var world_pos: Vector3 = plat.transform * (RAMP_SIDES[mesa.side] * scatter.mesa_ramp_offset
			* _ramp_reach(scatter, mesa))
	ramp.position = Vector3(world_pos.x, scatter.ground_height(world_pos.x, world_pos.z),
			world_pos.z)
	ramp.rotation.y = mesa.angle + RAMP_TURNS[mesa.side]
	ramp.scale = Vector3.ONE * mesa.scale


## Cuántas veces se multiplica mesa_ramp_offset además de la escala de la
## plataforma: pegada, ninguna; suelta, otra vez la escala.
static func _ramp_reach(scatter: ArenaScatter, mesa: Mesa) -> float:
	return 1.0 if scatter.mesa_ramp_attached else mesa.scale


## Centro (x, z) de la rampa de `mesa`: lo mismo que _add_ramp, en planta.
static func _ramp_site(scatter: ArenaScatter, mesa: Mesa) -> Vector2:
	var side := RAMP_SIDES[mesa.side]
	var offset := Vector2(side.x, side.z) * scatter.mesa_ramp_offset \
			* _ramp_reach(scatter, mesa) * mesa.scale
	return mesa.site + _turn(mesa.angle, Vector2.ZERO) * offset


## Anota en `mesa` la pieza cuya colisión ocupa `box` (en planta, a escala 1)
## puesta en `origin` con el giro `yaw`.
static func _add_piece(mesa: Mesa, origin: Vector2, yaw: float, box: Rect2) -> void:
	var center := _turn(yaw, origin) * (box.get_center() * mesa.scale)
	var half := box.size * 0.5 * mesa.scale
	mesa.frames.append(_turn(yaw, center).affine_inverse())
	mesa.halves.append(half)
	mesa.reach = maxf(mesa.reach, mesa.site.distance_to(center) + half.length())


## Del plano de una pieza al plano del mundo (x, z): el mismo giro que
## `rotation.y = yaw` le da a un Node3D, y después `origin`.
static func _turn(yaw: float, origin: Vector2) -> Transform2D:
	return Transform2D(-yaw, origin)


## El rectángulo en planta (x, z) que ocupa la colisión de `scene` a escala
## 1, en el espacio de su raíz.
static func _local_box(scene: PackedScene) -> Rect2:
	var root := scene.instantiate() as Node3D
	if root == null:
		return Rect2()
	var box := Rect2()
	var first := true
	for child: Node in root.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.disabled or holder.shape == null:
			continue
		var aabb := holder.transform * holder.shape.get_debug_mesh().get_aabb()
		var flat := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
		box = flat if first else box.merge(flat)
		first = false
	root.free()
	return box


## True si `point` queda a `gap` metros o más de todos los `others`.
static func _far_from(point: Vector2, others: Variant, gap: float) -> bool:
	for other: Vector2 in others:
		if other.distance_to(point) < gap:
			return false
	return true
