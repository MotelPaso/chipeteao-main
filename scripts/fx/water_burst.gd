class_name WaterBurst
extends Node3D
## Chorro de agua del pool: una columna de agua (tramos en círculo con
## water_column.gdshader) que brota de golpe de un punto del suelo, se abre y
## cae, con gotas que saltan (nodo Drops) y un destello de luz (nodo Light).
## Solo es un efecto: no daña a nadie. Lo usan los golpes de la Langosta Azul
## (LobsterFx): un pinzazo, la caída del Salto, cada salida de la Emboscada,
## la estela de la Embestida.
## Las gotas de la escena están ajustadas para un chorro de reference_radius
## por reference_height metros; con otro tamaño se escalan desde ahí.

@export_group("Aspecto")
## Tramos de agua de la columna.
@export var segments: int = 10
## Fracción del radio pedido con la que nace (0-1).
@export_range(0.05, 1.0) var start_radius: float = 0.45
## Fracción de la altura pedida con la que nace (0-1).
@export_range(0.05, 1.0) var start_height: float = 0.15
## Segundos que tarda en llegar a su radio y su altura completos.
@export var rise_seconds: float = 0.13
## Segundos que tarda después en caer y apagarse.
@export var fade_seconds: float = 0.5
## Cuánto más se abre mientras cae (1.5 = 50 % más ancha).
@export var fade_spread: float = 1.5
## Fracción de su altura con la que termina de caer (0-1).
@export_range(0.1, 1.0) var fade_height: float = 0.6
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.3

@export_group("Luz")
## Brillo del destello al nacer.
@export var light_energy: float = 4.5
## Alcance de la luz, en veces el radio del chorro.
@export var light_reach: float = 5.0
## Color de la luz.
@export var light_color: Color = Color(0.62, 0.9, 1.0)
## Radio mínimo del chorro, en metros, para que lleve destello: los chorros chicos (una estela, una corona) no lo llevan.
@export var light_min_radius: float = 1.0

@export_group("Gotas")
## Radio del chorro, en metros, para el que están ajustadas las gotas de la escena.
@export var reference_radius: float = 1.0
## Alto del chorro, en metros, para el que están ajustadas las gotas de la escena.
@export var reference_height: float = 4.0

var _radius: float = 1.0
var _height: float = 1.0
var _elapsed: float = 0.0
## Segundos hasta volver al pool: lo que dure más, la columna o las gotas.
var _life: float = 1.0
## Lo que traen las gotas en la escena (para el chorro de referencia).
var _drop_speed: Vector2 = Vector2.ZERO
var _drop_scale: Vector2 = Vector2.ONE
var _drop_spread: float = 0.5

@onready var _column: MultiMeshInstance3D = $Column
@onready var _light: OmniLight3D = $Light
@onready var _drops: CPUParticles3D = $Drops


func _ready() -> void:
	# Cada chorro del pool mueve sus propios tramos: copia el MultiMesh de la
	# escena (que trae la malla del tramo) en vez de compartirlo.
	var multimesh := _column.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = maxi(segments, 3)
	multimesh.custom_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 30.0, 24.0))
	_column.multimesh = multimesh
	_drop_speed = Vector2(_drops.initial_velocity_min, _drops.initial_velocity_max)
	_drop_scale = Vector2(_drops.scale_amount_min, _drops.scale_amount_max)
	_drop_spread = _drops.emission_sphere_radius
	pool_reset()


## Contrato de nodo del pool: chorro nuevo en cada adquisición.
func pool_reset() -> void:
	_column.visible = false
	_light.visible = false
	_drops.emitting = false
	set_process(false)


## Saca del pool un chorro y lo hace brotar en `at` (un punto sobre el suelo),
## de `radius` metros de radio y `height` de alto.
static func spawn(scene: PackedScene, at: Vector3, radius: float, height: float) -> void:
	var burst := Pools.acquire_scene(scene) as WaterBurst if scene != null else null
	if burst != null:
		burst.play(at, radius, height)


## Hace brotar ESTE chorro en `at`, con lo mismo que pide spawn().
func play(at: Vector3, radius: float, height: float) -> void:
	global_transform = Transform3D(Basis.IDENTITY, at)
	_radius = maxf(radius, 0.1)
	_height = maxf(height, 0.1)
	_elapsed = 0.0
	_life = maxf(rise_seconds + fade_seconds, _drops.lifetime) + 0.05
	_light.light_color = light_color
	_light.omni_range = _radius * light_reach
	_light.position = Vector3(0.0, minf(_height * 0.3, 2.5), 0.0)
	_column.visible = true
	_light.visible = _radius >= light_min_radius
	_throw_drops()
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life:
		pool_reset()
		Pools.release(self)
		return
	_apply()


# --- privados ---------------------------------------------------------------------

## Las gotas saltan más alto y más lejos cuanto más grande es el chorro.
func _throw_drops() -> void:
	var taller := sqrt(_height / maxf(reference_height, 0.1))
	var wider := _radius / maxf(reference_radius, 0.1)
	_drops.initial_velocity_min = _drop_speed.x * taller
	_drops.initial_velocity_max = _drop_speed.y * taller
	_drops.emission_sphere_radius = _drop_spread * wider
	var bigger := clampf(sqrt(wider), 0.6, 1.8)
	_drops.scale_amount_min = _drop_scale.x * bigger
	_drops.scale_amount_max = _drop_scale.y * bigger
	_drops.restart()
	_drops.emitting = true


## Tamaño, opacidad y luz según los segundos que lleva.
func _apply() -> void:
	var rise := clampf(_elapsed / maxf(rise_seconds, 0.01), 0.0, 1.0)
	var fade := clampf((_elapsed - rise_seconds) / maxf(fade_seconds, 0.01), 0.0, 1.0)
	if fade >= 1.0:
		# La columna ya cayó: solo quedan las gotas en el aire.
		_column.visible = false
		_light.visible = false
		return
	# Sale disparada y frena al llegar arriba.
	var grown := 1.0 - (1.0 - rise) * (1.0 - rise)
	var radius := _radius * lerpf(start_radius, 1.0, grown) * lerpf(1.0, fade_spread, fade)
	var height := _height * lerpf(start_height, 1.0, grown) * lerpf(1.0, fade_height, fade * fade)
	_place(radius, height)
	_column.set_instance_shader_parameter(&"fade", 1.0 - fade)
	_light.light_energy = light_energy * (1.0 - fade)


## Reparte los tramos en círculo, de pie sobre el punto donde brota.
func _place(radius: float, height: float) -> void:
	var multimesh := _column.multimesh
	var count := multimesh.instance_count
	var width := TAU * radius / float(count) * segment_overlap
	for index: int in count:
		var angle := TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		multimesh.set_instance_transform(index, Transform3D(
				Basis(tangent * width, Vector3.UP * height, outward),
				outward * radius + Vector3.UP * height * 0.5))
