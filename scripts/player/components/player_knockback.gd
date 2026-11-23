class_name PlayerKnockback
extends Node
## Empujón al recibir un golpe: cuando un golpe que nombra a su atacante
## llega a la vida del raider (Health.damaged_by: contacto, disparos,
## alientos), lo empuja lejos de ese atacante. El freno sale solo: Player
## lleva la velocidad hacia la que pide el jugador con su aceleración, así
## el empujón se apaga en un instante. Es el nodo Knockback de Player.tscn.

@export_group("Empujón al recibir golpe")
## Velocidad del empujón, en m/s (0 = sin empujón).
@export var push_speed: float = 9.5
## Saltito hacia arriba del empujón, en m/s (0 = se queda pegado al suelo).
@export var push_lift: float = 2.5
## Segundos mínimos entre dos empujones, para que un daño por segundo no lo zarandee.
@export var min_interval: float = 0.35

var _cooldown_left: float = 0.0

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D


func _ready() -> void:
	var health := Health.find_in(_body)
	if health != null:
		health.damaged_by.connect(_on_damaged_by)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## Lanzamiento desde un punto (meteoritos, explosiones): empuja al raider
## lejos de `from` y hacia arriba, sin esperar el intervalo mínimo.
func launch_from(from: Vector3, speed: float, lift: float) -> void:
	if _body == null:
		return
	var player := _body as Player
	if player != null and (player.is_downed() or player.is_rooted()):
		return
	var away := _body.global_position - from
	away.y = 0.0
	# Justo en el centro del impacto no hay "afuera": sale hacia atrás.
	if away.length_squared() < 0.01:
		away = _body.global_basis.z
	away = away.normalized() * speed
	_body.velocity.x += away.x
	_body.velocity.z += away.z
	_body.velocity.y = maxf(_body.velocity.y, lift)
	_cooldown_left = min_interval


func _on_damaged_by(attacker: Node3D) -> void:
	if _cooldown_left > 0.0 or push_speed <= 0.0 or attacker == null \
			or not is_instance_valid(attacker) or _body == null:
		return
	var player := _body as Player
	if player != null and (player.is_downed() or player.is_rooted()):
		return
	var away := _body.global_position - attacker.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	away = away.normalized() * push_speed
	_body.velocity.x += away.x
	_body.velocity.z += away.z
	_body.velocity.y = maxf(_body.velocity.y, push_lift)
	_cooldown_left = min_interval
