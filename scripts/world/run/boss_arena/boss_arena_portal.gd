class_name BossArenaPortal
extends Interactable
## El PORTAL DE REGRESO de la arena de un jefe (BossArenaPortal.tscn, campo
## portal_scene de su fila en BossArenaCatalog). BossArenaHost lo cuelga de
## la arena cuando el jefe muere y llama a open().
##
## Cualquier raider vivo dentro del anillo puede tomarlo y sale TODO el
## equipo, caídos incluidos. Si nadie lo toma, se cierra solo a los
## close_seconds de juego y se lleva al equipo igual: nadie queda varado en
## una arena vacía. Adónde lleva lo decide la fila del jefe (su campo exit):
## este nodo solo pide la salida (BossArenaHost.request_exit).
##
## Mientras está abierto, la flecha de objetivo del HUD apunta a él y una
## tarjeta (nodo Notice) cuenta lo que falta. Su aspecto es el de los demás
## portales (nodo Visual, PortalVisual).
## Contrato por nombre: open, el grupo "boss_arena_portal" y la línea
## "Boss arena: portal opened".

const GROUP: StringName = &"boss_arena_portal"

@export_group("Aspecto")
## Color del portal.
@export var portal_color: Color = Color(0.45, 0.9, 1.0)

@export_group("Anillo")
## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 2.2
## Cuánto más ancha que el anillo es la zona de detección (metros), para que el aviso aparezca un paso antes.
@export var detect_margin: float = 0.8
## Altura (metros) de la zona de detección.
@export var detect_height: float = 4.0
## Metros que el portal guarda con las coberturas y el borde del claro al buscar dónde abrirse.
@export var place_margin: float = 2.0

@export_group("Cierre")
## Segundos de juego que el portal queda abierto: al cumplirse se cierra solo y se lleva al equipo.
@export var close_seconds: float = 45.0

@export_group("Aviso")
## Título de la tarjeta.
@export var notice_text: String = "Portal de regreso"
## Segunda línea de la tarjeta; %d son los segundos que faltan.
@export var countdown_text: String = "Se cierra en %d s"
## Sonido con que se abre (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var open_sfx: StringName = &"return_portal"

var _host: BossArenaHost = null
## Segundos de juego que le quedan abierto.
var _left: float = 0.0
## True desde que alguien lo toma (o se cierra) hasta que la salida toma el
## control, y por qué se pidió la salida.
var _taken: bool = false
var _reason: String = ""

@onready var _visual: PortalVisual = $Visual
@onready var _notice: StickerNotice = $Notice


func _ready() -> void:
	add_to_group(GROUP)
	# La zona de detección ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + detect_margin
	cylinder.height = detect_height
	shape.shape = cylinder
	shape.position.y = detect_height * 0.5
	add_child(shape)
	super()
	_visual.build(ring_radius, portal_color)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _taken:
		# La salida no pudo empezar todavía (un fundido en curso): se reintenta.
		_leave(_reason)
		return
	_left -= delta
	_notice.set_subtitle(_countdown(maxi(ceili(_left), 0)))
	if _left <= 0.0:
		_leave(BossArenaHost.RETURN_TIMEOUT)


## Abre el portal del viaje que lleva `host`, lo más cerca que se pueda de
## `origin` (un punto de la arena a ras de suelo).
func open(host: BossArenaHost, origin: Vector3) -> void:
	_host = host
	_left = maxf(close_seconds, 0.0)
	global_position = _open_spot(origin)
	_notice.show_notice(notice_text, _countdown(ceili(_left)))
	get_tree().call_group("boss_ui", "track_objective", self)
	Sfx.play(open_sfx)
	set_physics_process(true)
	# Línea de log para los soaks.
	print("Boss arena: portal opened at %.1fs closes_in=%.0fs" % [RunState.stage_time, _left])


## Segundos de juego que le quedan abierto (lo lee el harness).
func seconds_left() -> float:
	return _left


func _interact(_player: Node) -> void:
	if _taken or _host == null or not _host.can_return():
		return
	consume()
	_emit_completed()
	_leave(BossArenaHost.RETURN_PORTAL)


## Pide la salida. Si todavía no puede empezar, queda tomado y lo reintenta
## cada frame.
func _leave(reason: String) -> void:
	_taken = true
	_reason = reason
	_notice.hide_notice()
	if _host != null and _host.request_exit(reason):
		set_physics_process(false)


## La segunda línea de la tarjeta. Un countdown_text sin %d se muestra tal cual.
func _countdown(seconds: int) -> String:
	return countdown_text % seconds if countdown_text.contains("%d") else countdown_text


## El punto más cercano a `origin` donde cabe el portal, a ras de suelo.
func _open_spot(origin: Vector3) -> Vector3:
	var at := origin
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"nearest_place"):
		var spot: Vector2 = bounds.call(&"nearest_place", Vector2(origin.x, origin.z),
				ring_radius + place_margin)
		at = Vector3(spot.x, origin.y, spot.y)
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		at.y = terrain.height_at(at.x, at.z)
	return at
