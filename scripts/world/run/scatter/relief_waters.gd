class_name ReliefWaters
extends RefCounted
## El agua del relieve por zonas: el RÍO que llena el fondo del cañón (o el
## lago, que es un cañón que se ensancha) y la CASCADA que lo alimenta. La
## cascada nace en un manantial sobre la zona que diga la receta
## (ReliefLayout.cascade_zone: el macizo en la Montaña Escalonada, la
## meseta-manantial en el Gran Río), cae por su acantilado a una poza, cruza
## el llano como arroyo y vuelve a caer al cañón. Sin esa zona no hay cascada.
##
## Todo es malla sin colisión, hija del scatter (así arde con el bosque en
## el infierno de Mythos) y del grupo ReliefStructures.GROUP. El material
## del agua quieta viene del ReliefSettings de la arena (`water_material`);
## vacío, no hay agua. No saca números de ningún RNG.

# --- edita aquí --------------------------------------------------------------
## El río: metros que se mete bajo las paredes del cañón, metros sobre el
## punto más alto de su fondo y metros que se recorta en cada punta.
const RIVER_MARGIN: float = 0.6
const RIVER_DEPTH: float = 0.16
const RIVER_TRIM: float = 2.5
## Metros a lo largo del cañón entre la cascada y el puente: se prueba cada
## distancia en orden y se queda con la primera donde cabe.
const CASCADE_APART: Array[float] = [40.0, 46.0, 34.0, 52.0, 28.0, 58.0, 64.0, 22.0]
## Lo más lejos que puede quedar el macizo del cañón, en metros.
const STRIP_MAX: float = 42.0
## Metros entre el manantial y el borde del macizo, y radio del manantial.
const SPRING_INSET: float = 9.0
const SPRING_RADIUS: float = 3.2
## Radio de la poza al pie de la primera caída.
const POOL_RADIUS: float = 3.0
## Ancho del arroyo y de las caídas, en metros.
const STREAM_WIDTH: float = 2.6
const FALL_WIDTH: float = 4.2
## Metros pasado el borde donde el agua deja la roca (la cornisa del corte
## asoma eso), y metros del borde a los que cae: lo que se inclina la roca
## más un poco de aire.
const FALL_LIP: float = 2.3
const FALL_REACH: float = 5.8
## Metros que el agua se levanta del suelo, para que no parpadee contra él.
const LIFT: float = 0.1
## Nenúfares: uno cada tantos metros de río, y su radio (mínimo y máximo).
const PAD_EVERY: float = 4.5
const PAD_RADIUS := Vector2(0.45, 0.95)
## Juncos: una mata cada tantos metros de cada orilla, y su alto (mínimo y máximo).
const REEDS_EVERY: float = 7.0
const REED_HEIGHT := Vector2(1.2, 2.3)
## Metros que nenúfares y juncos guardan con el puente.
const LIFE_FROM_BRIDGE: float = 16.0
## Colores: la hoja del nenúfar, su flor y el junco.
const PAD := Color(0.3, 0.6, 0.36)
const PAD_FLOWER := Color(0.97, 0.76, 0.84)
const REED := Color(0.42, 0.58, 0.3)
## Color del agua que cae, color de la espuma y copos de espuma por caída.
const RAPIDS := Color(0.74, 0.9, 0.96)
const FOAM := Color(0.97, 0.99, 1.0)
const FLAKES: int = 7
# -----------------------------------------------------------------------------


## Levanta el agua de `terrain` como hija de `scatter`. `run_seed` siembra
## dónde crecen los nenúfares y los juncos. Anota en `pieces` el río
## ("river") y la cascada ("waterfall") si los puso.
static func raise(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		run_seed: int, pieces: Dictionary = {}) -> void:
	var material := layout.settings.water_material
	if material == null or layout.ravine == null:
		return
	var level := _place_river(scatter, terrain, layout, material)
	if level == -INF:
		return
	pieces["river"] = 1
	_place_life(scatter, terrain, layout, level, run_seed)
	if not layout.settings.cascade or layout.cascade_zone < 0:
		return
	var spot := cascade_spot(layout)
	if spot.is_empty():
		print("Relief waters: no room for the cascade off zone %d" % (layout.cascade_zone + 1))
		return
	_place_cascade(scatter, terrain, material, spot, level)
	pieces["waterfall"] = 1


# --- el río ------------------------------------------------------------------------

