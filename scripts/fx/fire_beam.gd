class_name FireBeam
extends Node3D
## Chorro de fuego: el Aliento de Mythos. Son tramos de llama (el mismo muro
## de las ondas de fuego, fire_wall.gdshader) en dos hileras, a ras de suelo
## y siguiendo el relieve. Tiene dos caras:
##   AVISO   (warn)  dos líneas de llamas bajas, desde Mythos hacia afuera,
##           marcan entre dónde y dónde va a barrer; la más alta es por la
##           que empieza.
##   CHORRO  (blaze) las dos hileras van juntas, del ancho del chorro, bajan
##           del pico de Mythos al suelo y corren hasta el final de su
##           alcance. Quien lo usa lo llama en cada frame con el ángulo de
##           ahora.
## Solo dibuja: a quién quema lo decide el ataque (MythosBreath). Los ángulos
## son radianes en el plano del suelo (0 = +X, crece hacia +Z).

@export_group("Chorro")
## Tramos de llama de cada hilera.
@export var segments: int = 18
## Alto de las llamas del chorro, en metros.
@export var flame_height: float = 3.4
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.2
## Metros delante de Mythos donde el chorro, que baja de su pico, toca el suelo.
@export var nozzle_distance: float = 1.2
## Segundos que tarda en apagarse.
@export var fade_time: float = 0.3
## Brillo de la luz que acompaña al chorro.
@export var light_energy: float = 5.0
## Color de esa luz.
@export var light_color: Color = Color(1.0, 0.6, 0.25)
## Color de esa luz con el fuego de la segunda fase de Mythos.
@export var reborn_light_color: Color = Color(0.45, 0.75, 1.0)

@export_group("Aviso")
## Alto de la línea de aviso por la que empieza a barrer, en metros.
@export var warn_height: float = 1.1
## Alto de la línea de aviso donde termina, en metros.
@export var warn_end_height: float = 0.55
## Opacidad (0-1) de las líneas de aviso.
@export_range(0.0, 1.0) var warn_fade: float = 0.55

var _terrain: Terrain = null
var _fade_tween: Tween = null

@onready var _wall: MultiMeshInstance3D = $Wall
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	var multimesh := _wall.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = maxi(segments, 2) * 2
	# El chorro llega lejos de su origen: una caja fija evita que se recorte.
	multimesh.custom_aabb = AABB(Vector3(-80.0, -12.0, -80.0), Vector3(160.0, 40.0, 160.0))
	_wall.multimesh = multimesh
	_wall.visible = false
	_light.visible = false


## El aviso: desde `origin` (un punto sobre el suelo), una línea hacia
## `from_angle` (por donde empieza) y otra hacia `to_angle` (donde termina),
## entre `inner` y `reach` metros.
func warn(origin: Vector3, from_angle: float, to_angle: float, inner: float,
		reach: float) -> void:
	_show(origin, warn_fade)
	_light.visible = false
	_place_row(0, origin, from_angle, 0.0, inner, reach, warn_height, origin.y)
	_place_row(1, origin, to_angle, 0.0, inner, reach, warn_end_height, origin.y)


## El chorro encendido desde `origin` hacia `angle`: sale de `muzzle` (el
## pico de Mythos), toca el suelo y corre entre `inner` y `reach` metros, de
## `width` metros de ancho.
func blaze(origin: Vector3, muzzle: Vector3, angle: float, inner: float, reach: float,
		width: float) -> void:
	_show(origin, 1.0)
	var heading := Vector3(cos(angle), 0.0, sin(angle))
	_place_row(0, origin, angle, width * 0.5, inner, reach, flame_height, muzzle.y)
	_place_row(1, origin, angle, -width * 0.5, inner, reach, flame_height, muzzle.y)
	var middle := heading * (inner + (reach - inner) * 0.35)
	_light.visible = true
	_light.light_energy = light_energy
	_light.light_color = light_color.lerp(reborn_light_color, FireTint.amount())
	_light.position = middle + Vector3.UP * (_ground(origin + middle) - origin.y + 2.0)


## Se apaga de a poco.
func quench() -> void:
	if not _wall.visible:
		return
	_kill_fade()
	_light.visible = false
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_hide)


## Se apaga ya (el ataque se cortó a la mitad).
func snuff() -> void:
	_kill_fade()
	_hide()


# --- privados ---------------------------------------------------------------------

func _show(origin: Vector3, fade: float) -> void:
	_kill_fade()
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = Terrain.find(get_tree())
	global_transform = Transform3D(Basis.IDENTITY, origin)
	_set_fade(fade)
	_wall.visible = true


## Una hilera de tramos desde el origen hacia `angle`, corrida `side` metros
## hacia su izquierda. Hasta nozzle_distance baja desde `top` (la altura del
## pico) y de ahí en más va a ras de suelo.
func _place_row(row: int, origin: Vector3, angle: float, side: float, inner: float,
		reach: float, height: float, top: float) -> void:
	var multimesh := _wall.multimesh
	var count := maxi(segments, 2)
	var heading := Vector3(cos(angle), 0.0, sin(angle))
	var left := Vector3(heading.z, 0.0, -heading.x)
	var step := maxf(reach - inner, 0.1) / float(count)
	for index: int in count:
		var along := inner + step * (float(index) + 0.5)
		var at := heading * along + left * side
		var ground := _ground(origin + at) - origin.y
		# Cerca de Mythos el chorro todavía viene bajando desde su pico.
		var drop := 1.0 - clampf((along - inner) / maxf(nozzle_distance, 0.01), 0.0, 1.0)
		at.y = lerpf(ground, maxf(top - origin.y - height, ground), drop) + height * 0.5
		multimesh.set_instance_transform(row * count + index, Transform3D(
				Basis(heading * step * segment_overlap, Vector3.UP * height, left), at))


func _ground(point: Vector3) -> float:
	return _terrain.height_at(point.x, point.z) if _terrain != null else point.y


func _set_fade(amount: float) -> void:
	_wall.set_instance_shader_parameter(&"fade", amount)


func _hide() -> void:
	_wall.visible = false
	_light.visible = false


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
