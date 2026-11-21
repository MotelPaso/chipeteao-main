class_name FireBlast
extends Node3D
## Estallido de fuego del pool, en capas: una bola que se hincha y se deshace
## en jirones (Ball), un anillo de choque que se abre a ras de suelo (Ring),
## un chorro de chispas (Sparks), un fogonazo de luz que ilumina el suelo
## (Light) y la quemadura con grietas encendidas que queda un rato (Scorch).
## Solo es un efecto: el daño lo hace quien lo pide. Estallan así las bolas
## de fuego de Mythos y sus golpes grandes. Toma el color de su segunda fase
## junto con el resto del fuego (FireTint).

@export_group("Bola")
## Segundos que tarda la bola en hincharse y deshacerse.
@export var ball_seconds: float = 0.6
## Tamaño de la bola al nacer, en veces el radio pedido.
@export var ball_start: float = 0.25
## Tamaño de la bola al terminar, en veces el radio pedido.
@export var ball_end: float = 1.0

@export_group("Anillo de choque")
## Segundos que tarda el anillo en abrirse y apagarse.
@export var ring_seconds: float = 0.55
## Hasta dónde llega el anillo, en veces el radio pedido.
@export var ring_reach: float = 1.8

@export_group("Chispas")
## Chispas por cada metro de radio (hasta el `amount` del nodo Sparks).
@export var sparks_per_metre: float = 10.0
## Velocidad de las chispas, en metros por segundo por cada metro de radio.
@export var spark_speed_per_metre: float = 3.2

@export_group("Luz")
## Brillo del fogonazo al nacer.
@export var light_energy: float = 9.0
## Alcance de la luz, en veces el radio pedido.
@export var light_reach: float = 4.0
## Segundos que tarda la luz en apagarse.
@export var light_seconds: float = 0.5
## Color de la luz.
@export var light_color: Color = Color(1.0, 0.62, 0.25)
## Color de la luz con el fuego de la segunda fase de Mythos.
@export var reborn_light_color: Color = Color(0.45, 0.75, 1.0)

@export_group("Quemadura")
## Segundos que la quemadura queda en el suelo.
@export var scorch_seconds: float = 2.8
## Tamaño de la quemadura, en veces el radio pedido.
@export var scorch_size: float = 0.95
## Metros sobre el suelo, para que no parpadee contra el terreno.
@export var ground_lift: float = 0.06

var _radius: float = 1.0
var _elapsed: float = 0.0

@onready var _ball: MeshInstance3D = $Ball
@onready var _ring: MeshInstance3D = $Ring
@onready var _sparks: CPUParticles3D = $Sparks
@onready var _light: OmniLight3D = $Light
@onready var _scorch: MeshInstance3D = $Scorch
@onready var _cracks: MeshInstance3D = $Scorch/Cracks
## El tope de chispas es el `amount` que trae la escena.
@onready var _spark_cap: int = _sparks.amount


func _ready() -> void:
	pool_reset()


## Contrato de nodo del pool: estallido nuevo en cada adquisición.
func pool_reset() -> void:
	visible = false
	_sparks.emitting = false
	set_process(false)


## Saca del pool un estallido y lo enciende en `at` (un punto sobre el
## suelo), para un golpe de `radius` metros.
static func spawn(scene: PackedScene, at: Vector3, radius: float) -> void:
	var blast := Pools.acquire_scene(scene) as FireBlast if scene != null else null
	if blast != null:
		blast.play(at, radius)


## Enciende ESTE estallido en `at`, para un golpe de `radius` metros.
func play(at: Vector3, radius: float) -> void:
	global_transform = Transform3D(Basis.IDENTITY, at)
	_radius = maxf(radius, 0.1)
	_elapsed = 0.0
	_ring.position.y = ground_lift
	_ring.scale = Vector3.ONE * _radius * ring_reach
	_scorch.position.y = ground_lift * 0.5
	_scorch.scale = Vector3.ONE * _radius * scorch_size
	_light.light_color = light_color.lerp(reborn_light_color, FireTint.amount())
	_light.omni_range = _radius * light_reach
	_light.position.y = minf(_radius * 0.5, 2.5)
	_sparks.amount = clampi(roundi(sparks_per_metre * _radius), 4, _spark_cap)
	_sparks.initial_velocity_max = spark_speed_per_metre * _radius + 4.0
	_sparks.initial_velocity_min = _sparks.initial_velocity_max * 0.45
	_sparks.restart()
	_sparks.emitting = true
	visible = true
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= maxf(scorch_seconds, maxf(ball_seconds, ring_seconds)):
		pool_reset()
		Pools.release(self)
		return
	_apply()


# --- privados ---------------------------------------------------------------------

## Cada capa según los segundos que lleva el estallido.
func _apply() -> void:
	var ball := clampf(_elapsed / maxf(ball_seconds, 0.01), 0.0, 1.0)
	# Sale disparada y frena: casi todo el tamaño llega en el primer tercio.
	var grown := 1.0 - pow(1.0 - ball, 3.0)
	_ball.visible = ball < 1.0
	_ball.scale = Vector3.ONE * _radius * lerpf(ball_start, ball_end, grown)
	_ball.set_instance_shader_parameter(&"life", ball)
	var ring := clampf(_elapsed / maxf(ring_seconds, 0.01), 0.0, 1.0)
	_ring.visible = ring < 1.0
	_ring.set_instance_shader_parameter(&"reach", 1.0 - pow(1.0 - ring, 2.0))
	_ring.set_instance_shader_parameter(&"fade", 1.0 - ring * ring)
	var light := clampf(_elapsed / maxf(light_seconds, 0.01), 0.0, 1.0)
	_light.visible = light < 1.0
	_light.light_energy = light_energy * (1.0 - light) * (1.0 - light)
	var scorch := clampf(_elapsed / maxf(scorch_seconds, 0.01), 0.0, 1.0)
	# La quemadura aparece con el golpe y se va de a poco; sus grietas se
	# enfrían antes.
	_scorch.transparency = smoothstep(0.55, 1.0, scorch)
	_cracks.set_instance_shader_parameter(&"fade", 1.0 - smoothstep(0.05, 0.7, scorch))
