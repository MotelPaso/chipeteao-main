extends WeaponBase
## Vara de brasas: en cada enfriamiento detona un estallido de fuego en la
## posición del blanco que daña a todo cuerpo del grupo "enemies" dentro de
## burst_radius. El visual es un EmberBurst del pool: cáscara emisiva que se
## expande, una quemadura en el suelo que se desvanece y brasas que suben.

@export var burst_radius: float = 2.5

## Segundos entre las detonaciones que agrega el Tomo de Multitud.
## Escalonadas, no simultáneas: dos estallidos sobre el mismo cuerpo en el
## mismo frame son una explosión que tira el daño dos veces.
const EXTRA_BURST_STAGGER: float = 0.1
## La cadena escalonada entera termina dentro de esta fracción de un
## enfriamiento, o la cola de una ráfaga se montaría sobre la siguiente.
const BURST_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_BURST_STAGGER,
			effective_cooldown() * BURST_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_detonate(target.global_position)
	for i: int in range(1, count):
		# Temporizador pausable y en paso de física: un estallido extra no sale
		# con la pantalla de mejoras abierta, y el daño cae en el mismo tick que
		# el resto del combate.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_rekindle)


## Una detonación extra del Tomo de Multitud. Elige su PROPIO centro en vez de
## reusar el de la ráfaga: el primer estallido pudo haber vaciado ese punto, y
## volver a buscar reparte los extras por la horda. Llega un poco después de
## fire(), cuando el arma puede haber salido del árbol con un raider quitado.
func _rekindle() -> void:
	if not is_inside_tree():
		return
	var target := acquire_target()
	if target != null:
		_detonate(target.global_position)


func _detonate(center: Vector3) -> void:
	# Los tomos de área agrandan el estallido; el visual crece al mismo radio.
	var radius := burst_radius * area_scale()
	# Una esfera, no un disco: la detonación alcanza cuerpos por encima y por
	# debajo de su centro igual que los de al lado.
	damage_all(enemies_in_sphere(center, radius))
	_spawn_burst_visual(center, radius)


func _spawn_burst_visual(center: Vector3, radius: float) -> void:
	# Del pool, colgado de la arena: el efecto queda en su lugar mientras el
	# jugador camina (y sobrevive a que esta arma se libere).
	var burst := Pools.acquire_scene(Pools.EMBER_BURST_SCENE) as EmberBurst
	if burst == null:
		return
	burst.play(center, radius)
