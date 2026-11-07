class_name TelegraphDisc
extends MeshInstance3D
## Disco de aviso en el suelo, reusado por Pools: se llena desde el centro,
## sube su brillo y se desvanece. El cilindro de radio 1 se escala al radio
## pedido. La opacidad inicial sale del material de TelegraphDisc.tscn; el
## material es local a la escena, así cada instancia del pool anima su propia
## copia de alfa y emisión.

@export_group("Animación")
## Brillo de la emisión al empezar la carga. Va aquí y no en el material:
## Godot no guarda la emisión de un material sin sombreado en el .tscn.
@export var start_energy: float = 1.2
## Fracción del radio con la que aparece el disco antes de crecer (0-1).
@export var start_scale: float = 0.2
## Brillo de la emisión al terminar la carga.
@export var peak_energy: float = 2.6
## Segundos que tarda en desvanecerse tras la carga.
@export var fade_time: float = 0.15
## Metros sobre el suelo, para que el disco no parpadee contra el terreno.
@export var lift: float = 0.04

var _tween: Tween = null
var _start_alpha: float = 0.45


func _ready() -> void:
	var material := material_override as StandardMaterial3D
	if material != null:
		_start_alpha = material.albedo_color.a


## Contrato de nodo del pool: sin crecer ni desvanecerse lo del aviso anterior.
func pool_reset() -> void:
	_kill_tween()


## Reproduce un aviso; el nodo vuelve solo al pool tras desvanecerse.
func show_disc(center: Vector3, radius: float, duration: float, color: Color) -> void:
	var material := material_override as StandardMaterial3D
	if material == null:
		# El nodo salió del pool: irse sin devolverlo lo dejaría varado en la
		# escena para siempre.
		Pools.release(self)
		return
	material.albedo_color = Color(color.r, color.g, color.b, _start_alpha)
	material.emission = color
	material.emission_energy_multiplier = start_energy
	global_position = center + Vector3.UP * lift
	scale = Vector3(start_scale * radius, 1.0, start_scale * radius)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3(radius, 1.0, radius), duration)
	_tween.tween_property(material, "emission_energy_multiplier", peak_energy, duration)
	_tween.chain().tween_property(material, "albedo_color:a", 0.0, fade_time)
	_tween.chain().tween_callback(_on_disc_done)


func _on_disc_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
