class_name MesaBuilder
extends RefCounted
## Las mesetas de una arena: sortea dónde van y levanta en cada sitio una
## plataforma con su rampa. Los valores son exports del scatter (grupo
## «Mesetas»): se cambian en la arena, no aquí.


## Sortea los centros de las mesetas de `scatter` con su RNG: lejos del
## spawn, entre sí, de los spots de autor, de la roca de la máscara y de
## los cortes del relieve por zonas de `terrain`.
static func pick_sites(scatter: ArenaScatter, rng: RandomNumberGenerator, mask: ArenaMask,
		terrain: Terrain) -> PackedVector2Array:
	var sites := PackedVector2Array()
	if scatter.mesa_count <= 0 or scatter.mesa_platform_scene == null:
		return sites
	var authored: Array[Vector2] = []
	for node: Node in scatter.get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable) and scatter.owner_arena_contains(spot):
			authored.append(Vector2(spot.position.x, spot.position.z))
	# Mitad del cuadrado donde se sortean los centros, en metros.
	var half := scatter.arena_half_extent - scatter.mesa_edge_margin
	for attempt in scatter.mesa_count * 40:
		if sites.size() >= scatter.mesa_count:
			break
		var candidate := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if candidate.length() < scatter.mesa_min_spacing:
			continue
		if scatter.mask_enabled and not (mask.clear_of(candidate, scatter.mesa_clearance)
				and mask.clear_of(candidate, scatter.mesa_clearance * 0.5)):
			continue
		if not ReliefDressing.clear(terrain, candidate, scatter.relief_mesa_clearance):
			continue
		if _far_from(candidate, authored, scatter.mesa_min_spacing) \
				and _far_from(candidate, sites, scatter.mesa_min_spacing):
			sites.append(candidate)
	return sites


## Construye plataforma + rampa en cada sitio y devuelve los sitios donde
## quedó una. El claro ya es plano (el Terrain leyó los sitios), así la
## rampa toca suelo parejo en sus dos extremos en vez de flotar en uno.
static func build(scatter: ArenaScatter, rng: RandomNumberGenerator,
		sites: PackedVector2Array) -> PackedVector2Array:
	var built := PackedVector2Array()
	if scatter.mesa_platform_scene == null:
		return built
	var chests_left := scatter.mesa_chest_count
	for site: Vector2 in sites:
		var mesa_scale := rng.randf_range(scatter.mesa_scale_min, scatter.mesa_scale_max)
		var plat := scatter.mesa_platform_scene.instantiate() as Node3D
		if plat == null:
			continue
		scatter.add_child(plat)
		var plat_angle := rng.randf_range(0.0, TAU)
		plat.position = Vector3(site.x, scatter.ground_height(site.x, site.y), site.y)
		plat.rotation.y = plat_angle
		plat.scale = Vector3.ONE * mesa_scale
		if chests_left > 0 and ReliefDressing.place_chest(scatter, scatter.mesa_chest_scene,
				plat, scatter.mesa_deck_height * mesa_scale):
			chests_left -= 1
		if scatter.mesa_ramp_scene != null:
			_add_ramp(scatter, rng, plat, plat_angle, mesa_scale)
		built.append(site)
	return built


## La rampa de una meseta, alineada con una de las 4 caras planas de su
## plataforma `plat`.
static func _add_ramp(scatter: ArenaScatter, rng: RandomNumberGenerator, plat: Node3D,
		plat_angle: float, mesa_scale: float) -> void:
	var ramp := scatter.mesa_ramp_scene.instantiate() as Node3D
	if ramp == null:
		return
	scatter.add_child(ramp)
	var side_idx := rng.randi_range(0, 3)
	var offset := scatter.mesa_ramp_offset
	var local_offsets: Array[Vector3] = [
		Vector3(offset, 0.0, 0.0),
		Vector3(0.0, 0.0, offset),
		Vector3(-offset, 0.0, 0.0),
		Vector3(0.0, 0.0, -offset)
	]
	var local_rot_y: Array[float] = [PI, PI * 0.5, 0.0, -PI * 0.5]
	# plat.transform ya lleva la escala de la meseta.
	var reach := 1.0 if scatter.mesa_ramp_attached else mesa_scale
	var world_pos: Vector3 = plat.transform * (local_offsets[side_idx] * reach)
	ramp.position = Vector3(world_pos.x, scatter.ground_height(world_pos.x, world_pos.z),
			world_pos.z)
	ramp.rotation.y = plat_angle + local_rot_y[side_idx]
	ramp.scale = Vector3.ONE * mesa_scale


## True si `point` queda a `gap` metros o más de todos los `others`.
static func _far_from(point: Vector2, others: Variant, gap: float) -> bool:
	for other: Vector2 in others:
		if other.distance_to(point) < gap:
			return false
	return true
