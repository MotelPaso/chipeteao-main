class_name FireBurst
extends Node3D
## Columna de fuego del pool: un cilindro de llamas (tramos del mismo muro de
## las ondas de fuego, fire_wall.gdshader) que brota de golpe de un punto del
## suelo, se ensancha y se apaga, con un fogonazo de luz. Solo es un efecto:
## no quema a nadie. La usan los golpes grandes de Mythos (la Picada, el
## Aletazo, la Embestida). Toma el color de su segunda fase junto con el
## resto del fuego (FireTint).

@export_group("Aspecto")
## Tramos de llama de la columna.
@export var segments: int = 10
## Fracción del radio pedido con la que nace (0-1).
@export_range(0.05, 1.0) var start_radius: float = 0.35
## Fracción de la altura pedida con la que nace (0-1).
@export_range(0.05, 1.0) var start_height: float = 0.25
## Segundos que tarda en llegar a su radio y su altura completos.
@export var rise_seconds: float = 0.14
## Segundos que tarda después en apagarse.
@export var fade_seconds: float = 0.5
## Cuánto más se ensancha mientras se apaga (1.35 = 35 % más).
@export var fade_spread: float = 1.35
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.25

@export_group("Luz")
## Brillo del fogonazo al nacer.
@export var light_energy: float = 7.0
## Alcance de la luz, en veces el radio de la columna.
@export var light_reach: float = 4.0
## Color de la luz.
@export var light_color: Color = Color(1.0, 0.6, 0.25)
## Color de la luz con el fuego de la segunda fase de Mythos.
@export var reborn_light_color: Color = Color(0.45, 0.75, 1.0)

var _radius: float = 1.0
var _height: float = 1.0
var _elapsed: float = 0.0

@onready var _wall: MultiMeshInstance3D = $Wall
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	# Cada columna del pool mueve sus propios tramos: copia el MultiMesh de
	# la escena (que trae la malla del tramo) en vez de compartirlo.
	var multimesh := _wall.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = maxi(segments, 3)
	multimesh.custom_aabb = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 40.0, 40.0))
	_wall.multimesh = multimesh
	pool_reset()


## Contrato de nodo del pool: columna nueva en cada adquisición.
func pool_reset() -> void:
	_wall.visible = false
	_light.visible = false
	set_process(false)


## Saca del pool una columna y la enciende en `at` (un punto sobre el suelo),
## de `radius` metros de radio y `height` de alto.
static func spawn(scene: PackedScene, at: Vector3, radius: float, height: float) -> void:
	var burst := Pools.acquire_scene(scene) as FireBurst if scene != null else null
	if burst != null:
		burst.play(at, radius, height)


## Enciende ESTA columna en `at`, con lo mismo que pide spawn().
func play(at: Vector3, radius: float, height: float) -> void:
	global_transform = Transform3D(Basis.IDENTITY, at)
	_radius = maxf(radius, 0.1)
	_height = maxf(height, 0.1)
	_elapsed = 0.0
	_light.light_color = light_color.lerp(reborn_light_color, FireTint.amount())
	_light.omni_range = _radius * light_reach
	_light.position = Vector3(0.0, minf(_height * 0.25, 3.0), 0.0)
	_wall.visible = true
	_light.visible = true
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= rise_seconds + fade_seconds:
		pool_reset()
		Pools.release(self)
		return
	_apply()


# --- privados ---------------------------------------------------------------------

## Tamaño, opacidad y luz según los segundos que lleva encendida.
func _apply() -> void:
	var rise := clampf(_elapsed / maxf(rise_seconds, 0.01), 0.0, 1.0)
	var fade := clampf((_elapsed - rise_seconds) / maxf(fade_seconds, 0.01), 0.0, 1.0)
	# Sale disparada y frena al llegar arriba.
	var grown := 1.0 - (1.0 - rise) * (1.0 - rise)
	var radius := _radius * lerpf(start_radius, 1.0, grown) * lerpf(1.0, fade_spread, fade)
	_place(radius, _height * lerpf(start_height, 1.0, grown))
	_wall.set_instance_shader_parameter(&"fade", 1.0 - fade)
	_light.light_energy = light_energy * (1.0 - fade)


## Reparte los tramos en círculo, de pie sobre el punto donde brota.
func _place(radius: float, height: float) -> void:
	var multimesh := _wall.multimesh
	var count := multimesh.instance_count
	var width := TAU * radius / float(count) * segment_overlap
	for index: int in count:
		var angle := TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		multimesh.set_instance_transform(index, Transform3D(
				Basis(tangent * width, Vector3.UP * height, outward),
				outward * radius + Vector3.UP * height * 0.5))
