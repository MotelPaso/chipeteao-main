extends FieldWeapon
## Hedor: pulsos flatulentos. En cada enfriamiento estalla una nube de gas
## desde el portador que daña, envenena y ralentiza todo lo que hay en su
## radio. Cómo usa los ajustes de WeaponBase:
##   damage        — golpe del estallido (por deal_damage); el veneno por segundo sale de él
##   cooldown      — segundos entre pulsos
##   attack_range  — radio de la nube (los tomos de área lo escalan)
## Veneno y ralentización duran más con el stat de duración. El radio, la
## altura y el bono del Tomo de Multitud vienen de FieldWeapon.
## La evolución «Miasma» multiplica poison_duration y attack_range.

@export_group("Veneno y ralentización")
## Veneno por segundo como fracción del daño efectivo del pulso (0-1).
@export var poison_damage_fraction: float = 0.4
## Segundos de veneno por pulso; la carta «Hedor más rancio» y la evolución «Miasma» lo alargan.
@export var poison_duration: float = 3.0
## Multiplicador de velocidad de los enemigos ralentizados (0.6 = conservan el 60%).
@export var slow_multiplier: float = 0.6
## Segundos de ralentización por pulso.
@export var slow_duration: float = 2.0

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


func fire(_target: Node3D) -> void:
	var radius := reach()
	var poison_dps := effective_damage() * poison_damage_fraction
	for body: Node3D in enemies_in_disc(global_position, radius, height_window):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		# Los cadáveres no reciben estados: apply_poison ya rechaza a los
		# muertos, y una ralentización sobre un cuerpo que este pulso mató solo
		# deja estado para quien lo lea después.
		if enemy != null and (health == null or not health.is_dead):
			enemy.apply_poison(poison_dps, poison_duration * duration_scale())
			enemy.apply_slow(slow_multiplier, slow_duration * duration_scale())
	_play_cloud(radius)


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
