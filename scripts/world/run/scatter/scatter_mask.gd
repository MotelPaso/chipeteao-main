extends RefCounted
## La roca de una arena: arma la ArenaMask con los exports «Máscara de la
## arena» del scatter y su RNG (build), y levanta una RockFormation por cada
## región de celdas bloqueadas (raise_formations). Los valores son exports
## del scatter (grupos «Máscara de la arena» y «Formaciones de roca»): se
## cambian en la arena, no aquí. Ninguna escena usa este script; scatter.gd
## lo precarga como ScatterMask.


## La máscara de `scatter`, construida con su RNG `rng` (ArenaMask.build
## imprime `Arena mask:`). Con relieve por zonas (`layout`) la roca rodea sus
## cortes; con mask_enabled apagado queda vacía y toda la arena es caminable.
static func build(scatter: ArenaScatter, rng: RandomNumberGenerator,
		layout: ReliefLayout) -> ArenaMask:
	var mask := _new_mask(scatter, rng)
	if scatter.mask_enabled and layout != null:
		mask.build(_protected_seeds(scatter),
				ReliefQueries.mask_cells(layout, scatter.mask_cell_size),
				ReliefQueries.mask_barriers(layout, scatter.mask_cell_size))
	elif scatter.mask_enabled:
		mask.build(_protected_seeds(scatter))
	return mask


## Cada región conexa de celdas bloqueadas de `mask` se vuelve UNA
## RockFormation hija de `scatter` que cubre toda la región, borde incluido,
## con roca sólida (rock_formation.gd explica por qué el sello es estructural
## y no probable). El interior también es roca a propósito: un raider puede
## saltar a una formación y caminar su cresta, y sobre una región hueca
## caería a suelo que la máscara llama inalcanzable y quedaría atrapado.
static func raise_formations(scatter: ArenaScatter, mask: ArenaMask, run_seed: int) -> void:
	if mask.blocked_cell_count() == 0:
		return
	var started := Time.get_ticks_msec()
	var terrain := Terrain.find(scatter.get_tree())
	if terrain != null:
		terrain.ensure_built()
	var regions := mask.blocked_regions()
	var faces := 0
	var shapes := 0
	var seal_low := 0
	var tallest := 0.0
	for index in regions.size():
		var formation := RockFormation.new()
		formation.name = "RockFormation%d" % index
		formation.cell_size = scatter.mask_cell_size
		formation.half_extent = scatter.arena_half_extent
		formation.style = scatter.formation_style
		scatter.add_child(formation)
		formation.build(regions[index], terrain, run_seed)
		faces += formation.face_count
		shapes += formation.prism_count
		seal_low += formation.seal_low
		tallest = maxf(tallest, formation.tallest)
	print("Rock formations: %d regions, %d faces, %d shapes, tallest=%.1f in %d ms" % [
			regions.size(), faces, shapes, tallest, Time.get_ticks_msec() - started])
	if seal_low > 0:
		push_warning("Rock formations: %d boundary vertices under %.1f m — the mask seal is thin there"
				% [seal_low, RockFormation.SEAL_MIN_HEIGHT])


## Una ArenaMask con los exports «Máscara de la arena» de `scatter` y su RNG.
static func _new_mask(scatter: ArenaScatter, rng: RandomNumberGenerator) -> ArenaMask:
	var mask := ArenaMask.new(rng)
	mask.enabled = scatter.mask_enabled
	mask.half_extent = scatter.arena_half_extent
	mask.cell_size = scatter.mask_cell_size
	mask.blobs_min = scatter.mask_blobs_min
	mask.blobs_max = scatter.mask_blobs_max
	mask.blob_cells_min = scatter.mask_blob_cells_min
	mask.blob_cells_max = scatter.mask_blob_cells_max
	mask.ridge_bias = scatter.mask_ridge_bias
	mask.blob_spacing = scatter.mask_blob_spacing
	mask.formation_gap = scatter.mask_formation_gap
	mask.border_cells = scatter.mask_border_cells
	mask.protect_radius = scatter.mask_protect_radius
	mask.min_open_fraction = scatter.mask_min_open_fraction
	return mask


## Puntos planos donde nunca hay roca: el spawn y cada keepout de autor
## (spots de verticalidad, grupos de rocas), en orden de grupo.
static func _protected_seeds(scatter: ArenaScatter) -> Array[Vector2]:
	var seeds: Array[Vector2] = [Vector2.ZERO]
	for node: Node in scatter.get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable):
			seeds.append(Vector2(spot.global_position.x, spot.global_position.z))
	return seeds
