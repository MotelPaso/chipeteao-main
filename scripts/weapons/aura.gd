extends WeaponBase
## Aura: un anillo de luz fijo alrededor del portador que daña a todo enemigo
## dentro en cada pulso. Cómo usa los ajustes de WeaponBase:
##   damage        — daño por pulso (por deal_damage)
##   cooldown      — intervalo entre pulsos
##   attack_range  — radio del anillo (Largo alcance y los tomos de área lo ensanchan)
## El visual es un disco translúcido que respira con cada pulso.

@export var aura_color: Color = Color(1.0, 0.85, 0.4)
## Altura máxima, en metros, por encima o por debajo del portador a la que el pulso alcanza.
@export var height_window: float = 2.2

## Qué tan rápido el disco dibujado alcanza el radio real, como "fracción
## cerrada por segundo"; se usa en forma exponencial para que el suavizado sea
## igual a cualquier tasa de física.
const DISC_FOLLOW_RATE: float = 8.0

## Radio extra del anillo por punto del Tomo de Multitud, como fracción del
## radio base. El tomo no puede sumar ANILLOS: un segundo anillo centrado en
## el mismo portador es el mismo círculo dibujado dos veces (invisible) y
## duplicaría cada pulso. El conteo extra ensancha el único anillo.
const AURA_RADIUS_PER_EXTRA: float = 0.12
## Fracción del intervalo de pulso que quita cada punto extra: con el tomo
## apilado el anillo también late más rápido.
const AURA_PULSE_PER_EXTRA: float = 0.08
## Piso de la escala de pulso acumulada: el aura sigue siendo un pulso y no
## un campo de daño por frame.
const AURA_MIN_PULSE_SCALE: float = 0.6

var _disc: MeshInstance3D = null
var _pulse_tween: Tween = null


func _ready() -> void:
	_disc = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.05
	# Teselado explícito: una losa de 5 cm no necesita anillos de altura, y 32
	# lados mantienen redondo el anillo con el área al máximo.
	mesh.radial_segments = 32
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(aura_color, 0.22)
	material.emission_enabled = true
	material.emission = aura_color
	material.emission_energy_multiplier = 0.9
	mesh.material = material
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _physics_process(delta: float) -> void:
	var radius := reach()
	_disc.global_position = global_position + Vector3.DOWN * 1.0
	# Suavizado independiente del framerate: un lerp con delta * tasa cerraría
	# a otra velocidad si cambiara physics_ticks_per_second, y mostraría un
	# anillo chico mientras el daño ya cubre el grande.
	var follow := 1.0 - exp(-DISC_FOLLOW_RATE * delta)
	_disc.scale = _disc.scale.lerp(Vector3(radius, 1.0, radius), follow)
	super(delta)


## Radio del anillo: el área de daño, el disco dibujado y el disparo del pulso
## leen este único número, y por aquí llega el bono del Tomo de Multitud.
func reach() -> float:
	return attack_range * area_scale() \
			* (1.0 + AURA_RADIUS_PER_EXTRA * float(_multitude_extra()))


## Con el tomo también suben los pulsos por segundo (AURA_PULSE_PER_EXTRA); el
## piso evita que una pila grande convierta el intervalo en un tick.
func effective_cooldown() -> float:
	var pulse_scale := maxf(1.0 - AURA_PULSE_PER_EXTRA * float(_multitude_extra()),
			AURA_MIN_PULSE_SCALE)
	return maxf(super() * pulse_scale, MIN_COOLDOWN)


## Disparos después del primero que el arma habría hecho, o sea lo que dio el
## Tomo de Multitud (los ascensos también suben projectile_count).
func _multitude_extra() -> int:
	return maxi(effective_projectile_count() - 1, 0)


## El anillo ES el área de daño, así que el pulso debe dispararse con
## cualquier enemigo dentro, también en la franja que agrega area_scale().
func targeting_range() -> float:
	return reach()


func fire(_target: Node3D) -> void:
	damage_all(enemies_in_disc(global_position, reach(), height_window))
	# Respiración: el disco destella un poco en cada pulso.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_disc.transparency = 0.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_disc, "transparency", 0.45, effective_cooldown() * 0.8)