## Una cinta de agua por tramo hondo del cañón, a nivel, apenas sobre el
## punto más alto de ese tramo. Devuelve el nivel del tramo más largo, o
## -INF si no hubo ninguno.
static func _place_river(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		material: Material) -> float:
	var ravine := layout.ravine
	var runs: Array[Vector2] = []
	var run_from := -1.0
	var along := 0.0
	while along <= ravine.length + 1.0:
		var deep := along <= ravine.length \
				and layout.ravine_drop(along) >= ravine.depth - 0.01
		if deep and run_from < 0.0:
			run_from = along
		elif not deep and run_from >= 0.0:
			runs.append(Vector2(run_from + RIVER_TRIM, along - 1.0 - RIVER_TRIM))
			run_from = -1.0
		along += 1.0
	var longest := 0.0
	var answer := -INF
	for index in runs.size():
		var run := runs[index]
		if run.y - run.x < 4.0:
			continue
		var water := LowPolyMesh.new()
		var level := -INF
		var s := run.x
		while s <= run.y + 0.01:
			var frame := layout.ravine_frame(s)
			level = maxf(level, terrain.height_at(frame[0].x, frame[0].y))
			s += 2.0
		level += RIVER_DEPTH
		var before := PackedVector3Array()
		s = run.x
		while s <= run.y + 0.01:
			var frame := layout.ravine_frame(s)
			var side := Vector2(-frame[1].y, frame[1].x) * (ravine.half_at(s) + RIVER_MARGIN)
			var row := PackedVector3Array([
				Vector3(frame[0].x + side.x, level, frame[0].y + side.y),
				Vector3(frame[0].x - side.x, level, frame[0].y - side.y)])
			if not before.is_empty():
				water.quad(before[0], before[1], row[1], row[0], Color.WHITE,
						before[0] + Vector3.DOWN)
			before = row
			s += 2.0
		_hang(scatter, water, "Water%d" % (index + 1), material)
		if run.y - run.x > longest:
			longest = run.y - run.x
			answer = level
	return answer


## La vida del río: nenúfares sobre el agua y matas de juncos al pie de las
## dos paredes, lejos del puente. Una sola malla, sin colisión.
static func _place_life(scatter: Node3D, terrain: Terrain, layout: ReliefLayout, level: float,
		run_seed: int) -> void:
	var ravine := layout.ravine
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ 0x52495645
	var life := LowPolyMesh.new(run_seed + 11)
	var from := ravine.ramp + 4.0
	var to := ravine.length - ravine.ramp - 4.0
	var along := from
	while along < to:
		var frame := layout.ravine_frame(along)
		var side := Vector2(-frame[1].y, frame[1].x)
		var clear := true
		for crossing: ReliefLayout.Crossing in layout.crossings:
			if absf(along - crossing.s) < crossing.width * 0.5 + LIFE_FROM_BRIDGE:
				clear = false
		var wide := ravine.half_at(along)
		if clear and rng.randf() < 1.0 / PAD_EVERY:
			var at := frame[0] + side * rng.randf_range(-1.0, 1.0) * (wide - 4.0)
			# Solo sobre el agua: una isla asoma en medio del lago.
			if terrain.height_at(at.x, at.y) < level:
				_pad(life, rng, Vector3(at.x, level + 0.03, at.y))
		if clear and rng.randf() < 2.0 / REEDS_EVERY:
			var bank := 1.0 if rng.randf() < 0.5 else -1.0
			var at := frame[0] + side * bank * (wide - rng.randf_range(3.6, 5.2))
			# Solo donde el agua tapa el suelo: un junco no crece en seco.
			if terrain.height_at(at.x, at.y) < level:
				_reeds(life, rng, Vector3(at.x, level - 0.1, at.y))
		along += 1.0
	if life.is_empty():
		return
	var view := life.instance("RiverLife")
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_to_group(ReliefStructures.GROUP)
	scatter.add_child(view)


## Un nenúfar: una hoja redonda con una muesca y, a veces, su flor.
static func _pad(life: LowPolyMesh, rng: RandomNumberGenerator, center: Vector3) -> void:
	var radius := rng.randf_range(PAD_RADIUS.x, PAD_RADIUS.y)
	var rim := life.ring(center, radius, 8, rng.randf() * TAU)
	for index in rim.size() - 1:
		life.triangle(center, rim[index], rim[index + 1], PAD, center + Vector3.DOWN)
	if rng.randf() < 0.3:
		life.blob(center + Vector3.UP * 0.12, Vector3(0.2, 0.16, 0.2), PAD_FLOWER, 5, 3, 0.1)


