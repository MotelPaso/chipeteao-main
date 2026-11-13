extends FieldWeapon
## Hedor: pulsos flatulentos. En cada enfriamiento estalla una ráfaga de nubes
## de gas desde el portador (una por proyectil, escalonadas). Cada nube daña,
## envenena y ralentiza todo lo que hay en su radio. Cómo usa los ajustes de WeaponBase:
##   damage            — golpe de cada pulso (por deal_damage); el veneno por segundo sale de él
##   cooldown          — segundos entre ráfagas
##   attack_range      — radio de la nube (los tomos de área lo escalan)
##   projectile_count  — pulsos por ráfaga (el Tomo de Multitud suma)
## Cada golpe suma un stack de veneno (más daño por segundo) y más tiempo,
## hasta un tope de stacks y de duración.
## Veneno y ralentización duran más con el stat de duración. El radio y la
## altura vienen de FieldWeapon.
## La evolución «Miasma» multiplica poison_duration y attack_range.

@export_group("Veneno y ralentización")
## Veneno por segundo POR STACK, como fracción del daño efectivo del pulso (0.2 = 20%).
@export var poison_damage_fraction: float = 0.2
## Stacks máximos. Con 0.2 por stack, 5 stacks = 100% del daño del arma por segundo.
@export var max_poison_stacks: int = 5
## Segundos de veneno que suma CADA golpe; la carta «Hedor más rancio» y la evolución «Miasma» lo alargan.
@export var poison_duration: float = 3.0
## Tope de segundos de veneno acumulados en un enemigo (súbelo mucho para quitar el tope).
@export var max_poison_duration: float = 15.0
## Multiplicador de velocidad de los enemigos ralentizados (0.6 = conservan el 60%).
@export var slow_multiplier: float = 0.6
## Segundos de ralentización por pulso.
@export var slow_duration: float = 2.0

@export_group("Ráfaga")
## Segundos entre pulsos de una misma ráfaga. Fijo: no se comprime con el enfriamiento.
@export var burst_stagger: float = 0.15

@export_group("Nube")
## Malla y material de la nube (color y opacidad en albedo_color); radio 1, se escala al radio del pulso.
@export var cloud_mesh: Mesh
## Cuánto debajo del montaje del arma nace la nube, en metros.
@export var cloud_drop: float = 0.3
## Escala con que nace la nube antes de crecer, en metros de radio.
@export var cloud_start_scale: float = 0.3
## Segundos que tarda la nube en crecer hasta el radio del pulso.
@export var cloud_grow_time: float = 0.45
## Segundos que tarda la nube en desvanecerse.
@export var cloud_fade_time: float = 0.6

## id de instancia del enemigo -> {"stacks": int, "until": float} (run_time en que acaba su veneno).
var _poison_state: Dictionary[int, Dictionary] = {}


func fire(_target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	# El primer pulso sale ya; los demás escalonados, cada uno busca sus enemigos al salir.
	fire_volley_retarget(count, _pulse, _pulse, burst_stagger, false)


func _pulse() -> void:
	var radius := reach()
	var now := RunState.run_time
	for body: Node3D in enemies_in_disc(global_position, radius, height_window):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		# Los cadáveres no reciben estados: apply_poison ya rechaza a los
		# muertos, y una ralentización sobre un cuerpo que este pulso mató solo
		# deja estado para quien lo lea después.
		if enemy != null and (health == null or not health.is_dead):
			_stack_poison(enemy, now)
			enemy.apply_slow(slow_multiplier, slow_duration * duration_scale())
	_prune_poison(now)
	_play_cloud(radius)


## Cada golpe suma un stack (más daño por segundo) y más duración al veneno vigente.
func _stack_poison(enemy: EnemyBase, now: float) -> void:
	var id := enemy.get_instance_id()
	var state: Dictionary = _poison_state.get(id, {"stacks": 0, "until": 0.0})
	var remaining := maxf(float(state.until) - now, 0.0)
	# Veneno expirado: los stacks se reinician.
	var stacks := int(state.stacks) if remaining > 0.0 else 0
	stacks = mini(stacks + 1, maxi(max_poison_stacks, 1))
	var total := minf(remaining + poison_duration * duration_scale(), max_poison_duration)
	_poison_state[id] = {"stacks": stacks, "until": now + total}
	var dps := effective_damage() * poison_damage_fraction * float(stacks)
	enemy.apply_poison(dps, total)


## Tira las entradas vencidas para que el diccionario no crezca toda la partida.
func _prune_poison(now: float) -> void:
	if _poison_state.size() < 64:
		return
	for id: int in _poison_state.keys():
		if float(_poison_state[id].until) <= now:
			_poison_state.erase(id)


## Esfera translúcida que se expande y se adelgaza: el "pfff". Se anima la
## transparencia del nodo, no el material compartido de la escena.
func _play_cloud(radius: float) -> void:
	var shell := spawn_fx_mesh(cloud_mesh)
	shell.global_position = global_position + Vector3.DOWN * cloud_drop
	shell.scale = Vector3.ONE * cloud_start_scale
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius, cloud_grow_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "transparency", 1.0, cloud_fade_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(shell.queue_free)
