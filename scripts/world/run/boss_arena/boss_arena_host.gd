class_name BossArenaHost
extends Node
## ANFITRIÓN DE ARENAS DE JEFE (nodo de Run.tscn, grupo "boss_arena_host").
## Lleva al equipo del mapa de la etapa al campo de batalla propio de un jefe
## y lo trae de vuelta. Qué jefe tiene arena, y con qué escenas, es DATO: una
## fila de BossArenaCatalog. Aquí no hay nada de ningún jefe en particular.
##
## El viaje, de punta a punta:
##   1. PRESAGIO (begin_omen): el horario de jefes lo pide unos segundos
##      antes. La escena de presagio de la fila avisa en el mapa.
##   2. IDA (begin_trip): otro jefe que siga vivo muere con su pago. Con
##      cinemática, ella decide el instante del cambio de mundo y lo pide con
##      enter_arena(); sin ella, el cambio va dentro de un fundido.
##   3. CAMBIO DE MUNDO (enter_arena): la arena de la etapa SALE DEL ÁRBOL y
##      queda guardada aquí, entera; entra la arena del jefe, el equipo
##      aterriza en ella y nace el jefe.
##   4. VUELTA: muerto el jefe se abre el portal de la fila (o el equipo
##      vuelve solo). La arena del jefe se libera y la de la etapa vuelve al
##      árbol tal como estaba; cada raider vuelve a donde lo tomaron.
##
## La arena de la etapa sale del árbol y no se queda dormida adentro: así hay
## UN solo mundo respondiendo a "arena_bounds", "terrain" y "enemy_spawner"
## (el porqué y lo que exige están en SuspendedStage). La arena guardada se
## libera en TODA salida: fin de partida, salir al menú o cambio de etapa.
##
## Contratos por nombre: el grupo; las señales (el harness compara el mapa
## antes y después); y las líneas "Boss arena:", una por paso del viaje.

## Está por empezar el presagio de un viaje (el cielo del mapa sigue intacto).
signal omen_beginning
## Un viaje empezó: el equipo sigue en el mapa, justo donde lo toman.
signal trip_began
## El mapa de la etapa está por salir del árbol (todavía está entero y vivo).
signal stage_suspending(arena: Node3D)
## El equipo y el jefe ya están en la arena del jefe.
signal arena_entered(arena: Node3D)
## La arena del jefe está por liberarse (todavía está en el árbol).
signal arena_leaving(arena: Node3D)
## El mapa de la etapa volvió al árbol y todavía no corrió ningún tick.
signal stage_restored(arena: Node3D)
## El viaje terminó sin vuelta: "advance", "wipe" o "extract".
signal trip_abandoned(reason: String)

enum Phase { IDLE, LEAVING, AWAY, RETURNING }

const GROUP: StringName = &"boss_arena_host"
## Razones de un viaje que no termina con el equipo de vuelta en el mapa.
const ABANDON_ADVANCE: String = "advance"
const ABANDON_WIPE: String = "wipe"
const ABANDON_EXTRACT: String = "extract"
## Razones de la vuelta.
const RETURN_PORTAL: String = "portal"
const RETURN_TIMEOUT: String = "timeout"
## Nombre de cada fase para el harness, en el orden de Phase.
const PHASE_NAMES: Array[StringName] = [&"idle", &"leaving", &"away", &"returning"]

