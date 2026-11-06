class_name EventAltar
extends Interactable
## Cristal de tormenta sobre un pedestal: gratis, un solo uso, invoca un
## CLIMA al azar por la misma entrada forzada que usan el harness y
## BONK_WEATHER_NOW, así que interrumpe lo que esté corriendo y no respeta la
## pausa entre eventos.
##
## Nunca invoca las dos filas de PREMIO (lluvia dorada, luna llena): son lo
## que paga sobrevivir a una mala, y un altar que las regalara dejaría sin
## sentido a las lluvias y lunas que las ganan.
##
## Gratis a propósito: el precio es no elegir, y un desastre es una de las
## respuestas posibles.

## Aviso mientras ya corre un clima: invocar funciona igual y lo REEMPLAZA.
const BUSY_PROMPT: String = "[E] Invocar (reemplaza el evento actual)"
const READY_PROMPT: String = "[E] Invocar un evento"
@export_group("Cristal")
## Color del cristal y de su luz: tiñe Visual/Glass (conserva su transparencia) y Visual/Glow.
@export var glass_color: Color = Color(0.7, 0.78, 1.0)
## Velocidad del remolino del cristal en X, en radianes por segundo (desafinada con la de Z para que no lata como un metrónomo).
@export var swirl_x_speed: float = 1.3
## Velocidad del remolino del cristal en Z, en radianes por segundo.
@export var swirl_z_speed: float = 1.7
## Cuánto se estira el cristal en el remolino, como fracción de su tamaño.
@export var swirl_amount: float = 0.07

var _time: float = 0.0
var _spent: bool = false

## El material del cristal es local a la escena: cada altar tiene el suyo.
@onready var _glass: MeshInstance3D = $Visual/Glass
@onready var _glow: OmniLight3D = $Visual/Glow


func _ready() -> void:
	super()
	_paint()


func _physics_process(delta: float) -> void:
	_time += delta
	if available:
		_glass.scale = Vector3(
				1.0 + sin(_time * swirl_x_speed) * swirl_amount, 1.0,
				1.0 + cos(_time * swirl_z_speed) * swirl_amount)
	if available and player_in_range:
		# Se recalcula en cada frame con alguien en rango: la respuesta cambia
		# sola cuando un clima empieza o termina.
		set_prompt(READY_PROMPT if _director_idle() else BUSY_PROMPT)


## true cuando no corre ningún clima. Solo lo lee el AVISO: el altar siempre
## funciona (si rechazara, quedaría `available` para siempre y el recorrido
## del harness volvería a él una y otra vez). El aviso de ocupado le dice al
## jugador qué está cambiando.
func _director_idle() -> bool:
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null:
		return true
	var live: Variant = director.get("active_weather")
	return live == null or (live is Dictionary and (live as Dictionary).is_empty())


func _interact(_player: Node) -> void:
	if _spent or not available:
		return
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null or not director.has_method("random_altar_weather"):
		return
	var summoned := String(director.call("random_altar_weather"))
	if summoned.is_empty():
		return
	_spent = true
	_emit_started()
	consume()
	# Por start_sky_event, la ÚNICA entrada forzada: detiene lo que corre e
	# ignora la pausa entre eventos.
	director.call("start_sky_event", summoned)
	print("Event altar used: %s" % summoned)
	Juice.sparkle(global_position + Vector3.UP * 1.5)
	_emit_completed()
	sink_away()


## Pinta el cristal (conservando su transparencia) y su luz con glass_color.
func _paint() -> void:
	var material := _glass.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(glass_color, material.albedo_color.a)
		material.emission = glass_color
	_glow.light_color = glass_color
