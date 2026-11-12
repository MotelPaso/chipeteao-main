extends FieldWeapon
## Aura: un anillo de luz fijo alrededor del portador que daña a todo enemigo
## dentro en cada pulso. Cómo usa los ajustes de WeaponBase:
##   damage        — daño por pulso (por deal_damage)
##   cooldown      — intervalo entre pulsos
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

@onready var _disc: MeshInstance3D = $Disc


func _physics_process(delta: float) -> void:
	var radius := reach()
	_disc.global_position = global_position + Vector3.DOWN * disc_drop
	# Suavizado independiente del framerate: un lerp con delta * tasa cerraría
	# a otra velocidad si cambiara physics_ticks_per_second, y mostraría un
	# anillo chico mientras el daño ya cubre el grande.
	var follow := 1.0 - exp(-disc_follow_rate * delta)
	_disc.scale = _disc.scale.lerp(Vector3(radius, 1.0, radius), follow)
	super(delta)


func fire(_target: Node3D) -> void:
	damage_all(enemies_in_disc(global_position, reach(), height_window))
	# Respiración: el disco destella en cada pulso. Se anima la transparencia
	# del nodo, no el material compartido de la escena.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_disc.transparency = 0.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_disc, "transparency", pulse_fade_to,
			effective_cooldown() * pulse_fade_fraction)
