class_name FieldWeapon
extends WeaponBase
## Base de las armas de campo centradas en el portador (Aura, Hedor): el área
## de daño es un círculo de radio reach() que también decide cuándo pulsar.
## El Tomo de Multitud no suma campos: uno extra centrado en el mismo portador
## sería el mismo círculo dibujado dos veces (invisible) y duplicaría cada
## pulso. Cada punto extra agranda el radio y acorta el intervalo de pulso.

@export_group("Campo")
## Altura máxima, en metros, por encima o por debajo del portador a la que alcanza el pulso.
@export var height_window: float = 2.2

@export_group("Multitud")
## Radio extra por punto del Tomo de Multitud, como fracción del radio base (0.12 = +12%).
@export var radius_per_extra: float = 0.12
## Fracción del intervalo de pulso que quita cada punto del Tomo de Multitud (0.08 = -8%).
@export var pulse_per_extra: float = 0.08
## Piso de la escala de pulso acumulada (0-1): el campo sigue siendo un pulso y no un daño por frame.
@export var min_pulse_scale: float = 0.6


## Radio del campo: el área de daño, el visual y el disparo del pulso leen
## este único número, y por aquí llega el bono del Tomo de Multitud.
func reach() -> float:
	return attack_range * area_scale() \
			* (1.0 + radius_per_extra * float(_multitude_extra()))


## Con el tomo también suben los pulsos por segundo; el piso evita que una
## pila grande convierta el intervalo en un tick.
func effective_cooldown() -> float:
	var pulse_scale := maxf(1.0 - pulse_per_extra * float(_multitude_extra()),
			min_pulse_scale)
	return maxf(super() * pulse_scale, MIN_COOLDOWN)


## El campo ES el área de daño, así que el pulso debe dispararse con cualquier
## enemigo dentro, también en la franja que agrega area_scale().
func targeting_range() -> float:
	return reach()


## Disparos después del primero que el arma habría hecho, o sea lo que dio el
## Tomo de Multitud (los ascensos también suben projectile_count).
func _multitude_extra() -> int:
	return maxi(effective_projectile_count() - 1, 0)