var _phase: Phase = Phase.IDLE
## La fila de BossArenaCatalog del viaje en curso (vacía sin viaje).
var _encounter: Dictionary = {}
## El horario de jefes que pidió el viaje (BossSchedule): se le avisa cuando
## nace el jefe y cuando el equipo vuelve. Solo se le llama por nombre: es de
## un mapa que está fuera del árbol.
var _schedule: RefCounted = null
## La arena de la etapa mientras espera fuera del árbol.
var _stage := SuspendedStage.new()
var _boss_arena: BossArena = null
var _boss: BossBase = null
var _omen: Node = null
var _cinematic: Node = null
var _portal: Node3D = null
## Segundo de etapa en que el equipo dejó el mapa.
var _left_at: float = 0.0
## Segundos de juego que faltan para lo que sigue a la muerte del jefe (< 0 = nada pendiente).
var _exit_left: float = -1.0
## Jefes del mapa que murieron con su pago al partir.
var _rivals_slain: int = 0
## True desde que el viaje en curso imprimió su línea de cierre.
var _closed: bool = false

@onready var _party := TripParty.new(get_tree())


## EL acceso, como toda búsqueda entre escenas de este proyecto.
static func find(tree: SceneTree) -> BossArenaHost:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as BossArenaHost


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# Pausable aunque cuelgue de un nodo que procesa siempre (el harness): la
	# cuenta tras la muerte del jefe, la cinemática y el portal son tiempo de juego.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended"):
		manager.connect("run_ended", _on_run_ended)


## La partida se va (salir al menú, reintentar, cerrar): la arena de la etapa
## que esperaba fuera del árbol no cuelga de nadie y hay que liberarla aquí.
func _exit_tree() -> void:
	_stage.discard()


func _physics_process(delta: float) -> void:
	if _exit_left < 0.0:
		set_physics_process(false)
		return
	_exit_left -= delta
	if _exit_left > 0.0:
		return
	# Si todavía no se puede (un fundido en curso), se reintenta en el próximo frame.
	_exit_left = -1.0 if _open_exit() else 0.0


# --- lo que piden el horario de jefes, la cinemática, el portal y el harness ------

## En qué anda: "idle", "leaving" (ida en curso, el equipo sigue en el mapa),
## "away" (el equipo está en la arena del jefe) o "returning".
func phase_name() -> StringName:
	return PHASE_NAMES[_phase]


## True desde que el equipo deja el mapa de la etapa hasta que vuelve a él.
func is_away() -> bool:
	return _phase == Phase.AWAY or _phase == Phase.RETURNING


## True mientras hay un viaje en curso, en cualquiera de sus pasos.
func is_busy() -> bool:
	return _phase != Phase.IDLE


## La arena de la etapa mientras espera fuera del árbol, o null.
func suspended_arena() -> Node3D:
	return _stage.arena()


## La arena del jefe en curso, o null.
func boss_arena() -> BossArena:
	return _boss_arena if is_instance_valid(_boss_arena) else null


## El jefe del viaje en curso, o null.
func boss() -> BossBase:
	return _boss if is_instance_valid(_boss) else null


## El equipo del viaje: dónde estaba cada raider al partir (lo lee el harness).
func party() -> TripParty:
	return _party


## Jefes del mapa que murieron con su pago cuando el equipo partió.
func rivals_slain() -> int:
	return _rivals_slain


## El nombre del jefe del viaje en curso (la cinemática lo pone en su cartel
## antes de que el jefe exista).
func boss_title() -> String:
	return BossArenaCatalog.boss_title(_encounter)


## Empieza el presagio de `encounter`, que dura `seconds` hasta el viaje.
## Sin escena de presagio en la fila no hace nada.
func begin_omen(encounter: Dictionary, seconds: float) -> void:
	if is_instance_valid(_omen) or is_busy():
		return
	omen_beginning.emit()
	var scene := BossArenaCatalog.scene_of(encounter, "omen_scene")
	if scene == null:
		return
	_omen = scene.instantiate()
	add_child(_omen)
	if _omen.has_method(&"begin"):
		_omen.call(&"begin", BossArenaCatalog.boss_title(encounter), seconds)


## True si un viaje puede EMPEZAR ahora: sin otro en curso, con la partida
## viva, alguien en pie y sin fundido ni cambio de etapa en marcha.
func can_begin_trip() -> bool:
	var root := _run_root()
	return _phase == Phase.IDLE and RunState.run_active and not ScreenFade.is_busy() \
			and root != null and not root.is_swapping() and root.arena_root() != null \
			and Coop.alive_player_count(get_tree()) > 0


