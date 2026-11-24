class_name ReliefEdgeSweeps
extends RefCounted
## Los barridos del BORDE de una arena con relieve por zonas, que ReliefSweeps
## corre con los demás al empezar la etapa. Cada uno imprime una línea
## `Relief sweep:` que lee tools/verificar.sh:
##
##   rim   celdas que el raider o la horda alcanzan desde el spawn a menos de
##         rim_flat_band de un muro, y cuántas tienen el piso a más de
##         RIM_LEVEL metros del nivel del borde (off_level, tiene que dar 0:
##         los muros del Perimeter solo alcanzan sobre suelo a ese nivel).
##   edge  el suelo de AFUERA del muro: si es la malla del Terrain con el
##         material del suelo (material=terrain), cuánto se aparta del borde
##         de la arena sobre el muro (seam_max, por la función de altura) y
##         cuánto se aparta la malla de esa función (mesh_max; inf si la malla
##         no sigue pasado el muro). `bad` cuenta las muestras del muro que se
##         apartan más de SEAM_LIMIT, más una si mesh_max pasa de SEAM_LIMIT:
##         tiene que dar 0.
##
## Nunca se afloja una tolerancia para hacerlos pasar: cede el relieve.

## Metros que el piso de una celda alcanzable junto al muro puede apartarse
## del nivel del borde.
const RIM_LEVEL: float = 1.0
## Metros que el suelo de afuera puede apartarse del borde de la arena sobre
## el muro, y metros entre dos muestras del muro.
const SEAM_LIMIT: float = 0.1
const SEAM_STEP: float = 2.0
## Metros hacia afuera del muro a los que se lee el suelo de afuera.
const SEAM_OUT: float = 0.01
## Muestras con nombre cuando un conteo no da cero.
const DETAIL_LIMIT: int = 4


## El barrido `rim`. `raider_seen` y `horde_seen` marcan con 1 las celdas del
## grafo que cada uno alcanza desde el spawn.
static func rim(graph: ReliefGraph, terrain: Terrain, raider_seen: PackedByteArray,
		horde_seen: PackedByteArray) -> void:
	var band := terrain.rim_flat_band
	var half := terrain.size * 0.5
	var cells := 0
	var off := 0
	var worst := 0.0
	var notes: Array[String] = []
	for index in graph.state.size():
		if graph.state[index] != ReliefGraph.OPEN:
			continue
		if raider_seen[index] == 0 and horde_seen[index] == 0:
			continue
		var flat := graph.center(index)
		var to_x := half - absf(flat.x)
		var to_z := half - absf(flat.y)
		if minf(to_x, to_z) > band:
			continue
		cells += 1
		var wall := Vector2(signf(flat.x) * half, flat.y) if to_x < to_z \
				else Vector2(flat.x, signf(flat.y) * half)
		var gap := absf(graph.floor_y[index] - terrain.height_at(wall.x, wall.y))
		worst = maxf(worst, gap)
		if gap > RIM_LEVEL:
			off += 1
			if notes.size() < DETAIL_LIMIT:
				var at := graph.stand(index)
				notes.append("rim off level by %.2f at (%.1f, %.1f, %.1f)" % [gap, at.x, at.y, at.z])
	print("Relief sweep: rim band=%.1f cells=%d off_level=%d max_off=%.2f" % [band, cells, off,
			worst])
	for note: String in notes:
		print("Relief sweep detail: %s" % note)


## El barrido `edge`.
static func edge(terrain: Terrain, ground_shader_path: String) -> void:
	var outside := terrain.outside_relief()
	if outside == null:
		print("Relief sweep: edge outside=none")
		return
	var view := terrain.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var material := "other"
	var shader := view.material_override as ShaderMaterial if view != null else null
	if shader != null and shader.shader != null \
			and shader.shader.resource_path == ground_shader_path:
		material = "terrain"
	var half := terrain.size * 0.5
	var samples := 0
	var bad := 0
	var seam := 0.0
	var notes: Array[String] = []
	for side: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var along := Vector2(-side.y, side.x)
		var run := -half
		while run <= half + 0.001:
			var wall := side * half + along * run
			var gap := absf(terrain.outside_height_at(wall.x + side.x * SEAM_OUT,
					wall.y + side.y * SEAM_OUT) - terrain.height_at(wall.x, wall.y))
			samples += 1
			seam = maxf(seam, gap)
			if gap > SEAM_LIMIT:
				bad += 1
				if notes.size() < DETAIL_LIMIT:
					notes.append("edge seam %.3f at (%.1f, %.1f)" % [gap, wall.x, wall.y])
			run += SEAM_STEP
	# La malla misma: tiene que seguir pasado el muro y pegada a la función.
	var mesh_gap := _mesh_gap(view, terrain, half)
	if mesh_gap > SEAM_LIMIT:
		bad += 1
		if notes.size() < DETAIL_LIMIT:
			notes.append("edge mesh missing past the wall" if is_inf(mesh_gap)
					else "edge mesh off the outside height by %.3f" % mesh_gap)
	print("Relief sweep: edge material=%s reach=%.1f seam_max=%.3f mesh_max=%.3f samples=%d bad=%d" % [
			material, outside.reach, seam, mesh_gap, samples, bad])
	for note: String in notes:
		print("Relief sweep detail: %s" % note)


## Cuánto se aparta, como mucho, un vértice de la malla del Terrain que cae
## afuera del muro de la altura que da OutsideRelief en su lugar.
static func _mesh_gap(view: MeshInstance3D, terrain: Terrain, half: float) -> float:
	if view == null or view.mesh == null:
		return INF
	var vertices: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	var outside := 0
	for vertex: Vector3 in vertices:
		if absf(vertex.x) <= half and absf(vertex.z) <= half:
			continue
		outside += 1
		worst = maxf(worst, absf(vertex.y - terrain.outside_height_at(vertex.x, vertex.z)))
	return worst if outside > 0 else INF
