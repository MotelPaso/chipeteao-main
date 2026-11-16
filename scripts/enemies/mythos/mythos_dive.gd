class_name MythosDive
extends MythosMove
## Picada: se remonta sobre el raider y el disco de aviso LO PERSIGUE mientras
## sube. Poco antes del golpe el disco se clava (un segundo aviso lo marca,
## con un chillido) y Mythos cae sobre ese punto como un cometa: golpea el
## suelo, levanta una columna de fuego y manda una onda de llamas que hay que
## saltar. Seguir corriendo derecho no alcanza: hay que cambiar de rumbo en
## cuanto el disco se clava. Después queda POSADO en tierra (Mythos.land), a
## tiro de las armas cortas, y pelea desde ahí con sus Garras hasta que
## despega con un Aletazo. Con chain es la Picada en cadena (el nodo
## DiveChain de la segunda fase): rebota, vuelve a remontarse y cae varias
## veces antes de quedarse posado.

enum Step { TRACK, LOCKED, PERCHED }

@export_group("Picada")
## Segundos de aviso entre que aparece el disco y el golpe, con agresividad 0.
@export var windup: float = 1.3
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.75
## Segundos antes del golpe en los que el disco deja de perseguir al raider: la ventana para salir.
@export var lock_seconds: float = 0.55
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 5.0
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 50.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para ubicar el disco.
@export var lead_seconds: float = 0.35
## Tope de ese adelanto, en metros, para un raider a velocidad base (crece si corre más rápido).
@export var max_lead: float = 4.0
## Segundos finales del aviso en los que cae hasta la marca.
@export var dash_time: float = 0.3
## Segundos posado y quieto justo después del golpe (la ventana más segura para pegarle), con agresividad 0.
@export var recover: float = 2.4
## Multiplicador de ese descanso con agresividad 1.
@export var recover_at_full_aggression: float = 0.7
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"phoenix_screech"
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"fireball_blast"
## Picadas seguidas antes de quedarse posado (1 = una sola).
@export var chain: int = 1
## Segundos de aviso de cada picada después de la primera.
@export var chain_windup: float = 0.95

@export_group("Remontada")
## Metros que sube sobre su altura de vuelo antes de caer.
@export var climb_height: float = 9.0
## Rapidez con que sube (por segundo).
@export var climb_speed: float = 5.0
## Metros que se queda detrás de la marca mientras la persigue desde arriba: de ahí cae en diagonal.
@export var stoop_distance: float = 7.0
## Rapidez con que el cuerpo sigue a la marca desde arriba (por segundo).
@export var follow_speed: float = 4.5

@export_group("Columna de fuego")
## Escena de la columna que levanta el golpe (FireBurst, sale de Pools). Vacío = sin columna.
@export var burst_scene: PackedScene = preload("res://scenes/fx/FireBurst.tscn")
## Alto de la columna, en metros.
@export var burst_height: float = 13.0
## Radio de la columna, en veces el radio del golpe.
@export var burst_radius_factor: float = 0.55

@export_group("Onda de fuego")
## Escena de la onda que sale del golpe (FireWave, sale de Pools). Vacío = sin onda.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Radio en metros hasta el que llega la onda.
@export var wave_radius: float = 20.0
## Metros por segundo a los que se abre.
@export var wave_speed: float = 14.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var wave_damage: float = 28.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var wave_height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var wave_band: float = 1.4

var _step: Step = Step.TRACK
var _timer: float = 0.0
## De dónde partió, dónde va a caer y desde dónde empezó la caída.
var _from: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO
var _fall_from: Vector3 = Vector3.ZERO
var _fall_lift: float = 0.0
var _target: Node3D = null
var _dives_left: int = 0
## El disco que persigue al raider; se suelta en cuanto se clava.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	wave_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_dives_left = maxi(chain, 1)
	_aim(windup * aggression_lerp(1.0, windup_at_full_aggression))


