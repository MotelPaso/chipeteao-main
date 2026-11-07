extends StaticBody3D
## Muñeco de práctica: recibe daño por su hijo Health, sale del grupo
## "enemies" al morir y reaparece con la vida llena tras una espera, para
## probar armas una y otra vez.

@export var respawn_delay: float = 3.0

@onready var _health: Health = $Health
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_health.died.connect(_on_died)


func _on_died() -> void:
	remove_from_group("enemies")
	_mesh.visible = false
	_collision.set_deferred("disabled", true)
	await get_tree().create_timer(respawn_delay).timeout
	# El SceneTreeTimer sobrevive a quien lo espera: un cambio de mapa durante
	# la espera reanudaría esta corrutina sobre un muñeco liberado.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_respawn()


func _respawn() -> void:
	_health.heal_full()
	add_to_group("enemies")
	_mesh.visible = true
	_collision.set_deferred("disabled", false)