## Empieza el viaje a la arena de `encounter`. `schedule` es el horario de
## jefes que lo pide (recibe on_trip_boss y on_trip_over). Devuelve false si
## no pudo empezar: quien llama reintenta en otro tick.
func begin_trip(encounter: Dictionary, schedule: RefCounted) -> bool:
	if not can_begin_trip() or BossArenaCatalog.scene_of(encounter, "arena_scene") == null:
		return false
	_phase = Phase.LEAVING
	_encounter = encounter
	_schedule = schedule
	_exit_left = -1.0
	_closed = false
	# Lo que cuelga de la arena y tiene la pausa (ruleta, vendedor) se cierra
	# antes de tocar nada: con la arena suspendida, nadie podría devolverla.
	get_tree().call_group(BlockingUi.CLOSABLE_GROUP, "dismiss")
	_party.remember()
	trip_began.emit()
	_rivals_slain = SuspendedStage.slay_rival_bosses(get_tree())
	var scene := BossArenaCatalog.scene_of(encounter, "cinematic_scene")
	if scene != null:
		_cinematic = scene.instantiate()
		add_child(_cinematic)
		_cinematic.call(&"play", self)
	else:
		_leave_through_fade()
	return true


## EL CAMBIO DE MUNDO. Lo pide la cinemática en el instante en que la
## pantalla queda tapada (o el fundido, sin cinemática). Todo pasa en este
## frame: la arena de la etapa sale del árbol, entra la del jefe, el equipo
## aterriza y nace el jefe. Devuelve el jefe, o null si no hubo cambio.
func enter_arena() -> BossBase:
	var root := _run_root()
	if _phase != Phase.LEAVING or root == null or not RunState.run_active:
		return null
	var stage := root.arena_root()
	var arena := BossArenaCatalog.scene_of(_encounter, "arena_scene").instantiate() as BossArena
	if stage == null or arena == null:
		push_error("BossArenaHost: the arena scene root is not a BossArena.")
		return null
	get_tree().call_group(BlockingUi.CLOSABLE_GROUP, "dismiss")
	_party.clear_weapon_fields()
	# El presagio termina aquí: el mapa se guarda con su cielo de siempre.
	_end_omen()
	stage_suspending.emit(stage)
	_left_at = RunState.stage_time
	_stage.suspend(root, stage)
	_phase = Phase.AWAY
	_boss_arena = arena
	# Línea de log para los soaks: el mapa de la etapa quedó suspendido.
	print("Boss arena: left %s for %s at %.1fs party=%d" % [
			String(stage.get("map_id")), arena.map_id, RunState.stage_time,
			_party.bodies().size()])
	# Antes del add_child, como RunRoot._load_stage: lo que entra al árbol ya
	# pregunta por arena_root().
	root.set_live_arena(arena)
	root.arena_host().add_child(arena)
	# Si una cinemática tiene el mundo congelado, la arena nueva también lo está.
	WorldFreeze.hold_late(arena)
	# El sol de esta arena recibe la calidad gráfica, como el de cada etapa.
	Settings.apply_graphics()
	get_tree().call_group("run_systems", "place_party", arena.spawn_origin())
	_party.notify_world_changed()
	_boss = _spawn_boss(arena)
	print("Boss arena: entered %s at %.1fs" % [arena.map_id, RunState.stage_time])
	arena_entered.emit(arena)
	return _boss


## Saca del mapa suspendido a la horda normal que quedó en él (sin pagar
## nada) y las saetas que venían en vuelo. Lo pide el jefe cuando empieza su
## pelea. Los siervos poseídos y los jefes que el viaje perdonó se quedan.
## Devuelve cuántos enemigos se llevó.
func sweep_stage_horde() -> int:
	return _stage.sweep_horde()


