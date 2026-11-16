class_name MythosBreath
extends MythosMove
## Aliento de fuego: se planta en el aire y toma aire (el aviso: dos líneas
## de llamas bajas marcan entre dónde y dónde va a barrer, y los bordes de la
## pantalla se oscurecen). Después suelta un chorro de fuego que BARRE la
## arena de una línea a la otra, pasando por donde estaba el raider. Lejos de
## Mythos el chorro barre más rápido de lo que corre un raider: se esquiva
## saltándolo cuando pasa, saliendo de su alcance o metiéndose pegado a
## Mythos, donde no llega. Cada pasada quema una vez a cada raider que
## alcance en el suelo. Con passes mayor que 1 vuelve sobre lo barrido (el
## nodo Scorch de la segunda fase).

enum Step { INHALE, SWEEP, TURN, REST }

@export_group("Aliento")
## Escena del chorro (FireBeam): dibuja el aviso y las llamas.
@export var beam_scene: PackedScene = preload("res://scenes/fx/FireBeam.tscn")
## Segundos que toma aire antes de soltar el chorro, con agresividad 0.
@export var windup: float = 1.5
## Multiplicador de ese aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.75
## Grados que barre el chorro en cada pasada.
@export var sweep_degrees: float = 120.0
## Segundos que tarda cada pasada, con agresividad 0.
@export var sweep_seconds: float = 1.9
## Multiplicador de ese tiempo con agresividad 1.
@export var sweep_at_full_aggression: float = 0.75
## Largo del chorro, en metros.
@export var reach: float = 34.0
## Metros alrededor de Mythos donde el chorro no llega (pegado a él no quema).
@export var inner_radius: float = 4.0
## Ancho del chorro, en metros.
@export var width: float = 2.4
## Daño a cada raider que el chorro alcance en el suelo, una vez por pasada (valor base).
@export var damage: float = 40.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var height_window: float = 1.1
## Pasadas: 1 barre una sola vez; con 2 vuelve sobre lo barrido.
@export var passes: int = 1
## Segundos de pausa entre una pasada y la siguiente.
@export var turn_seconds: float = 0.45
## Segundos quieto después de la última pasada.
@export var recover: float = 0.9
## Metros que baja de su altura de vuelo mientras sopla, para que el chorro le salga del pico a ras de suelo.
@export var stoop: float = 2.2
## Sonido del chorro en cada pasada (fila de Sfx.SOUND_LIBRARY).
@export var breath_sfx: StringName = &"phoenix_breath"

var _step: Step = Step.INHALE
var _timer: float = 0.0
var _total: float = 0.0
## Desde dónde sale el chorro (un punto sobre el suelo) y entre qué ángulos
## barre la pasada de ahora, en radianes.
var _origin: Vector3 = Vector3.ZERO
var _from_angle: float = 0.0
var _to_angle: float = 0.0
var _passes_left: int = 0
## Raiders que esta pasada ya quemó (ids de instancia).
var _burned: Dictionary[int, bool] = {}
var _beam: FireBeam = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	if _beam == null and beam_scene != null:
		_beam = beam_scene.instantiate() as FireBeam
		add_child(_beam)
	_origin = boss.floor_point(boss.global_position)
	var to_target := target.global_position - _origin
	var bearing := atan2(to_target.z, to_target.x)
	# Barre de un lado al otro del raider; de qué lado empieza es al azar.
	var half := deg_to_rad(sweep_degrees) * 0.5 * (1.0 if randf() < 0.5 else -1.0)
	_from_angle = bearing - half
	_to_angle = bearing + half
	_passes_left = maxi(passes, 1)
	_step = Step.INHALE
	_total = windup * aggression_lerp(1.0, windup_at_full_aggression)
	_timer = _total
	boss.rig.set_pose(MythosRig.Pose.WINDUP)
	_face(_from_angle)


func tick(delta: float) -> bool:
	_timer -= delta
	# Baja para soplar y vuelve a su altura mientras descansa.
	boss.rig.lift = lerpf(boss.rig.lift, 0.0 if _step == Step.REST else -stoop,
			Juice.damp(4.0, delta))
	match _step:
		Step.INHALE:
			boss.feel.dread(1.0 - clampf(_timer / maxf(_total, 0.01), 0.0, 1.0))
			if _beam != null:
				_beam.warn(_origin, _from_angle, _to_angle, inner_radius, reach)
			if _timer <= 0.0:
				_begin_sweep()
		Step.SWEEP:
			_tick_sweep()
		Step.TURN:
			boss.feel.dread(0.6)
			if _timer <= 0.0:
				_begin_sweep()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	if _beam != null:
		_beam.snuff()
	boss.rig.lift = 0.0
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(boss.rest_pose())


# --- privados ---------------------------------------------------------------------

func _begin_sweep() -> void:
	_step = Step.SWEEP
	_total = sweep_seconds * aggression_lerp(1.0, sweep_at_full_aggression)
	_timer = _total
	_burned.clear()
	boss.rig.set_pose(MythosRig.Pose.CAST)
	boss.rig.gesture(&"roar")
	boss.feel.shock(MythosFeel.Shock.LIGHT, _origin)
	Sfx.play(breath_sfx)


## Un frame de la pasada: el chorro avanza, quema a quien alcance y Mythos
## gira con él.
func _tick_sweep() -> void:
	var t := 1.0 - clampf(_timer / maxf(_total, 0.01), 0.0, 1.0)
	# Arranca suave y después barre parejo.
	var angle := lerpf(_from_angle, _to_angle, t * t * (3.0 - 2.0 * t))
	_face(angle)
	boss.feel.dread(0.6)
	if _beam != null:
		_beam.blaze(_origin, boss.muzzle_point(), angle, inner_radius, reach, width)
	_burn(angle)
	if _timer > 0.0:
		return
	_passes_left -= 1
	if _passes_left > 0:
		# Vuelve sobre lo barrido: la próxima pasada sale de donde terminó esta.
		var swap := _from_angle
		_from_angle = _to_angle
		_to_angle = swap
		_step = Step.TURN
		_timer = turn_seconds
		return
	if _beam != null:
		_beam.quench()
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(boss.rest_pose())


## Quema, una vez por pasada, a cada raider en pie dentro del chorro.
func _burn(angle: float) -> void:
	var heading := Vector3(cos(angle), 0.0, sin(angle))
	var terrain := Terrain.find(get_tree())
	for raider: Node3D in Coop.alive_players(get_tree()):
		var id := raider.get_instance_id()
		if _burned.has(id):
			continue
		var offset := raider.global_position - _origin
		offset.y = 0.0
		var along := offset.dot(heading)
		if along < inner_radius or along > reach:
			continue
		if (offset - heading * along).length() > width * 0.5:
			continue
		var ground := _origin.y
		if terrain != null:
			ground = terrain.height_at(raider.global_position.x, raider.global_position.z)
		if raider.global_position.y - ground > height_window:
			continue
		_burned[id] = true
		var health := Health.find_in(raider)
		if health != null and not health.is_dead:
			health.take_damage(damage, false, boss)


func _face(angle: float) -> void:
	boss.face_along(Vector3(cos(angle), 0.0, sin(angle)))
