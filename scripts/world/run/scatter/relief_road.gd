class_name ReliefRoad
extends RefCounted
## El CAMINO ANTIGUO del relieve por zonas: losas gastadas que salen del
## punto de aparición y llevan a la pieza que importa. En la Montaña
## Escalonada bajan por la rampa del macizo que queda más cerca del puente,
## llegan a su cabecera y siguen un trecho por la otra orilla hasta perderse
## en el bosque; en las otras recetas siguen los tramos que dejó la receta
## (ReliefLayout.road_legs: al puente, al muelle de la isla, por el paso).
## Cada tantos metros lleva un farol de piedra. Puede faltar: la receta lo
## sortea con ReliefSettings.road_chance (la pieza opcional "road").
##
## Las losas no tienen colisión; cada farol es un poste que se rodea. Todo
## cuelga del scatter (arde con el bosque en el infierno de Mythos) y entra
## al grupo ReliefStructures.GROUP. No saca números del RNG de la partida:
## se siembra con la semilla que le pasan.

# --- edita aquí --------------------------------------------------------------
## Ancho del camino y metros entre una fila de losas y la siguiente.
const WIDTH: float = 3.4
const ROW_STEP: float = 1.3
## Fracción de losas que faltan (un camino viejo), al empezar y al final del
## trecho de la otra orilla, donde el camino se pierde.
const GAPS: float = 0.12
const GAPS_AT_END: float = 0.75
## Metros que las losas se levantan del suelo, para que no parpadeen contra él.
const LIFT: float = 0.07
## Metros del punto de aparición donde arranca, y metros que sigue pasada
## la cabecera de la otra orilla.
const START: float = 7.0
const BEYOND: float = 28.0
## Metros que el camino guarda con el pie del macizo y con el borde del cañón.
const FROM_CLIFF: float = 6.0
const FROM_CANYON: float = 5.0
## Faroles: cada cuántos metros, a cuántos del eje del camino, su altura y
## metros que guardan con una cabecera del puente.
const LAMP_EVERY: float = 15.0
const LAMP_ASIDE: float = 2.7
const LAMP_HEIGHT: float = 3.1
const LAMP_FROM_HEAD: float = 9.0
## Radio del claro que reserva cada farol: nada se coloca encima de su poste.
const LAMP_KEEPOUT: float = 1.2
## Radio del claro que el camino reserva (ni props ni pasto encima) y cada
## cuántos metros anota uno.
const KEEPOUT: float = 2.9
const KEEPOUT_STEP: float = 3.5
## Colores: la losa, el musgo de sus bordes, la piedra del farol y su luz.
const SLAB := Color(0.63, 0.62, 0.57)
const MOSS := Color(0.42, 0.56, 0.36)
const LAMP_STONE := Color(0.5, 0.51, 0.5)
const LAMP_GLOW := Color(1.0, 0.8, 0.42)
# -----------------------------------------------------------------------------


## Tiende el camino de `terrain` como hijo de `scatter` y devuelve los claros
## que reserva, como (x, radio, z). Sin tramos (una receta que sorteó no
## tener camino, o la montaña sin puente) no hay camino.
static func raise(scatter: Node3D, terrain: Terrain, run_seed: int) -> PackedVector3Array:
	var claimed := PackedVector3Array()
	var layout := terrain.relief_layout()
	var legs := _legs(layout)
	if legs.is_empty():
		return claimed
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ 0x524F4144
	var slabs := LowPolyMesh.new(run_seed)
	var lamps: Array[Vector3] = []
	for leg: Dictionary in legs:
		_pave(scatter, terrain, layout, rng, slabs, leg["points"], bool(leg["fading"]), lamps,
				claimed)
	if slabs.is_empty():
		return claimed
	var view := slabs.instance("Road")
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_to_group(ReliefStructures.GROUP)
	scatter.add_child(view)
	_raise_lamps(scatter, lamps, run_seed)
	return claimed