## True si el equipo puede volver ahora (el portal lo pregunta ANTES de gastarse).
func can_return() -> bool:
	return _phase == Phase.AWAY and RunState.run_active and not ScreenFade.is_busy()


## Pide la vuelta al mapa de la etapa. `reason` es RETURN_PORTAL (alguien
## tomó el portal) o RETURN_TIMEOUT (se cerró solo). Devuelve false si no
## puede empezar ahora.
func request_return(reason: String) -> bool:
	if not can_return():
		return false
	_phase = Phase.RETURNING
	_exit_left = -1.0
	# Línea de log para los soaks.
	print("Boss arena: returning reason=%s at %.1fs" % [reason, RunState.stage_time])
	_return_through_fade()
	return true


## El viaje termina sin volver: un cambio de etapa (lo llama
## RunRoot._swap_stage por el grupo). Libera la arena del jefe y deja la de
## la etapa otra vez como la viva, para que el desmontaje de siempre la
## recorra. No coloca al equipo: la etapa siguiente lo hace.
func abandon_trip(reason: String) -> void:
	if _phase == Phase.IDLE:
		_end_omen()
		return
	_close_trip(reason)
	_free_cinematic()
	var root := _run_root()
	if root != null and suspended_arena() != null:
		_dispose_boss_arena(root)
		_stage.restore(root)
	_end_omen()
	_forget_trip()


# --- ida y vuelta -----------------------------------------------------------------

## La ida sin cinemática: el cambio de mundo dentro de un fundido.
func _leave_through_fade() -> void:
	await ScreenFade.transition_async(enter_arena)
	if _phase == Phase.LEAVING:
		# El cambio no pasó (otro fundido ganó la carrera o la partida terminó
		# en el camino): el horario de jefes puede pedirlo de nuevo.
		_close_trip("")
		_forget_trip()


func _return_through_fade() -> void:
	await ScreenFade.transition_async(_return_to_stage)
	if _phase == Phase.RETURNING:
		_phase = Phase.AWAY


## La vuelta, dentro del fundido: lo de la arena del jefe se recoge y se
## libera, y la arena de la etapa vuelve al árbol tal como salió.
func _return_to_stage() -> void:
	var root := _run_root()
	if _phase != Phase.RETURNING or root == null or not RunState.run_active:
		return
	get_tree().call_group(BlockingUi.CLOSABLE_GROUP, "dismiss")
	_party.collect_loot(boss_arena())
	_party.clear_weapon_fields()
	_free_cinematic()
	_dispose_boss_arena(root)
	var stage := _stage.restore(root)
	_end_omen()
	_party.place_back()
	_party.notify_world_changed()
	var schedule := _schedule
	var away := RunState.stage_time - _left_at
	_forget_trip()
	if stage != null:
		stage_restored.emit(stage)
	if schedule != null and schedule.has_method(&"on_trip_over"):
		schedule.call(&"on_trip_over")
	# Línea de log para los soaks: el mapa de la etapa es otra vez el vivo.
	print("Boss arena: back in %s at %.1fs away=%.1fs" % [
			String(stage.get("map_id")) if stage != null else "?", RunState.stage_time, away])


## Libera la arena del jefe con el portal y el jefe y, primero, lo que los
## pools tienen vivo en ella (y solo en ella).
func _dispose_boss_arena(root: RunRoot) -> void:
	_portal = null
	_boss = null
	var arena := boss_arena()
	_boss_arena = null
	if arena == null:
		return
	arena_leaving.emit(arena)
	Pools.release_live_under(arena)
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	if root.arena_root() == arena:
		root.set_live_arena(null)
	# free() y no queue_free(): la arena de la etapa vuelve a colgarse en este
	# mismo frame y dos arenas vivas responderían a los mismos grupos.
	arena.free()


