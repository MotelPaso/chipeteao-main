class_name LobsterTailSpin
extends LobsterMove
## Coletazo: enrosca la cola hacia un lado (el aviso) y un disco centrado en
## su lomo marca hasta dónde llega. El disco va CON la langosta, que mientras
## avisa se le viene encima al raider; cuando termina, gira sobre sí misma y
## la cola barre todo el disco a ras de suelo. Se esquiva alejándose (ella
## avanza más lento que un raider) o SALTANDO el barrido. Con agresividad da
## un segundo giro, para el otro lado.

enum Step { COIL, SPIN, REST }

@export_group("Coletazo")
## Giros seguidos con agresividad 0.
@export var spins: int = 1
## Giros extra con agresividad 1.
@export var extra_spins_at_full_aggression: int = 1
## Segundos de aviso antes del primer giro, con agresividad 0.
@export var windup: float = 1.0
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.8
## Segundos de aviso antes de cada giro después del primero.
@export var respin_windup: float = 0.55
## Fracción de su velocidad con que se acerca al raider mientras avisa (0-1).
@export_range(0.0, 1.0) var advance_factor: float = 0.6
## Metros a los que deja de acercarse (ya lo tiene dentro del disco).
@export var close_enough: float = 2.6
## Radio del barrido y de su disco de aviso, en metros.
@export var radius: float = 5.0
## Segundos que tarda en dar la vuelta.
@export var spin_seconds: float = 0.42
## Fracción del giro (0-1) en la que la cola golpea.
@export_range(0.0, 1.0) var hit_fraction: float = 0.45
## Daño del barrido a cada raider dentro del disco (valor base).
@export var damage: float = 8.0
## Metros sobre el suelo por encima de los cuales la cola no alcanza (se esquiva saltando).
@export var height_window: float = 1.0
## Segundos quieta después del último giro: una ventana para pegarle.
@export var recover: float = 0.95
## Sonido de cada giro (fila de Sfx.SOUND_LIBRARY).
@export var spin_sfx: StringName = &"lobster_whoosh"
## Escena del anillo que dibuja el barrido (ShockRing sin daño, sale de Pools). Vacío = sin anillo.
@export var sweep_scene: PackedScene = preload("res://scenes/fx/ShockRing.tscn")

var _step: Step = Step.COIL
var _timer: float = 0.0
var _spins_left: int = 0
var _target: Node3D = null
var _struck: bool = false
## El disco que va con la langosta mientras avisa.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_spins_left = maxi(aggression_count(spins, extra_spins_at_full_aggression), 1)
	_coil(windup * aggression_lerp(1.0, windup_at_full_aggression))


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.COIL:
			_tick_coil()
		Step.SPIN:
			_tick_spin()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	release_disc(_disc)
	_disc = null
	boss.rig.spin = 0.0
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

## Enrosca la cola para el otro lado y el disco aparece a su alrededor.
func _coil(seconds: float) -> void:
	_step = Step.COIL
	_timer = seconds
	boss.rig.side = -boss.rig.side
	boss.rig.set_pose(LobsterRig.Pose.COIL)
	boss.rig.set_anger(0.7)
	_disc = Telegraph.spawn_moving_disc(boss.core_point(), radius, seconds,
			boss.telegraph_color)


func _tick_coil() -> void:
	if has_target(_target):
		var to_target := _target.global_position - boss.global_position
		to_target.y = 0.0
		if to_target.length() > close_enough:
			boss.walk(to_target.normalized() * advance_factor)
	# El disco sigue a la langosta hasta el final del aviso; después vuelve
	# solo al pool y ya no se lo toca.
	if _timer > 0.03 and _disc != null:
		_disc.move_to(boss.core_point())
	if _timer <= 0.0:
		_disc = null
		_step = Step.SPIN
		_timer = spin_seconds
		_struck = false
		boss.rig.set_pose(LobsterRig.Pose.SWEEP)
		Sfx.play(spin_sfx)
		if sweep_scene != null:
			ShockRing.spawn(sweep_scene, boss.core_point(), 1.0, radius,
					radius / maxf(spin_seconds * hit_fraction, 0.05), 0.0, 0.0, 0.0, boss)


func _tick_spin() -> void:
	var t := 1.0 - clampf(_timer / maxf(spin_seconds, 0.01), 0.0, 1.0)
	boss.rig.spin = 360.0 * smoothstep(0.0, 1.0, t) * boss.rig.side
	if not _struck and t >= hit_fraction:
		_struck = true
		var at := boss.core_point()
		var hit := boss.strike_ground([at], radius, height_window, damage)
		boss.feel.shock(
				LobsterFeel.Shock.HEAVY if not hit.is_empty() else LobsterFeel.Shock.LIGHT, at)
	if _timer > 0.0:
		return
	boss.rig.spin = 0.0
	_spins_left -= 1
	if _spins_left > 0:
		_coil(respin_windup)
		return
	_step = Step.REST
	_timer = recover
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