## Los tramos del camino: {points, fading}. Los de la receta, o los de la
## Montaña Escalonada (del macizo al primer puente y un trecho más allá).
static func _legs(layout: ReliefLayout) -> Array[Dictionary]:
	if not layout.road_legs.is_empty():
		return layout.road_legs
	var legs: Array[Dictionary] = []
	if layout.recipe != &"massif" or not bool(layout.options.get("road", true)) \
			or layout.crossings.is_empty() or layout.zones.is_empty():
		return legs
	var crossing := layout.crossings[0]
	var massif := layout.zones[0]
	var near := crossing.head_a
	var far := crossing.head_b
	if far.distance_to(massif.center) < near.distance_to(massif.center):
		near = crossing.head_b
		far = crossing.head_a
	var onward := (far - near).normalized()
	legs.append({"points": _way_down(layout, massif, near), "fading": false})
	legs.append({"points": PackedVector2Array([far, far + onward * BEYOND]), "fading": true})
	return legs


## El trecho del lado de la montaña: del punto de aparición a la rampa del
## macizo más cercana a `head`, rampa abajo, y por el llano hasta `head`.
static func _way_down(layout: ReliefLayout, massif: ReliefLayout.Zone,
		head: Vector2) -> PackedVector2Array:
	var way := PackedVector2Array()
	var best: ReliefLayout.Ramp = null
	for ramp: ReliefLayout.Ramp in massif.ramps:
		if best == null or (ramp.origin + ramp.dir * ramp.length).distance_to(head) \
				< (best.origin + best.dir * best.length).distance_to(head):
			best = ramp
	if best == null:
		return way
	var top := best.origin - best.dir * 2.0
	var foot := best.origin + best.dir * (best.length + 3.0)
	way.append(top.normalized() * START if top.length() > START else top)
	way.append(top)
	way.append(foot)
	# Por el llano, entre el pie del macizo y el cañón: nunca sobre un corte.
	for step in range(1, 6):
		var point := foot.lerp(head, float(step) / 6.0)
		var rel := point - massif.center
		var rim := layout.polar(massif.radii, rel.angle()) + FROM_CLIFF
		if rel.length() < rim:
			point = massif.center + rel.normalized() * rim
		var coords := layout.ravine_coords(point)
		if coords.x >= 0.0 and coords.y < layout.ravine.half_width + FROM_CANYON:
			point += (massif.center - point).normalized() \
					* (layout.ravine.half_width + FROM_CANYON - coords.y)
		way.append(point)
	way.append(head)
	return way


## Pone las losas de un trecho, anota sus claros y dónde van sus faroles.
## Con `fading`, el camino se va perdiendo hacia el final.
static func _pave(scatter: Node3D, terrain: Terrain, layout: ReliefLayout,
		rng: RandomNumberGenerator, slabs: LowPolyMesh, way: PackedVector2Array, fading: bool,
		lamps: Array[Vector3], claimed: PackedVector3Array) -> void:
	var total := 0.0
	for index in way.size() - 1:
		total += way[index].distance_to(way[index + 1])
	if total < ROW_STEP:
		return
	var walked := 0.0
	var next_lamp := LAMP_EVERY * 0.5
	var next_site := 0.0
	var lamp_side := 1.0
	for index in way.size() - 1:
		var from := way[index]
		var to := way[index + 1]
		var along := (to - from).normalized()
		var side := Vector2(-along.y, along.x)
		var rows := maxi(roundi(from.distance_to(to) / ROW_STEP), 1)
		var step := from.distance_to(to) / float(rows)
		for row in rows:
			var center := from + along * (step * (float(row) + 0.5))
			walked += step
			if not bool(scatter.call(&"is_walkable", center)) or layout.level_at(center) < 0 \
					or (fading and layout.level_at(center) != 0):
				continue
			var gaps := lerpf(GAPS, GAPS_AT_END, walked / total) if fading else GAPS
			_row(terrain, rng, slabs, center, along * (step * 0.47), side, gaps)
			if walked >= next_site:
				next_site = walked + KEEPOUT_STEP
				claimed.append(Vector3(center.x, KEEPOUT, center.y))
			if walked >= next_lamp:
				next_lamp = walked + LAMP_EVERY
				lamp_side = -lamp_side
				var post := center + side * (LAMP_ASIDE * lamp_side)
				if _head_distance(layout, post) > LAMP_FROM_HEAD \
						and layout.level_at(post) == layout.level_at(center) \
						and terrain.relief_distance(post, 4.0) >= 4.0:
					lamps.append(Vector3(post.x, terrain.height_at(post.x, post.y), post.y))
					claimed.append(Vector3(post.x, LAMP_KEEPOUT, post.y))


