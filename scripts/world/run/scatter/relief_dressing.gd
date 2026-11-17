class_name ReliefDressing
extends RefCounted
## Lo que el scatter hace con el relieve por zonas de su arena: levanta la
## roca de cada corte (CliffWall) y los puentes, y responde dónde se puede
## colocar algo (clear, nearest). La roca y los puentes cuelgan DEL SCATTER,
## como las formaciones: así arden con el bosque en el infierno de Mythos
## (HellDressing quema lo que cuelga de "arena_bounds").
##
## En una arena sin relieve por zonas no levanta nada y todo punto sirve.

## Edita aquí (no hay Inspector); las medidas del puente están en su escena
## y en ReliefSettings.
##
## Metros que el puente se mete en cada orilla, pasado el borde del
## cañón: tiene que tapar el escalón que el terreno esconde ahí.
const BRIDGE_OVERLAP: float = 3.5
## Metros que la calzada del puente baja pasado el fondo del cañón.
const BRIDGE_FOOTING: float = 2.5
## Metros que el tablero queda bajo el claro de sus cabeceras: el suelo lo
## tapa en las orillas y se entra al puente sin escalón.
const DECK_SINK: float = 0.03
## Sal que separa el facetado de un corte del del siguiente.
const CUT_SEED_STEP: int = 7919
## Búsqueda de nearest(): anillos, rumbos por anillo y metros entre anillos.
const NEAREST_RINGS: int = 14
const NEAREST_TURNS: int = 12
const NEAREST_STEP: float = 1.5


## Levanta la roca de cada corte y los puentes de `terrain` como hijos de
## `scatter`, e imprime `Relief dressing:`.
static func raise(scatter: Node3D, terrain: Terrain, style: RockFormationStyle,
		run_seed: int) -> void:
	if terrain == null or not terrain.has_relief():
		return
	var started := Time.get_ticks_msec()
	terrain.ensure_built()
	var layout := terrain.relief_layout()
	var faces := 0
	var shapes := 0
	var gaps := 0
	var tallest := 0.0
	for index in layout.cuts.size():
		var wall := CliffWall.new()
		wall.name = "CliffWall%d" % index
		wall.style = style
		scatter.add_child(wall)
		wall.build(layout.cuts[index], terrain, run_seed + index * CUT_SEED_STEP)
		faces += wall.face_count
		shapes += wall.prism_count
		gaps += wall.gap_faces
		tallest = maxf(tallest, wall.tallest)
	var bridges := 0
	for crossing: ReliefLayout.Crossing in layout.crossings:
		if _place_bridge(scatter, layout, crossing):
			bridges += 1
	print("Relief dressing: %d cuts, %d faces, %d shapes, tallest=%.1f, %d bridges in %d ms" % [
			layout.cuts.size(), faces, shapes, tallest, bridges,
			Time.get_ticks_msec() - started])
	if gaps > 0:
		push_warning("Relief dressing: %d rock faces slope between 45 and 60 degrees" % gaps)


## True si `xz` queda a `margin` metros o más de todo corte, rampa y puente
## de `terrain` y a `mesa_keepout` o más de cada sitio de meseta. Siempre
## true en una arena sin relieve por zonas (ahí las mesetas no cuentan: sus
## repartos se sortearon sin esta pregunta y así tienen que seguir).
static func clear(terrain: Terrain, xz: Vector2, margin: float,
		mesa_sites: PackedVector2Array = PackedVector2Array(), mesa_keepout: float = 0.0) -> bool:
	if terrain == null or not terrain.has_relief():
		return true
	if terrain.relief_distance(xz, margin) < margin:
		return false
	for site: Vector2 in mesa_sites:
		if site.distance_to(xz) < mesa_keepout:
			return false
	return true


## El punto más cercano a `xz` que pasa `can_place(punto, margin)`: el mismo
## `xz` si sirve; si no, busca en anillos cada vez más anchos, siempre en el
## mismo orden (no saca números de ningún RNG). Si nada sirve, devuelve `xz`.
static func nearest(xz: Vector2, margin: float, can_place: Callable) -> Vector2:
	if bool(can_place.call(xz, margin)):
		return xz
	for ring in range(1, NEAREST_RINGS + 1):
		for turn in NEAREST_TURNS:
			var candidate := xz + Vector2.from_angle(TAU * float(turn) / float(NEAREST_TURNS)) \
					* (float(ring) * NEAREST_STEP)
			if bool(can_place.call(candidate, margin)):
				return candidate
	return xz


## Pone un cofre de `scene` a `height` metros sobre `plat` (el tablero de una
## meseta). Cuelga del nodo Interactables de la arena y no del scatter: lo
## que cuelga del scatter arde en el infierno de Mythos, y un cofre tiene que
## seguir leyéndose. Sin ese nodo (el fondo del menú lo quita) no hay cofre.
## No saca números de ningún RNG.
static func place_chest(scatter: Node3D, scene: PackedScene, plat: Node3D, height: float) -> bool:
	var arena := scatter.get_parent()
	var holder := arena.get_node_or_null("Interactables") if arena != null else null
	if scene == null or holder == null:
		return false
	var chest := scene.instantiate() as Node3D
	if chest == null:
		return false
	holder.add_child(chest)
	chest.global_position = plat.global_position + Vector3.UP * height
	chest.rotation.y = plat.rotation.y
	return true


static func _place_bridge(scatter: Node3D, layout: ReliefLayout,
		crossing: ReliefLayout.Crossing) -> bool:
	var scene := layout.settings.bridge_scene
	var bridge := scene.instantiate() as Bridge if scene != null else null
	if bridge == null:
		return false
	bridge.span = crossing.span + BRIDGE_OVERLAP * 2.0
	bridge.width = crossing.width
	bridge.drop = layout.ravine.depth + BRIDGE_FOOTING
	scatter.add_child(bridge)
	bridge.position = Vector3(crossing.center.x, crossing.level - DECK_SINK, crossing.center.y)
	# El tablero corre por +X local: se gira hasta el eje del cruce.
	bridge.rotation.y = -crossing.axis.angle()
	return true
