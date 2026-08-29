extends StaticBody3D
## Practice target: damageable via its Health child, leaves the "enemies"
## group on death and respawns at full HP after a delay so weapon testing
## is repeatable.

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
	_respawn()


func _respawn() -> void:
	_health.heal_full()
	add_to_group("enemies")
	_mesh.visible = true
	_collision.set_deferred("disabled", false)