## Metros de `point` a la cabecera de puente más cercana (INF sin puentes).
static func _head_distance(layout: ReliefLayout, point: Vector2) -> float:
	var nearest := INF
	for crossing: ReliefLayout.Crossing in layout.crossings:
		nearest = minf(nearest, minf(point.distance_to(crossing.head_a),
				point.distance_to(crossing.head_b)))
	return nearest


## Una fila del camino: dos losas con la junta corrida, cada una apoyada en
## el suelo por sus cuatro esquinas. Alguna falta.
static func _row(terrain: Terrain, rng: RandomNumberGenerator, slabs: LowPolyMesh,
		center: Vector2, half_step: Vector2, side: Vector2, gaps: float) -> void:
	var half := WIDTH * 0.5 * rng.randf_range(0.86, 1.08)
	var joint := rng.randf_range(-0.55, 0.55)
	var shift := rng.randf_range(-0.2, 0.2)
	for part: Vector2 in [Vector2(-half, joint - 0.06), Vector2(joint + 0.06, half)]:
		if rng.randf() < gaps:
			continue
		var tone := SLAB.lerp(MOSS, rng.randf_range(0.0, 0.35))
		var corners := PackedVector3Array()
		for corner: Vector2 in [Vector2(-1.0, part.x), Vector2(1.0, part.x),
				Vector2(1.0, part.y), Vector2(-1.0, part.y)]:
			var xz := center + half_step * corner.x + side * (corner.y + shift)
			corners.append(Vector3(xz.x, terrain.height_at(xz.x, xz.y) + LIFT, xz.y))
		slabs.plate(corners[0], corners[1], corners[2], corners[3], tone,
				corners[0] + Vector3.DOWN)


## Los faroles: un solo cuerpo con un poste de colisión por farol, la malla
## de piedra de todos y la de sus luces.
static func _raise_lamps(scatter: Node3D, lamps: Array[Vector3], run_seed: int) -> void:
	if lamps.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "RoadLamps"
	body.add_to_group(ReliefStructures.GROUP)
	scatter.add_child(body)
	var stone := LowPolyMesh.new(run_seed + 3)
	var glow := LowPolyMesh.new(run_seed + 5)
	for foot: Vector3 in lamps:
		var post := CylinderShape3D.new()
		post.radius = 0.38
		post.height = LAMP_HEIGHT
		var holder := CollisionShape3D.new()
		holder.shape = post
		holder.position = foot + Vector3.UP * (LAMP_HEIGHT * 0.5)
		body.add_child(holder)
		var frame := Transform3D(Basis.IDENTITY, foot)
		stone.block(frame.translated(Vector3(0.0, 0.1, 0.0)), Vector3(1.0, 0.9, 1.0), LAMP_STONE)
		stone.block(frame.translated(Vector3(0.0, LAMP_HEIGHT * 0.42, 0.0)),
				Vector3(0.5, LAMP_HEIGHT * 0.84, 0.5), LAMP_STONE)
		stone.block(frame.translated(Vector3(0.0, LAMP_HEIGHT - 0.78, 0.0)),
				Vector3(0.95, 0.16, 0.95), LAMP_STONE)
		glow.block(frame.translated(Vector3(0.0, LAMP_HEIGHT - 0.45, 0.0)),
				Vector3(0.6, 0.5, 0.6), LAMP_GLOW)
		var roof := stone.ring(foot + Vector3.UP * (LAMP_HEIGHT - 0.2), 0.72, 4, PI * 0.25)
		for index in 4:
			stone.triangle(roof[index], roof[(index + 1) % 4],
					foot + Vector3.UP * (LAMP_HEIGHT + 0.42), LAMP_STONE, foot)
	body.add_child(stone.instance("Stone"))
	var light := glow.instance("Glow")
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.vertex_color_use_as_albedo = true
	light.material_override = shine
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(light)
