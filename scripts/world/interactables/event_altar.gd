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

@export var glass_color: Color = Color(0.7, 0.78, 1.0)

## Aviso mientras ya corre un clima: invocar funciona igual y lo REEMPLAZA.
const BUSY_PROMPT: String = "[E] Invocar (reemplaza el evento actual)"
const READY_PROMPT: String = "[E] Invocar un evento"
## Dos frecuencias desafinadas (Hz) para que el cristal no lata como un metrónomo.
const SWIRL_X_HZ: float = 1.3
const SWIRL_Z_HZ: float = 1.7

var _glass: MeshInstance3D = null
var _time: float = 0.0
var _spent: bool = false


func _init() -> void:
	prompt_text = READY_PROMPT
	marker_kind = &"event_altar"
	prompt_height = 3.0
	meta_stat_id = "shrines_used"
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# El anillo de detección va ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.2
	cylinder.height = 3.5
	shape.shape = cylinder
	shape.position.y = 1.75
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	var pedestal := MeshInstance3D.new()
	var stone := BoxMesh.new()
	stone.size = Vector3(1.1, 1.0, 1.1)
	pedestal.mesh = stone
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.28, 0.29, 0.34)
	rock.roughness = 0.9
	pedestal.material_override = rock
	pedestal.position.y = 0.5
	add_child(pedestal)
	_glass = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.45
	orb.height = 0.9
	# Teselado explícito (el del motor es 64 x 32, ~4.2k triángulos).
	orb.radial_segments = 16
	orb.rings = 8
	_glass.mesh = orb
	# Material propio de cada altar.
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(glass_color, 0.75)
	glass.emission_enabled = true
	glass.emission = glass_color
	glass.emission_energy_multiplier = 1.8
	_glass.material_override = glass
	_glass.position.y = 1.45
	add_child(_glass)
	var light := OmniLight3D.new()
	light.light_color = glass_color
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position.y = 1.45
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _glass != null and available:
		_glass.scale = Vector3(
				1.0 + sin(_time * SWIRL_X_HZ) * 0.07, 1.0,
				1.0 + cos(_time * SWIRL_Z_HZ) * 0.07)
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

