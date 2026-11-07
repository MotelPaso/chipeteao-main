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

## XP que da la gema antes de multiplicadores; quien la suelta la escala.
@export var xp_value: int = 1

var _default_xp_value: int = 1


func _ready() -> void:
	super()
	_default_xp_value = xp_value


func live_group() -> StringName:
	return LIVE_GROUP


func _reset_extra() -> void:
	xp_value = _default_xp_value


## La XP es de toda la party, pero el multiplicador de XP de quien la
## recoge (Tomo de Sabiduría) y la parte de dificultad de la partida la escalan.
func _on_collected(collector: Node3D) -> void:
	Sfx.play(&"gem_pickup")
	var multiplier := RunState.difficulty_xp_multiplier()
	var stats := PlayerStats.find_in(collector) if collector != null else null
	if stats != null:
		multiplier *= stats.xp_multiplier
	RunState.add_xp(maxi(roundi(float(xp_value) * multiplier), 1))
