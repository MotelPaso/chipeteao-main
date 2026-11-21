class_name MythosHalo
extends MeshInstance3D
## El resplandor que rodea el cuerpo de Mythos (nodo Halo de Mythos.tscn). Su
## color de siempre es el de su material en la escena; en la forma renacida
## pasa a ascended_color. Pinta sobre una copia propia de ese material: el de
## la escena es compartido. Es la primera malla del modelo, así que el
## estallido con que muere el jefe toma su color (EnemyOverlays).

@export_group("Renacido")
## Color y opacidad del resplandor en la forma renacida.
@export var ascended_color: Color = Color(0.1, 0.35, 1.0, 0.13)

var _material: StandardMaterial3D = null
var _base_color: Color = Color.WHITE


func _ready() -> void:
	_material = get_surface_override_material(0).duplicate() as StandardMaterial3D
	set_surface_override_material(0, _material)
	_base_color = _material.albedo_color


func _notification(what: int) -> void:
	# La copia muere con este nodo: se la quita a la malla antes, así el motor
	# nunca dibuja ni revisa una malla que apunta a un material ya liberado.
	if what == NOTIFICATION_PREDELETE:
		set_surface_override_material(0, null)


## Cuánto tomó la forma renacida (0-1).
func set_ascend(amount: float) -> void:
	_material.albedo_color = _base_color.lerp(ascended_color, clampf(amount, 0.0, 1.0))
