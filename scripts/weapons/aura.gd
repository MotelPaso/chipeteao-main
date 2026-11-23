extends FieldWeapon
## Aura: un anillo de luz fijo alrededor del portador. Un enemigo recibe el
## golpe (daño y frenazo del grupo «Impacto») en cuanto su cuerpo toca el
## borde, y después otra vez cada `cooldown` mientras siga dentro. Cómo usa
## los ajustes de WeaponBase:
##   damage        — daño de cada golpe (por deal_damage)
##   cooldown      — segundos entre dos golpes al MISMO enemigo (y el ritmo del destello)
##   attack_range  — radio del anillo (Largo alcance y los tomos de área lo ensanchan)
## El radio, la altura y el bono del Tomo de Multitud vienen de FieldWeapon.
## La evolución «Halo de ruina» multiplica attack_range y cooldown.
## El visual es el nodo Disc de Aura.tscn (malla y material en la escena): un
## disco translúcido que respira con cada pulso.

@export_group("Disco")
## Cuánto debajo del montaje del arma se dibuja el disco, en metros.
@export var disc_drop: float = 1.0
## Qué tan rápido el disco alcanza el radio real, en fracción cerrada por segundo (suavizado exponencial).
@export var disc_follow_rate: float = 8.0
## Transparencia (0-1) a la que se apaga el disco después de cada destello de pulso.
@export var pulse_fade_to: float = 0.45
## Fracción del intervalo de pulso que tarda el disco en apagarse.
@export var pulse_fade_fraction: float = 0.8

var _pulse_tween: Tween = null
## id de instancia del enemigo -> segundos hasta que puede volver a recibir golpe.
var _rehit: Dictionary[int, float] = {}

@onready var _disc: MeshInstance3D = $Disc


func _physics_process(delta: float) -> void:
	var radius := reach()
	_disc.global_position = global_position + Vector3.DOWN * disc_drop
	# El disco sigue la pendiente del suelo bajo él; la escala la pone el
	# suavizado de abajo.
	GroundAlign.align(_disc, GroundAlign.normal_at(get_tree(), _disc.global_position))
	# Suavizado independiente del framerate: un lerp con delta * tasa cerraría
	# a otra velocidad si cambiara physics_ticks_per_second, y mostraría un
	# anillo chico mientras el daño ya cubre el grande.
	var follow := 1.0 - exp(-disc_follow_rate * delta)
	_disc.scale = _disc.scale.lerp(Vector3(radius, 1.0, radius), follow)
	_touch_enemies(radius, delta)
	super(delta)


## El enfriamiento del arma solo marca el destello del disco: el daño lo
## reparte _touch_enemies, enemigo por enemigo.
func fire(_target: Node3D) -> void:
	# Respiración: el disco destella en cada pulso. Se anima la transparencia
	# del nodo, no el material compartido de la escena.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_disc.transparency = 0.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_disc, "transparency", pulse_fade_to,
			effective_cooldown() * pulse_fade_fraction)


## Golpea al instante a cada enemigo que toca el aura y no tiene su espera
## corriendo; cada golpe le pone una espera de effective_cooldown().
func _touch_enemies(radius: float, delta: float) -> void:
	for id: int in _rehit.keys():
		_rehit[id] -= delta
		if _rehit[id] <= 0.0:
			_rehit.erase(id)
	for body: Node3D in enemies_in_disc(global_position, radius, height_window):
		var id := body.get_instance_id()
		if _rehit.has(id):
			continue
		var health := Health.find_in(body)
		if health == null or health.is_dead:
			continue
		deal_damage(health)
		_rehit[id] = effective_cooldown()
