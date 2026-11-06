class_name TelegraphDisc
extends MeshInstance3D
## Disco de aviso en el suelo, reusado por Pools: se llena desde el centro,
## sube su brillo y se desvanece. El cilindro de radio 1 se escala al radio
## pedido, empezando en 0.2 del radio. El material es local a la escena, así
## cada instancia del pool anima su propia copia de alfa y emisión.

var _tween: Tween = null


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
	material.albedo_color = Color(color.r, color.g, color.b, 0.45)
	material.emission = color
	material.emission_energy_multiplier = 1.2
	global_position = center + Vector3.UP * 0.04
	scale = Vector3(0.2 * radius, 1.0, 0.2 * radius)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3(radius, 1.0, radius), duration)
	_tween.tween_property(material, "emission_energy_multiplier", 2.6, duration)
	_tween.chain().tween_property(material, "albedo_color:a", 0.0, 0.15)
	_tween.chain().tween_callback(_on_disc_done)


func _on_disc_done() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
