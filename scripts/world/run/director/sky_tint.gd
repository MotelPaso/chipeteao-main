class_name SkyTint
extends RefCounted
## El tinte del cielo de los climas: guarda el sol y el ambiente de la arena
## y sus valores originales, los lleva a un tinte y los devuelve. Lo crea y
## lo usa el WeatherDirector; los tweens se crean sobre ese nodo, así se
## pausan con él.
## Orden obligatorio: forget() en cada inicio de etapa (si no, la etapa 2
## teñiría el sol ya liberado de la etapa 1 y ningún cielo se vería) y
## snap_back() antes de que la arena se libere.

## Edita aquí: segundos del paso al tinte y de la vuelta al cielo original.
const TINT_SECONDS: float = 1.5
const RESTORE_SECONDS: float = 2.0

## El nodo dueño de los tweens (el WeatherDirector).
var _host: Node = null
var _sun: DirectionalLight3D = null
var _sun_color: Color = Color.WHITE
var _sun_energy: float = 1.0
var _environment: Environment = null
var _ambient_color: Color = Color.WHITE
var _ambient_energy: float = 1.0
## El ÚNICO tween que escribe el sol y el ambiente: dos a la vez escriben
## las mismas propiedades cada frame y gana el más largo.
var _tween: Tween = null


func _init(host: Node) -> void:
	_host = host


## Olvida las luces de la arena anterior sin tocarlas (inicio de etapa).
func forget() -> void:
	_kill_tween()
	_sun = null
	_environment = null
	_sun_color = Color.WHITE
	_sun_energy = 1.0
	_ambient_color = Color.WHITE
	_ambient_energy = 1.0


## Guarda el sol y el ambiente de la arena actual y sus valores originales.
## No hace nada si ya los tiene (forget() los olvida en cada etapa).
func cache(layout: StageLayout) -> void:
	if _sun != null:
		return
	# La ARENA, no current_scene: current_scene es la raíz de la partida y
	# sus luces son las de la arena que tenga debajo.
	var scene := layout.current_arena() if layout != null else null
	if scene == null:
		return
	for node: Node in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		_sun_color = _sun.light_color
		_sun_energy = _sun.light_energy
		break
	for node: Node in scene.find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment == null or world_environment.environment == null:
			break
		# El Environment de la arena es un sub_resource COMPARTIDO por todas
		# las instancias de la escena: teñirlo pasaría a la partida
		# siguiente. Se trabaja sobre una copia propia de esta arena.
		_environment = world_environment.environment.duplicate()
		world_environment.environment = _environment
		_ambient_color = _environment.ambient_light_color
		_ambient_energy = _environment.ambient_light_energy
		break


## Lleva el sol y el ambiente a un tinte en TINT_SECONDS. `sun_energy`
## multiplica la energía original del sol.
func tint(sun_color: Color, sun_energy: float, ambient: Color) -> void:
	_kill_tween()
	_tween = _host.create_tween().set_parallel()
	if _sun != null:
		_tween.tween_property(_sun, "light_color", sun_color, TINT_SECONDS)
		_tween.tween_property(_sun, "light_energy", _sun_energy * sun_energy, TINT_SECONDS)
	if _environment != null:
		_tween.tween_property(_environment, "ambient_light_color", ambient, TINT_SECONDS)


## Devuelve el cielo original de la arena en RESTORE_SECONDS.
func restore() -> void:
	_kill_tween()
	_tween = _host.create_tween().set_parallel()
	if _sun != null:
		_tween.tween_property(_sun, "light_color", _sun_color, RESTORE_SECONDS)
		_tween.tween_property(_sun, "light_energy", _sun_energy, RESTORE_SECONDS)
	if _environment != null:
		_tween.tween_property(_environment, "ambient_light_color", _ambient_color,
				RESTORE_SECONDS)


## Devuelve la luz original de la arena AL INSTANTE (sin tween). Se usa
## cuando la arena se va: un tween sobre un sol liberado es un error.
func snap_back() -> void:
	_kill_tween()
	if _sun != null and is_instance_valid(_sun):
		_sun.light_color = _sun_color
		_sun.light_energy = _sun_energy
	if _environment != null:
		_environment.ambient_light_color = _ambient_color
		_environment.ambient_light_energy = _ambient_energy


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
