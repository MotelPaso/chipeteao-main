extends RefCounted
## Pisos ELEVADOS para la Langosta Azul (lo usa LobsterBody.safe_point): el
## tablero del Gran Puente, lo alto de una meseta o de una roca ancha. La
## máscara de la arena no cuenta ahí lugar para un cuerpo, pero ahí se para un
## raider. Si el raider al que va un ataque pisa uno de esos pisos, la marca
## del ataque se queda en ese mismo piso, en el lugar más cercano donde el
## cuerpo entero cabe: así el Salto y la Emboscada lo alcanzan sobre el puente.
## Ninguna escena usa este script (se carga con preload, sin class_name): lo
## que alguien podría querer tocar está en el bloque «Edita aquí».

# --- Edita aquí ---------------------------------------------------------------
## Metros sobre el terreno desde los que el piso que pisa un raider cuenta como elevado.
const RAISED_FLOOR: float = 1.0
## Metros desde el centro a los que se mira el suelo, en TURNS rumbos, para
## saber si el cuerpo entero cabe: su radio de colisión (1.1) y algo más. Así
## no queda junto al borde, una baranda o una torre.
const FOOTING: float = 1.5
## Paso y alcance, en metros, de la búsqueda de ese lugar alrededor de la marca.
const SEARCH_STEP: float = 0.75
const SEARCH_REACH: float = 3.0
## Metros bajo los pies del raider hasta los que se busca el piso que pisa
## (más alto que eso salta solo un instante).
const STAND_PROBE: float = 4.0
## Rumbos en que se mira alrededor de un punto.
const TURNS: int = 8


## Si el raider en `raider_at` pisa un piso elevado, el lugar más cercano a
## `point` de ese mismo piso donde `body` cabe entero, a ras de ese piso; si
## no hay ninguno a SEARCH_REACH metros, Vector3.INF.
static func raised_spot(body: LobsterBody, point: Vector3, raider_at: Vector3) -> Vector3:
	if not body.is_inside_tree():
		return Vector3.INF
	var terrain := Terrain.find(body.get_tree())
	if terrain == null:
		return Vector3.INF
	# El rayo sale de sus pies: bajo un puente, el tablero de arriba no cuenta.
	var level := _first_hit(body, raider_at + Vector3.UP * LobsterBody.GROUND_STEP,
			raider_at + Vector3.DOWN * STAND_PROBE)
	if level - terrain.height_at(raider_at.x, raider_at.z) < RAISED_FLOOR:
		return Vector3.INF
	for ring: int in roundi(SEARCH_REACH / SEARCH_STEP) + 1:
		for turn: int in (1 if ring == 0 else TURNS):
			var spot := point + _heading(turn) * SEARCH_STEP * float(ring)
			if absf(spot.x) <= body.arena_half_extent and absf(spot.z) <= body.arena_half_extent \
					and _fits_on(body, terrain, spot, level):
				return Vector3(spot.x, level, spot.z)
	return Vector3.INF


## True si en `spot` el cuerpo entero cabe sobre el piso a altura `level`: lo
## primero que hay bajo el centro y bajo TURNS rumbos a FOOTING metros, visto
## desde bien arriba, queda a no más de LobsterBody.GROUND_STEP de esa altura.
## Así no cabe junto al borde (no hay nada a esa altura), ni sobre una baranda
## o junto a una torre (lo primero que hay está más arriba).
static func _fits_on(body: LobsterBody, terrain: Terrain, spot: Vector3, level: float) -> bool:
	for turn: int in TURNS + 1:
		# Primero el centro: la mayoría de los lugares que no sirven fallan ahí.
		var at := spot if turn == 0 else spot + _heading(turn - 1) * FOOTING
		var top := _first_hit(body,
				Vector3(at.x, terrain.height_at(at.x, at.z) + LobsterBody.GROUND_PROBE_UP, at.z),
				Vector3(at.x, level - FOOTING, at.z))
		if absf(top - level) > LobsterBody.GROUND_STEP:
			return false
	return true


## Altura de lo primero que cruza el rayo de `from` a `to` en la capa del
## mundo, sin contar a los personajes (raiders, la langosta, la horda); -INF si
## no cruza nada.
static func _first_hit(body: LobsterBody, from: Vector3, to: Vector3) -> float:
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return -INF
	var skip: Array[RID] = [body.get_rid()]
	for _attempt: int in LobsterBody.GROUND_TRIES:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to,
				LobsterBody.WORLD_MASK, skip))
		if hit.is_empty():
			return -INF
		if not hit["collider"] is CharacterBody3D:
			return (hit["position"] as Vector3).y
		skip.append(hit["rid"] as RID)
	return -INF


## Rumbo número `turn` de TURNS, plano y unitario.
static func _heading(turn: int) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, TAU * float(turn) / float(TURNS))