## Una mata de juncos: varias hojas finas y altas que salen del agua.
static func _reeds(life: LowPolyMesh, rng: RandomNumberGenerator, center: Vector3) -> void:
	for blade in rng.randi_range(5, 8):
		var foot := center + Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var height := rng.randf_range(REED_HEIGHT.x, REED_HEIGHT.y)
		var angle := rng.randf() * TAU
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.07
		var tip := foot + Vector3(rng.randf_range(-0.25, 0.25), height, rng.randf_range(-0.25, 0.25))
		life.triangle(foot + side, foot - side, tip, REED, foot + Vector3(-side.z, 0.0, side.x) * 9.0)
		life.triangle(foot - side, foot + side, tip, REED, foot - Vector3(-side.z, 0.0, side.x) * 9.0)


# --- la cascada --------------------------------------------------------------------

## Dónde cabe la cascada: {rim, dir, strip} con el borde del cañón del lado
## de la zona que la alimenta (XZ), la dirección hacia ella y los metros de
## llano hasta su borde. Vacío si no cabe en ningún lado. En la Montaña
## Escalonada se busca a unas distancias del puente (que se vea desde él);
## en las otras recetas, frente a la zona que la alimenta. Público para el
## planificador: una meseta-manantial solo se queda si su cascada cabe.
static func cascade_spot(layout: ReliefLayout) -> Dictionary:
	var ravine := layout.ravine
	var source := layout.zones[layout.cascade_zone]
	var low := ravine.ramp + 8.0
	var high := ravine.length - ravine.ramp - 8.0
	for s: float in _cascade_candidates(layout, source):
		if s < low or s > high:
			continue
		var frame := layout.ravine_frame(s)
		var normal := Vector2(-frame[1].y, frame[1].x)
		var dir := normal * signf((source.center - frame[0]).dot(normal))
		var rim := frame[0] + dir * ravine.half_at(s)
		var strip := _strip_to(layout, layout.cascade_zone, rim, dir)
		if strip > 0.0:
			return {"rim": rim, "dir": dir, "strip": strip}
	return {}


## Los lugares del eje del cañón donde se prueba la cascada, en orden.
static func _cascade_candidates(layout: ReliefLayout, source: ReliefLayout.Zone) -> PackedFloat32Array:
	var ravine := layout.ravine
	var out := PackedFloat32Array()
	if layout.recipe == &"massif":
		var bridge := ravine.length * 0.5
		if not layout.crossings.is_empty():
			bridge = layout.crossings[0].s
		# Primero hacia el lado del cañón donde queda más tramo.
		var roomy := 1.0 if ravine.length - bridge > bridge else -1.0
		for apart: float in CASCADE_APART:
			for turn: float in [roomy, -roomy]:
				out.append(bridge + turn * apart)
		return out
	var facing := layout.ravine_coords(source.center).x
	if facing < 0.0:
		# La zona queda más allá de una punta: se mira desde la punta más cercana.
		facing = 0.0 if source.center.distance_to(ravine.points[0]) \
				< source.center.distance_to(ravine.points[ravine.points.size() - 1]) else ravine.length
	for apart: float in [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0]:
		out.append(facing + apart)
	return out


## Metros de llano desde `rim` hacia `dir` hasta el acantilado de la zona de
## índice `zone_index`, o -1 si en ese rumbo no hay un acantilado limpio:
## queda lejos, cae en una rampa o no deja lugar para la poza.
static func _strip_to(layout: ReliefLayout, zone_index: int, rim: Vector2,
		dir: Vector2) -> float:
	var massif := layout.zones[zone_index]
	var side := Vector2(-dir.y, dir.x)
	var reach := 1.0
	while reach <= STRIP_MAX:
		if layout.raised_offset(massif, rim + dir * reach) >= 0.0:
			break
		reach += 0.5
	if reach > STRIP_MAX or reach < FALL_REACH + POOL_RADIUS * 2.0 + 1.5:
		return -1.0
	# Meseta entera arriba y llano entero abajo, también a los costados: ni
	# una rampa ni la esquina de otra zona.
	for aside: float in [-FALL_WIDTH, 0.0, FALL_WIDTH]:
		var column := rim + side * aside
		if layout.raised_offset(massif, column + dir * (reach + 2.5)) < massif.height - 0.01:
			return -1.0
		if layout.level_at(column + dir * (reach - 2.5)) != 0 \
				or layout.level_at(column + dir * (reach * 0.5)) != 0:
			return -1.0
	if layout.level_at(rim + dir * (reach + SPRING_INSET + SPRING_RADIUS)) != zone_index + 1:
		return -1.0
	return reach


