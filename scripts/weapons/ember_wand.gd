extends WeaponBase
## Vara de brasas: en cada enfriamiento detona un estallido de fuego en la
## posición del blanco que daña a todo cuerpo del grupo "enemies" dentro de
## burst_radius. El visual es un EmberBurst del pool: cáscara que se
## expande, una quemadura en el suelo que se desvanece y brasas que suben.

@export_group("Estallido")
## Radio del estallido, en metros (los tomos de área lo escalan); la evolución «Lanza solar» lo multiplica.
@export var burst_radius: float = 2.5

@export_group("Multitud")
## Segundos entre las detonaciones extra del Tomo de Multitud; dos en el mismo frame serían una explosión que tira el daño dos veces.
@export var extra_stagger: float = 0.1


func fire(target: Node3D) -> void:
	fire_volley_retarget(maxi(effective_projectile_count(), 1),
			_detonate.bind(target.global_position), _rekindle, extra_stagger)


## Una detonación extra del Tomo de Multitud. Elige su PROPIO centro en vez de
## reusar el de la ráfaga: el primer estallido pudo haber vaciado ese punto, y
## volver a buscar reparte los extras por la horda.
func _rekindle() -> void:
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
