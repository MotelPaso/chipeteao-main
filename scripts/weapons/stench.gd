extends WeaponBase
## Hedor: pulsos flatulentos. En cada enfriamiento estalla una nube de gas
## desde el portador que daña, envenena y ralentiza todo lo que hay en su
## radio. Cómo usa los ajustes de WeaponBase:
##   damage        — golpe del estallido (por deal_damage); el veneno por segundo sale de él
##   cooldown      — segundos entre pulsos
##   attack_range  — radio de la nube (los tomos de área lo escalan)
## Veneno y ralentización duran más con el stat de duración.

@export var poison_damage_fraction: float = 0.4
@export var poison_duration: float = 3.0
@export var slow_multiplier: float = 0.6
@export var slow_duration: float = 2.0
@export var gas_color: Color = Color(0.55, 0.8, 0.25)
@export var height_window: float = 2.2

## Radio extra de la nube por punto del Tomo de Multitud, como fracción del
## radio base. El tomo no puede sumar NUBES: una segunda centrada en el mismo
## portador es la misma esfera dibujada dos veces (invisible) y duplicaría
## daño, veneno y ralentización de cada pulso. El conteo extra agranda la única nube.
const STENCH_RADIUS_PER_EXTRA: float = 0.12
## Fracción del intervalo de pulso que quita cada punto extra: con el tomo
## apilado el gas también sale más seguido.
const STENCH_PULSE_PER_EXTRA: float = 0.08
## Piso de la escala de pulso acumulada: veneno y ralentización se refrescan,
## así que un intervalo colapsado sería un campo permanente.
const STENCH_MIN_PULSE_SCALE: float = 0.6

var _shell_mesh: SphereMesh = null


func _ready() -> void:
	_shell_mesh = SphereMesh.new()
	_shell_mesh.radius = 1.0
	_shell_mesh.height = 2.0
	# Teselado explícito: una cáscara alfa de doble cara puede llenar la
	# pantalla alrededor del portador, y con el teselado por defecto del motor
	# (64 x 32) cada pulso dibujaría miles de triángulos transparentes.
	_shell_mesh.radial_segments = 24
	_shell_mesh.rings = 12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(gas_color, 0.35)
	material.emission_enabled = true
	material.emission = gas_color
	material.emission_energy_multiplier = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell_mesh.material = material


## Radio de la nube: el área de daño, la cáscara dibujada y el disparo del
## pulso leen este único número, y por aquí llega el bono del Tomo de Multitud.
func reach() -> float:
	return attack_range * area_scale() \
			* (1.0 + STENCH_RADIUS_PER_EXTRA * float(_multitude_extra()))


## Con el tomo también suben los pulsos por segundo (STENCH_PULSE_PER_EXTRA);
## el piso evita que una pila grande convierta el intervalo en un tick.
func effective_cooldown() -> float:
	var pulse_scale := maxf(1.0 - STENCH_PULSE_PER_EXTRA * float(_multitude_extra()),
			STENCH_MIN_PULSE_SCALE)
	return maxf(super() * pulse_scale, MIN_COOLDOWN)


## Disparos después del primero que el arma habría hecho, o sea lo que dio el
## Tomo de Multitud (los ascensos también suben projectile_count).
func _multitude_extra() -> int:
	return maxi(effective_projectile_count() - 1, 0)


## La nube ES el área de daño, así que el pulso debe dispararse con
## cualquier enemigo dentro, también en la franja que agrega area_scale().
func targeting_range() -> float:
	return reach()


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


## Esfera translúcida que se expande y se adelgaza: el "pfff".
func _play_cloud(radius: float) -> void:
	var shell := spawn_fx_mesh(_shell_mesh)
	shell.global_position = global_position + Vector3.DOWN * 0.3
	shell.scale = Vector3.ONE * 0.3
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "transparency", 1.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(shell.queue_free)