func tick(delta: float) -> bool:
	_timer -= delta
	if _step == Step.PERCHED:
		return _timer <= 0.0
	if _step == Step.TRACK:
		if _timer > lock_seconds:
			_mark = _aim_point()
			if _disc != null:
				_disc.move_to(_mark)
		else:
			_lock()
	if _step == Step.LOCKED:
		boss.feel.dread(1.0)
	if _timer > dash_time:
		_hover(delta)
	else:
		# El último tramo del aviso es la caída: llega a la marca justo cuando
		# el disco termina de llenarse.
		boss.rig.set_pose(MythosRig.Pose.DIVE)
		var t := 1.0 - clampf(_timer / maxf(dash_time, 0.01), 0.0, 1.0)
		boss.glide_to(_fall_from.lerp(_mark, t * t))
		boss.rig.lift = _fall_lift * (1.0 - t * t)
	if _timer <= 0.0:
		_impact()
	return false


func cancel() -> void:
	_disc = null
	boss.rig.lift = 0.0
	boss.rig.set_trail(false)
	boss.rig.set_pose(boss.rest_pose())


# --- privados ---------------------------------------------------------------------

## Empieza una picada: se remonta y el disco persigue al raider `seconds`.
func _aim(seconds: float) -> void:
	_step = Step.TRACK
	_timer = maxf(seconds, lock_seconds + 0.05)
	_from = boss.global_position
	_mark = _from
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, radius, _timer, boss.telegraph_color)
	boss.rig.set_pose(MythosRig.Pose.WINDUP)
	boss.rig.set_trail(true)


## Adónde va el raider, llevado a un lugar donde Mythos cabe. Sin raider a
## quien seguir, la marca se queda donde estaba.
func _aim_point() -> Vector3:
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		return _mark
	return boss.safe_point(MythosBolts.predicted(_target, lead_seconds, max_lead))


## El disco se clava: ya no persigue, y un segundo aviso marca dónde cae.
func _lock() -> void:
	_step = Step.LOCKED
	_disc = null
	Telegraph.spawn_disc(boss, _mark, radius, _timer, boss.impact_color)
	boss.rig.gesture(&"screech")
	Sfx.play(lock_sfx)


## Mientras avisa vuela alto, un poco detrás de la marca, mirándola.
func _hover(delta: float) -> void:
	var back := _from - _mark
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.01 else Vector3.BACK
	var above := _mark + back * stoop_distance
	boss.glide_to(boss.global_position.lerp(above, Juice.damp(follow_speed, delta)))
	boss.rig.lift = lerpf(boss.rig.lift, climb_height, Juice.damp(climb_speed, delta))
	boss.face_along(_mark - boss.global_position)
	_fall_from = boss.global_position
	_fall_lift = boss.rig.lift


func _impact() -> void:
	boss.glide_to(_mark)
	boss.rig.lift = 0.0
	boss.strike_ground([_mark], radius, height_window, damage)
	# La onda nace en el borde del golpe: quien salió del disco todavía tiene
	# que saltarla.
	if wave_scene != null:
		FireWave.spawn(wave_scene, _mark, radius, wave_radius, wave_speed, wave_damage,
				wave_height_window, wave_band, boss)
	FireBurst.spawn(burst_scene, _mark, radius * burst_radius_factor, burst_height)
	boss.feel.shock(MythosFeel.Shock.HEAVY, _mark)
	boss.rig.burst()
	Sfx.play(impact_sfx)
	_dives_left -= 1
	if _dives_left > 0:
		# Rebota: vuelve a remontarse y persigue de nuevo.
		_aim(chain_windup)
		return
	boss.rig.set_trail(false)
	boss.face_along(Vector3.ZERO)
	boss.land()
	# Recién posado se sacude las plumas.
	boss.rig.gesture(&"shake")
	_step = Step.PERCHED
	_timer = recover * aggression_lerp(1.0, recover_at_full_aggression)