## Las piezas de la cascada en `spot` (ver cascade_spot), con el río a `level`.
static func _place_cascade(scatter: Node3D, terrain: Terrain, material: Material,
		spot: Dictionary, level: float) -> void:
	var rim: Vector2 = spot["rim"]
	var dir: Vector2 = spot["dir"]
	var strip: float = spot["strip"]
	var cliff := rim + dir * strip
	var spring := cliff + dir * SPRING_INSET
	var pool := cliff - dir * (FALL_REACH + POOL_RADIUS - 1.0)
	var still := LowPolyMesh.new()
	var white := LowPolyMesh.new()
	_disc(still, _on_ground(terrain, spring), SPRING_RADIUS)
	_stream(still, terrain, spring, cliff)
	_disc(still, _on_ground(terrain, pool), POOL_RADIUS)
	_stream(still, terrain, pool, rim)
	var upper := _fall(white, _on_ground(terrain, cliff), -dir,
			terrain.height_at(pool.x, pool.y) + LIFT)
	var lower := _fall(white, _on_ground(terrain, rim), -dir, level + 0.04)
	_disc(white, upper[upper.size() - 1] + Vector3.UP * 0.05, FALL_WIDTH * 0.62)
	_disc(white, lower[lower.size() - 1] + Vector3.UP * 0.05, FALL_WIDTH * 0.8)
	_hang(scatter, still, "Cascade", material)
	var rapids := StandardMaterial3D.new()
	rapids.albedo_color = RAPIDS
	rapids.roughness = 0.4
	var foam := StandardMaterial3D.new()
	foam.albedo_color = FOAM
	foam.roughness = 0.9
	var falls := _hang(scatter, white, "CascadeFalls", rapids)
	for path: PackedVector3Array in [upper, lower]:
		var flow := CascadeFlow.new()
		flow.name = "CascadeFlow"
		falls.add_child(flow)
		flow.setup(path, FLAKES, FALL_WIDTH * 0.5, foam)


## Una caída: la cinta de agua blanca que sale de `top`, se despega
## FALL_REACH metros hacia `out` y baja hasta la altura `foot`. Devuelve su
## línea, de arriba abajo.
static func _fall(mesh: LowPolyMesh, top: Vector3, out: Vector2, foot: float) -> PackedVector3Array:
	var away := Vector3(out.x, 0.0, out.y)
	var side := Vector3(-out.y, 0.0, out.x) * (FALL_WIDTH * 0.5)
	var drop := top.y - foot
	# (metros desde el borde, caída en fracción): corre por la cornisa hasta
	# el labio, salta y cae cada vez más a pique.
	var leap := FALL_REACH - FALL_LIP
	var profile: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(FALL_LIP, 0.0),
			Vector2(FALL_LIP + leap * 0.3, 0.14), Vector2(FALL_LIP + leap * 0.6, 0.45),
			Vector2(FALL_LIP + leap * 0.85, 0.78), Vector2(FALL_REACH, 1.0)]
	var line := PackedVector3Array()
	for point: Vector2 in profile:
		line.append(top + away * point.x + Vector3.DOWN * (drop * point.y))
	for index in line.size() - 1:
		mesh.quad(line[index] - side, line[index] + side, line[index + 1] + side,
				line[index + 1] - side, Color.WHITE, line[index] - away + Vector3.DOWN)
	return line


## Un arroyo: una cinta apoyada en el suelo de `from` a `to` (XZ).
static func _stream(mesh: LowPolyMesh, terrain: Terrain, from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var steps := maxi(ceili(length), 1)
	var across := (to - from).normalized()
	var side := Vector3(-across.y, 0.0, across.x) * (STREAM_WIDTH * 0.5)
	var before := _on_ground(terrain, from)
	for step in range(1, steps + 1):
		var here := _on_ground(terrain, from.lerp(to, float(step) / float(steps)))
		mesh.quad(before - side, before + side, here + side, here - side, Color.WHITE,
				before + Vector3.DOWN)
		before = here


## Un charco redondo de radio `radius` con el centro en `center`.
static func _disc(mesh: LowPolyMesh, center: Vector3, radius: float) -> void:
	mesh.cap(mesh.ring(center, radius, 9, 0.2), Color.WHITE, center + Vector3.DOWN)


## `xz` apoyado en el suelo, LIFT metros arriba.
static func _on_ground(terrain: Terrain, xz: Vector2) -> Vector3:
	return Vector3(xz.x, terrain.height_at(xz.x, xz.y) + LIFT, xz.y)


## Cuelga la malla de `mesh` de `scatter` con `material`, sin sombra propia.
static func _hang(scatter: Node3D, mesh: LowPolyMesh, node_name: String,
		material: Material) -> MeshInstance3D:
	var view := mesh.instance(node_name)
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_to_group(ReliefStructures.GROUP)
	scatter.add_child(view)
	return view