## Libera la cinemática ya: su salida devuelve el mundo, la pantalla y la canción.
func _free_cinematic() -> void:
	if is_instance_valid(_cinematic):
		if _cinematic.get_parent() != null:
			_cinematic.get_parent().remove_child(_cinematic)
		_cinematic.free()
	_cinematic = null


## Cierra un viaje que no vuelve: una línea con la razón (una sola por viaje)
## y el aviso al horario de jefes. Sin razón, el viaje nunca llegó a pasar.
func _close_trip(reason: String) -> void:
	if not reason.is_empty() and not _closed:
		_closed = true
		print("Boss arena: abandoned reason=%s at %.1fs" % [reason, RunState.stage_time])
		trip_abandoned.emit(reason)
	var schedule := _schedule
	_schedule = null
	if schedule != null and schedule.has_method(&"on_trip_over"):
		schedule.call(&"on_trip_over")


func _forget_trip() -> void:
	_phase = Phase.IDLE
	_encounter = {}
	_schedule = null
	_boss = null
	_portal = null
	_exit_left = -1.0
	_party.forget()
	_free_cinematic()


## Termina el presagio: devuelve el cielo del mapa y se va.
func _end_omen() -> void:
	if is_instance_valid(_omen):
		if _omen.has_method(&"release"):
			_omen.call(&"release")
		_omen.queue_free()
	_omen = null


## La partida terminó (toda la party cayó, o alguien extrajo). Con un viaje en
## curso no hay vuelta: se deja todo como está y se anota la razón.
func _on_run_ended(_victory: bool) -> void:
	_exit_left = -1.0
	if _phase == Phase.IDLE:
		return
	_close_trip(ABANDON_EXTRACT if _party.anyone_alive() else ABANDON_WIPE)


# --- el jefe ----------------------------------------------------------------------

## Crea el jefe de la fila en su punto de la arena, mirando al equipo, y se lo
## presenta al horario de jefes que pidió el viaje (grado, contadores y log).
func _spawn_boss(arena: BossArena) -> BossBase:
	var scene := BossArenaCatalog.scene_of(_encounter, "boss_scene")
	if scene == null:
		return null
	var node := scene.instantiate()
	var body := node as BossBase
	if body == null:
		node.free()
		push_warning("BossArenaHost: boss scene root does not extend BossBase.")
		return null
	arena.boss_parent().add_child(body)
	var at := arena.boss_origin()
	body.global_position = at
	var toward := arena.spawn_origin() - at
	toward.y = 0.0
	if toward.length_squared() > 0.0001:
		body.rotation.y = atan2(-toward.x, -toward.z)
	if _schedule != null and _schedule.has_method(&"on_trip_boss"):
		_schedule.call(&"on_trip_boss", body)
	var health := Health.find_in(body)
	if health != null:
		health.died.connect(_on_boss_died, CONNECT_ONE_SHOT)
	return body


func _on_boss_died() -> void:
	if not is_away():
		return
	_exit_left = maxf(float(_encounter.get("exit_delay", 0.0)), 0.0)
	set_physics_process(true)


## Lo que sigue a la caída del jefe: el portal de la fila o, sin portal, la
## vuelta directa. False si todavía no se puede (se reintenta).
func _open_exit() -> bool:
	var arena := boss_arena()
	var scene := BossArenaCatalog.scene_of(_encounter, "portal_scene")
	if arena == null:
		return true
	if scene == null:
		return request_return(RETURN_TIMEOUT)
	_portal = scene.instantiate() as Node3D
	if _portal == null:
		return request_return(RETURN_TIMEOUT)
	arena.add_child(_portal)
	if _portal.has_method(&"open"):
		_portal.call(&"open", self, arena.portal_origin())
	return true


# --- utilitarios ------------------------------------------------------------------

func _run_root() -> RunRoot:
	return get_tree().get_first_node_in_group("run_root") as RunRoot
