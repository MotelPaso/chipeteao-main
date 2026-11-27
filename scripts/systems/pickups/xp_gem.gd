class_name XpGem
extends MagnetPickup
## Gema de XP que sueltan los enemigos: el chasis compartido MagnetPickup
## más lo único propio de la gema — recogerla acredita RunState.add_xp
## escalado por el multiplicador de XP de QUIEN la recoge.
## pool_reset también restaura xp_value, que quien suelta escala por gema
## sobre el valor de la escena.

## Grupo de toda gema viva (soltada y sin recoger); la aspiradora llega a
## las gemas por él. Distinto del grupo permanente "xp_gems" de la escena,
## que cuenta la sonda de rendimiento.
const LIVE_GROUP: StringName = &"gems"

@export_group("Experiencia")
## XP que da la gema antes de multiplicadores; quien la suelta la escala.
@export var xp_value: int = 1
@export_group("Tamaño")
## Escala del cristal con 1 XP, el tamaño de siempre.
@export var base_size_scale: float = 1.0
## XP a partir de la cual el cristal alcanza `full_size_scale`.
@export var full_size_value: int = 10
## Escala del cristal al llegar a `full_size_value` XP.
@export var full_size_scale: float = 1.6
@export_group("")

var _default_xp_value: int = 1


func _ready() -> void:
	super()
	_default_xp_value = xp_value


func live_group() -> StringName:
	return LIVE_GROUP


func _reset_extra() -> void:
	xp_value = _default_xp_value
	_apply_size()


## Junta `other` en esta gema: suma la XP, se queda con la edad más joven y
## devuelve la otra al pool sin recogerla. False si alguna ya no está en suelo.
func merge_from(other: XpGem) -> bool:
	if other == null or other == self or not is_instance_valid(other):
		return false
	if not can_merge() or not other.can_merge():
		return false
	var own_weight := float(maxi(xp_value, 1))
	var other_weight := float(maxi(other.xp_value, 1))
	global_position = (global_position * own_weight + other.global_position * other_weight) / (own_weight + other_weight)
	xp_value += other.xp_value
	keep_age_at_most(other.age_seconds())
	_apply_size()
	other.release_for_merge()
	return true


## La XP es de toda la party, pero el multiplicador de XP de quien la
## recoge (Tomo de Sabiduría) y la parte de dificultad de la partida la escalan.
func _on_collected(collector: Node3D) -> void:
	Sfx.play(&"gem_pickup")
	var multiplier := RunState.difficulty_xp_multiplier()
	var stats := PlayerStats.find_in(collector) if collector != null else null
	if stats != null:
		multiplier *= stats.xp_multiplier
	RunState.add_xp(maxi(roundi(float(xp_value) * multiplier), 1))


func _apply_size() -> void:
	var span := float(maxi(full_size_value, 1))
	var t := clampf(float(maxi(xp_value, 1)) / span, 0.0, 1.0)
	_visual.scale = Vector3.ONE * lerpf(base_size_scale, full_size_scale, t)
