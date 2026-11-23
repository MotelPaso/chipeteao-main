class_name TripCast
extends RefCounted
## LO QUE UN VIAJE PONE EN ESCENA (lo lleva BossArenaHost): el presagio, la
## cinemática, la arena, el jefe y el portal de salida de la fila en curso,
## más la cuenta entre la muerte del jefe y su salida. Cada pieza sale de su
## escena del catálogo (BossArenaCatalog.instance_of); este objeto las crea,
## las guarda y las libera, y el anfitrión decide cuándo. Aquí no hay nada de
## ningún jefe en particular: cada escena cumple su contrato por nombre.
##   presagio:   begin(título del jefe, segundos) y release()
##   cinemática: play(host)
##   arena:      su raíz es una BossArena
##   portal:     open(host, punto de la arena)

var _host: Node = null
var _omen: Node = null
var _cinematic: Node = null
var _arena: BossArena = null
var _boss: BossBase = null
var _portal: Node3D = null
## Segundos de juego que faltan para la salida tras la muerte del jefe (< 0 = nada pendiente).
var _exit_left: float = -1.0


func _init(host: Node) -> void:
	_host = host


## El jefe del viaje en curso, o null.
func boss() -> BossBase:
	return _boss if is_instance_valid(_boss) else null


# --- presagio ---------------------------------------------------------------------

func has_omen() -> bool:
	return is_instance_valid(_omen)


## Empieza el presagio de `row`, que dura `seconds` hasta el viaje. Sin escena
## de presagio en la fila no hace nada.
func begin_omen(row: Dictionary, seconds: float) -> void:
	_omen = BossArenaCatalog.instance_of(row, "omen_scene")
	if _omen == null:
		return
	_host.add_child(_omen)
	if _omen.has_method(&"begin"):
		_omen.call(&"begin", BossArenaCatalog.boss_title(row), seconds)


## Termina el presagio: devuelve el cielo del mapa y se va.
func end_omen() -> void:
	if is_instance_valid(_omen):
		if _omen.has_method(&"release"):
			_omen.call(&"release")
		_omen.queue_free()
	_omen = null


# --- cinemática -------------------------------------------------------------------

## Arranca la cinemática de `row`. Devuelve false si la fila no trae una.
func play_cinematic(row: Dictionary) -> bool:
	_cinematic = BossArenaCatalog.instance_of(row, "cinematic_scene")
	if _cinematic == null:
		return false
	_host.add_child(_cinematic)
	_cinematic.call(&"play", _host)
	return true


## Libera la cinemática ya: su salida devuelve el mundo, la pantalla y la canción.
func free_cinematic() -> void:
	if is_instance_valid(_cinematic):
		if _cinematic.get_parent() != null:
			_cinematic.get_parent().remove_child(_cinematic)
		_cinematic.free()
	_cinematic = null


# --- arena ------------------------------------------------------------------------

## La arena del jefe del viaje en curso, o null.
func boss_arena() -> BossArena:
	return _arena if is_instance_valid(_arena) else null


## Crea la arena de `row`, todavía fuera del árbol. Devuelve null si la escena
## de la fila no es una BossArena.
func make_arena(row: Dictionary) -> BossArena:
	var node := BossArenaCatalog.instance_of(row, "arena_scene")
	_arena = node as BossArena
	if _arena == null and node != null:
		node.free()
	return _arena


## Cuelga la arena creada como la arena viva de `root`.
func hang_arena(root: RunRoot) -> void:
	# Antes del add_child, como RunRoot._load_stage: lo que entra al árbol ya
	# pregunta por arena_root().
	root.set_live_arena(_arena)
	root.arena_host().add_child(_arena)
	# Si una cinemática tiene el mundo congelado, la arena nueva también lo está.
	WorldFreeze.hold_late(_arena)
	# El sol de esta arena recibe la calidad gráfica, como el de cada etapa.
	Settings.apply_graphics()


## El viaje suelta su arena con su jefe y su portal: desde aquí ya no los
## nombra. Devuelve la arena (null si no había), que sigue viva hasta free_arena().
func take_arena() -> BossArena:
	var arena := boss_arena()
	forget()
	return arena


## Libera `arena` y, primero, lo que los pools tienen vivo en ella (y solo en ella).
func free_arena(root: RunRoot, arena: BossArena) -> void:
	Pools.release_live_under(arena)
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	if root.arena_root() == arena:
		root.set_live_arena(null)
	# free() y no queue_free(): la arena de la etapa vuelve a colgarse en este
	# mismo frame y dos arenas vivas responderían a los mismos grupos.
	arena.free()


# --- jefe -------------------------------------------------------------------------

## Crea el jefe de `row` en su punto de `arena`, mirando al equipo, y se lo
## presenta a `schedule` (el horario de jefes que pidió el viaje: grado,
## contadores y log). `on_died` se llama una vez, cuando muere.
func spawn_boss(row: Dictionary, arena: BossArena, schedule: RefCounted,
		on_died: Callable) -> BossBase:
	var node := BossArenaCatalog.instance_of(row, "boss_scene")
	if node == null:
		return null
	_boss = node as BossBase
	if _boss == null:
		node.free()
		push_warning("BossArenaHost: boss scene root does not extend BossBase.")
		return null
	arena.boss_parent().add_child(_boss)
	var at := arena.boss_origin()
	_boss.global_position = at
	var toward := arena.spawn_origin() - at
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		_boss.rotation.y = atan2(-toward.x, -toward.z)
	if schedule != null and schedule.has_method(&"on_trip_boss"):
		schedule.call(&"on_trip_boss", _boss)
	var health := Health.find_in(_boss)
	if health != null:
		health.died.connect(on_died, CONNECT_ONE_SHOT)
	return _boss


# --- salida -----------------------------------------------------------------------

## El jefe murió: la salida de la arena llega en `seconds` segundos de juego.
func arm_exit(seconds: float) -> void:
	_exit_left = maxf(seconds, 0.0)


func exit_pending() -> bool:
	return _exit_left >= 0.0


## Corre la cuenta de la salida. Devuelve true cuando ya toca (y lo sigue
## devolviendo cada frame hasta exit_done()).
func count_exit(delta: float) -> bool:
	if _exit_left < 0.0:
		return false
	_exit_left = maxf(_exit_left - delta, 0.0)
	return _exit_left <= 0.0


func exit_done() -> void:
	_exit_left = -1.0


## Abre el portal de salida de `row` en `arena`. Devuelve false si la fila no
## trae uno: ahí el equipo sale solo.
func open_portal(row: Dictionary, arena: BossArena) -> bool:
	_portal = BossArenaCatalog.instance_of(row, "portal_scene") as Node3D
	if _portal == null:
		return false
	arena.add_child(_portal)
	if _portal.has_method(&"open"):
		_portal.call(&"open", _host, arena.portal_origin())
	return true


## El viaje terminó: la arena se fue, con su jefe y su portal.
func forget() -> void:
	_arena = null
	_boss = null
	_portal = null
	_exit_left = -1.0
