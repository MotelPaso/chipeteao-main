extends RefCounted
## El BOSQUE PROFUNDO de afuera (ver ForestEdge): un manto de copas sobre las
## lomas de OutsideRelief, desde el fondo de la franja hasta el horizonte, con
## pinos que asoman y algún peñasco. Una malla por trozo de la cuadrícula,
## colgada del Backdrop con el material propio del ForestEdge (HellSky lo tiñe
## con el horizonte). Los vértices caen en una cuadrícula común a todos los
## trozos: dos vecinos comparten su borde sin rendija. Los valores son
## exports de ForestEdge (grupo «Bosque profundo»); ninguna escena usa este
## script.

## Tipo de trozo para su semilla (ver ForestEdge.chunk_seed).
const SEED_KIND: int = 2
## Metros bajo el suelo a los que baja el manto antes de su borde: así su
## frente sale de la tierra y no queda una rendija.
const SINK: float = 0.8
## Metros antes de `far_radius` en que el manto empieza a bajar al suelo.
const OUTER_FADE: float = 60.0


## Los trozos del manto que tienen algo: los que cruzan el borde del manto o
## quedan afuera de él, hasta far_radius.
static func jobs(edge: ForestEdge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var outside := edge.outside()
	var per_side := ceili(edge.far_radius * 2.0 / edge.far_chunk)
	var inner := edge.canopy_from - edge.canopy_from_jitter - edge.canopy_step * 2.0
	for iz in per_side:
		for ix in per_side:
			var low := Vector2(-edge.far_radius + float(ix) * edge.far_chunk,
					-edge.far_radius + float(iz) * edge.far_chunk)
			var high := low + Vector2.ONE * edge.far_chunk
			# La esquina del trozo más lejos de la arena: si ni ella pasa del
			# borde del manto, el trozo queda adentro.
			var far_x := maxf(absf(low.x), absf(high.x))
			var far_z := maxf(absf(low.y), absf(high.y))
			if outside.distance_out(far_x, far_z) < inner:
				continue
			var near := Vector2(clampf(0.0, low.x, high.x), clampf(0.0, low.y, high.y))
			if near.length() > edge.far_radius:
				continue
			out.append({"kind": "far", "ix": ix, "iz": iz})
	return out


## Arma el trozo `job` del manto como hijo de `backdrop`.
static func build(edge: ForestEdge, job: Dictionary, backdrop: Node3D) -> void:
	var outside := edge.outside()
	var ix := int(job["ix"])
	var iz := int(job["iz"])
	var rng := RandomNumberGenerator.new()
	rng.seed = edge.chunk_seed(SEED_KIND, ix, iz)
	var mesh := LowPolyMesh.new(rng.randi())
	var steps := maxi(roundi(edge.far_chunk / edge.canopy_step), 1)
	var low := Vector2(-edge.far_radius + float(ix) * edge.far_chunk,
			-edge.far_radius + float(iz) * edge.far_chunk)
	var points := PackedVector3Array()
	var lifts := PackedFloat32Array()
	points.resize((steps + 1) * (steps + 1))
	lifts.resize(points.size())
	for gz in steps + 1:
		for gx in steps + 1:
			var x := low.x + float(gx) * edge.canopy_step
			var z := low.y + float(gz) * edge.canopy_step
			var lift := _lift(edge, outside, x, z)
			var ground := outside.height_at(x, z)
			var crown := edge.canopy_height + edge.canopy_bumps * edge.bump_noise().get_noise_2d(x, z)
			points[gz * (steps + 1) + gx] = Vector3(x, ground + lift * crown - (1.0 - lift) * SINK, z)
			lifts[gz * (steps + 1) + gx] = lift
	for gz in steps:
		for gx in steps:
			var a := gz * (steps + 1) + gx
			var corners: Array[int] = [a, a + 1, a + steps + 2, a + steps + 1]
			var most := 0.0
			for corner: int in corners:
				most = maxf(most, lifts[corner])
			if most < 0.01:
				continue
			var tone := edge.canopy_dark.lerp(edge.canopy_bright, rng.randf()) \
					.darkened(0.25 * (1.0 - most))
			var below := (points[corners[0]] + points[corners[2]]) * 0.5 + Vector3.DOWN * 4.0
			mesh.quad(points[corners[0]], points[corners[1]], points[corners[2]],
					points[corners[3]], tone, below)
	if mesh.is_empty():
		return
	_spires(edge, mesh, rng, outside, low)
	_crags(edge, mesh, rng, outside, low)
	edge.tally("far", 1)
	edge.tally("faces", mesh.face_count())
	var view := mesh.instance("FarForest_%d_%d" % [ix, iz])
	view.material_override = edge.far_material()
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(view)


## Cuánto manto hay en (x, z), de 0 (nada: antes de su borde, o pasado el
## horizonte) a 1 (el manto entero).
static func _lift(edge: ForestEdge, outside: OutsideRelief, x: float, z: float) -> float:
	var d := outside.distance_out(x, z)
	if d <= 0.0:
		return 0.0
	var t := outside.perimeter_param(x, z)
	var from := edge.canopy_from + edge.canopy_from_jitter * edge.edge_noise().get_noise_1d(t)
	var reach := Vector2(x, z).length()
	return smoothstep(from, from + edge.canopy_rise, d) \
			* (1.0 - smoothstep(edge.far_radius - OUTER_FADE, edge.far_radius, reach))


## Los pinos que asoman sobre el manto: un cono alto sobre las copas.
static func _spires(edge: ForestEdge, mesh: LowPolyMesh, rng: RandomNumberGenerator,
		outside: OutsideRelief, low: Vector2) -> void:
	for spire in edge.spires_per_chunk:
		var x := low.x + rng.randf() * edge.far_chunk
		var z := low.y + rng.randf() * edge.far_chunk
		var lift := _lift(edge, outside, x, z)
		if lift < 0.9:
			continue
		var top := outside.height_at(x, z) + lift * edge.canopy_height
		var height := rng.randf_range(5.0, 11.0)
		var base := Vector3(x, top - 1.5, z)
		var rim := mesh.ring(base, rng.randf_range(2.0, 3.4), 5, rng.randf() * TAU, 0.1)
		var apex := base + Vector3.UP * height
		var tone := edge.spire_color.lerp(edge.canopy_bright, rng.randf_range(0.0, 0.4))
		for side in rim.size():
			mesh.triangle(apex, rim[side], rim[(side + 1) % rim.size()], tone,
					base + Vector3.UP * 0.5)


## Algún peñasco que asoma del manto: roca facetada a medio enterrar en las copas.
static func _crags(edge: ForestEdge, mesh: LowPolyMesh, rng: RandomNumberGenerator,
		outside: OutsideRelief, low: Vector2) -> void:
	for crag in edge.crags_per_chunk:
		if rng.randf() > 0.4:
			continue
		var x := low.x + rng.randf_range(0.2, 0.8) * edge.far_chunk
		var z := low.y + rng.randf_range(0.2, 0.8) * edge.far_chunk
		var lift := _lift(edge, outside, x, z)
		if lift < 0.95:
			continue
		var size := rng.randf_range(7.0, 13.0)
		var top := outside.height_at(x, z) + edge.canopy_height
		mesh.blob(Vector3(x, top - size * 0.2, z),
				Vector3(size, size * rng.randf_range(0.8, 1.3), size * rng.randf_range(0.7, 1.0)),
				edge.crag_color, 7, 4, 0.22)
		edge.tally("rocks", 1)
