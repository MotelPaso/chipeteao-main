class_name EnemyBolt
extends Area3D
## Proyectil enemigo: vuela recto por -Z a una velocidad que se esquiva de
## lado y solo daña a raiders. Su máscara es mundo + jugador (capa 1), así
## que nunca detecta cuerpos de la capa de enemigos. Vuelve a Pools al tocar
## cualquier cuerpo (raider, suelo, prop) o tras max_distance.
## `monitorable` está apagado en EnemyBolt.tscn: la saeta solo DETECTA
## cuerpos y nadie detecta áreas, así que ser detectable solo costaría
## trabajo de física. NodePool guarda el valor al soltarla y lo restaura al
## reusarla.

@export var speed: float = 10.0
@export var damage: float = 8.0
@export var max_distance: float = 30.0

## El enemigo que la disparó, para que un golpe reflejado tenga a quién
## volver. Se limpia en cada reuso: una saeta del pool con el lanzador
## anterior le devolvería el daño al cuerpo equivocado (o a uno liberado).
var launcher: Node3D = null
## Lo marca EnemySpawner.freeze_enemies: una saeta congelada queda quieta en
## el aire. Es una BANDERA y no set_physics_process(false) porque
## NodePool.release guarda el estado de proceso y acquire() lo restaura: una
## saeta congelada así volvería inerte para siempre.
var frozen: bool = false

var _travelled: float = 0.0
## Daño por defecto de la escena, restaurado al reusarla (quien dispara lo
## pisa en cada tiro DESPUÉS del reset del pool, así el daño de un shiny no
## pasa a la siguiente saeta).
var _default_damage: float = 8.0
## Se marca en cuanto la saeta se gasta. Pools.release DIFIERE el cambio de
## padre, así que el Area3D sigue detectando durante el resto del vaciado de
## señales: sin esta bandera dos raiders que entran en el mismo paso de
## física recibirían cada uno un golpe completo de la misma saeta.
var _spent: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Se une aquí Y en pool_reset: al soltarla se cambia de padre (no se
	# libera), y el tiempo detenido tiene que encontrar cada saeta en vuelo
	# sin recorrer todo el árbol.
	add_to_group(&"enemy_projectiles")
	_default_damage = damage


## Contrato de nodo del pool: vuelo nuevo en cada reuso.
func pool_reset() -> void:
	damage = _default_damage
	_travelled = 0.0
	_spent = false
	frozen = false
	launcher = null
	if not is_in_group(&"enemy_projectiles"):
		add_to_group(&"enemy_projectiles")


func _physics_process(delta: float) -> void:
	if _spent or frozen:
		return
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= max_distance:
		_spend()


func _on_body_entered(body: Node3D) -> void:
	# Una saeta congelada cuelga en el tiempo detenido: no se gasta ni daña
	# al raider que pasa a su lado. Su Area3D sigue detectando mientras está
	# congelada (por eso es una bandera), y sin esto una bala ya en el aire
	# rompería la única promesa del tiempo detenido: que nada te toca.
	if _spent or frozen:
		return
	if body.is_in_group("player"):
		var health := Health.find_in(body)
		if health != null:
			# Nombra al lanzador para que Reflejo (y las espinas) se lo
			# devuelvan; si ya murió pasa null y solo hace su daño.
			health.take_damage(damage, false,
					launcher if is_instance_valid(launcher) else null)
	_spend()


func _spend() -> void:
	_spent = true
	Pools.release(self)
