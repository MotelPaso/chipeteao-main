class_name ImpactRipple
extends MeshInstance3D
## Onda de un golpe en el suelo, del pool: un fogonazo en el centro, anillos
## que se abren hasta el borde del golpe y rayos que se apagan
## (impact_ripple.gdshader), sobre un cuadro acostado en el suelo. Solo es un
## efecto: no daña a nadie. La usan los golpes de la Langosta Azul (LobsterFx)
## para mostrar dónde cayó cada uno y hasta dónde llegó.

@export_group("Onda")
## Segundos que dura.
@export var seconds: float = 0.5
## Metros sobre el suelo, para que no parpadee contra el terreno.
@export var lift: float = 0.07

var _elapsed: float = 0.0


func _ready() -> void:
	pool_reset()


## Contrato de nodo del pool: onda nueva en cada adquisición.
func pool_reset() -> void:
	visible = false
	set_process(false)


## Saca del pool una onda y la abre en `at` (un punto sobre el suelo), hasta
## `radius` metros, del color `color`.
static func spawn(scene: PackedScene, at: Vector3, radius: float, color: Color) -> void:
	var ripple := Pools.acquire_scene(scene) as ImpactRipple if scene != null else null
	if ripple != null:
		ripple.play(at, radius, color)


## Abre ESTA onda, con lo mismo que pide spawn().
func play(at: Vector3, radius: float, color: Color) -> void:
	var reach := maxf(radius, 0.1)
	global_transform = Transform3D(Basis.from_scale(Vector3(reach, 1.0, reach)),
			at + Vector3.UP * lift)
	set_instance_shader_parameter(&"tint", color)
	set_instance_shader_parameter(&"progress", 0.0)
	_elapsed = 0.0
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := _elapsed / maxf(seconds, 0.01)
	if progress >= 1.0:
		pool_reset()
		Pools.release(self)
		return
	set_instance_shader_parameter(&"progress", progress)
