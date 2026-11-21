class_name ClawScar
extends MeshInstance3D
## La marca que deja en el suelo un zarpazo de Mythos, del pool: tres tajos
## al rojo vivo que se enfrían y se apagan. Solo es visual: el golpe y su
## daño los decide quien lo pide. El plano de lado 1 se escala al tamaño
## pedido; los colores y la forma de los tajos viven en su material y pasan a
## los de la segunda fase con el resto del fuego (FireTint).

@export_group("Animación")
## Segundos que tarda en enfriarse y apagarse.
@export var burn_seconds: float = 1.6
## Metros sobre el suelo, para que no parpadee contra el terreno.
@export var lift: float = 0.08
## Ancho de la marca, en veces su largo.
@export var width_ratio: float = 0.8

var _tween: Tween = null


## Contrato de nodo del pool: sin la animación de la marca anterior.
func pool_reset() -> void:
	_kill_tween()
	visible = false


## Deja una marca de `length` metros en `center` (un punto a ras de suelo),
## con los tajos a lo largo de `heading`.
static func spawn(scene: PackedScene, center: Vector3, heading: Vector3, length: float) -> void:
	var scar := Pools.acquire_scene(scene) as ClawScar
	if scar != null:
		scar.play(center, heading, length)


## Muestra la marca; vuelve sola al pool cuando se apaga.
func play(center: Vector3, heading: Vector3, length: float) -> void:
	var flat := Vector3(heading.x, 0.0, heading.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	# El largo del plano (su Z) va a lo largo del zarpazo.
	global_transform = Transform3D(
			Basis(Vector3.UP.cross(flat) * length * width_ratio, Vector3.UP, flat * length),
			center + Vector3.UP * lift)
	visible = true
	set_instance_shader_parameter(&"life", 0.0)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_set_life, 0.0, 1.0, maxf(burn_seconds, 0.05))
	_tween.tween_callback(_on_done)


func _set_life(value: float) -> void:
	set_instance_shader_parameter(&"life", value)


func _on_done() -> void:
	visible = false
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
