class_name MythosEntrance
extends Node3D
## La entrada de Mythos (nodo Entrance de MythosCinematic.tscn): lo que el
## fénix HACE durante la calma. La cinemática le pasa en cada frame cuánto
## avanzó la calma (advance) y este nodo mueve el modelo (MythosRig.fly_at)
## y dispara cada momento a su tiempo:
##   COMETA   cae del cielo en picada y queda rasante, con su estela
##   ANILLO   da una vuelta alrededor de la party y deja un anillo de fuego
##   ASCENSO  sube en espiral y abre las alas en lo alto, con un fogonazo
##   PICADA   cae a plomo y golpea el suelo: ondas de fuego y escombros
##   COLUMNA  una columna de fuego lo tapa; sale de ella abriendo las alas
##   GRITO    grita de frente a la cámara
## Con la canción de la primera fase puesta, los momentos fuertes caen sobre
## sus golpes (uno cada 2 s desde el segundo 1,24 de una calma de 15,24 s).
## El recorrido lo calcula MythosEntrancePath y el anillo lo dibuja el nodo
## Ring (MythosFireRing). Nada de aquí hace daño ni toca a nadie: la onda del
## golpe solo saca de la vista a la horda congelada (MythosHordeVeil), que
## vuelve al terminar la calma.
## Los tiempos son fracciones de la calma (0-1) y van en el orden de arriba.

## Pide un temblor de cámara: `strength` en metros de pantalla, durante `seconds`.
signal shake_requested(strength: float, seconds: float)
## Pide un destello a pantalla completa de opacidad `alpha` (0-1).
signal flash_requested(alpha: float)


## Un momento de la entrada: en qué fracción de la calma pasa y qué hace.
class Beat:
	extends RefCounted
	var at: float = 0.0
	var run: Callable = Callable()


@export_group("Cometa")
## Fracción de la calma (0-1) en que termina de bajar y entra al anillo.
@export_range(0.0, 1.0) var comet_until: float = 0.2126
## Metros que recorre, a ras de suelo, desde donde aparece hasta el anillo.
@export var comet_distance: float = 210.0
## Altura en metros a la que aparece.
@export var comet_height: float = 100.0
## Curva de la bajada (1 = pareja; más alto = cae rápido al principio y después va rasante).
@export var comet_drop_curve: float = 2.2
## Altura del vuelo rasante, en metros sobre el punto de llegada (por encima de árboles y rocas).
@export var low_height: float = 12.0
## Fracción de la calma (0-1) en que sale de la picada y abre las alas.
@export_range(0.0, 1.0) var level_fraction: float = 0.11
## Grito lejano con que empieza (fila de Sfx.SOUND_LIBRARY).
@export var omen_sfx: StringName = &"phoenix_call"
## Sonido al abrir las alas (fila de Sfx.SOUND_LIBRARY).
@export var level_sfx: StringName = &"phoenix_dive"
## Metros detrás del fénix desde los que sale su estela.
@export var trail_back: float = 4.5

@export_group("Anillo de fuego")
## Fracción de la calma (0-1) en que termina la vuelta.
@export_range(0.0, 1.0) var ring_until: float = 0.4751
## Radio del anillo, en metros.
@export var ring_radius: float = 34.0
## Metros mínimos entre el anillo y la party: si la party está lejos, el anillo se agranda.
@export var ring_party_margin: float = 9.0
## Vueltas que da.
@export var ring_laps: float = 1.0
## Grados que se ladea por cada radián por segundo que gira.
@export var bank_per_turn_rate: float = 22.0
## Tope de ese ladeo, en grados.
@export var bank_max_degrees: float = 60.0
## Graznido al empezar la vuelta (fila de Sfx.SOUND_LIBRARY).
@export var ring_sfx: StringName = &"phoenix_caw"

@export_group("Ascenso y picada")
## Fracción de la calma (0-1) en que llega a lo alto y abre las alas.
@export_range(0.0, 1.0) var apex_fraction: float = 0.6063
## Altura en metros a la que llega.
@export var apex_height: float = 58.0
## Vueltas que da mientras sube.
@export var climb_turns: float = 0.75
## Parte del ascenso (0-1) desde la que se va enderezando hacia la cámara.
@export_range(0.0, 1.0) var settle_from: float = 0.6
## Inclinación con que queda en lo alto, en grados (casi vertical, alas abiertas).
@export var apex_pitch_degrees: float = 70.0
## Radio del fogonazo de lo alto, en unidades del modelo.
@export var apex_flash_radius: float = 9.0
## Segundos que dura ese fogonazo.
@export var apex_flash_seconds: float = 0.5
## Temblor de cámara de ese momento, en metros de pantalla.
@export var apex_shake: float = 0.2
## Aletazo al empezar a subir (fila de Sfx.SOUND_LIBRARY).
@export var climb_sfx: StringName = &"phoenix_flap"
## Grito de lo alto (fila de Sfx.SOUND_LIBRARY).
@export var apex_sfx: StringName = &"phoenix_ascend"
## Fracción de la calma (0-1) en que se deja caer.
@export_range(0.0, 1.0) var plunge_fraction: float = 0.69
## Inclinación en la caída, en grados (negativo = pico abajo).
@export var plunge_pitch_degrees: float = -85.0
## Parte de la caída (0-1) que tarda en clavarse de pico.
@export_range(0.05, 1.0) var tip_over: float = 0.35
## Silbido de la caída (fila de Sfx.SOUND_LIBRARY).
@export var plunge_sfx: StringName = &"phoenix_dive"

@export_group("Impacto")
## Fracción de la calma (0-1) en que golpea el suelo. Desde ahí el bosque empieza a arder.
@export_range(0.0, 1.0) var impact_fraction: float = 0.7375
## Radio del fogonazo del golpe, en unidades del modelo.
@export var impact_flash_radius: float = 14.0
## Segundos que dura ese fogonazo.
@export var impact_flash_seconds: float = 0.9
## Opacidad del destello a pantalla completa del golpe (0-1).
@export_range(0.0, 1.0) var impact_flash_alpha: float = 0.55
## Temblor de cámara del golpe, en metros de pantalla.
@export var impact_shake: float = 0.8
## Segundos que dura ese temblor.
@export var impact_shake_seconds: float = 1.2
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"fireball_blast"
## Escena de las ondas de fuego que salen del golpe (FireWave). Vacío = sin ondas.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Ondas que salen, una tras otra (la cámara corta al plano héroe cuando la última ya le pasó).
@export var waves: int = 1
## Segundos entre una onda y la siguiente.
@export var wave_interval: float = 0.18
## Radio en metros con que nace cada onda.
@export var wave_start_radius: float = 3.0
## Radio en metros hasta el que llega.
@export var wave_radius: float = 70.0
## Metros por segundo a los que se abre.
@export var wave_speed: float = 40.0

@export_group("Columna de fuego")
## Escena de la columna que sube del golpe (un FireTornado que no daña). Vacío = sin columna.
@export var pillar_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Radio de la columna, en metros.
@export var pillar_radius: float = 3.6
## Segundos que tarda en formarse.
@export var pillar_form_seconds: float = 0.25
## Fracción de la calma (0-1) en que se yergue dentro de la columna.
@export_range(0.0, 1.0) var rear_fraction: float = 0.78
## Fracción de la calma (0-1) en que despega dentro de la columna.
@export_range(0.0, 1.0) var rise_fraction: float = 0.82
## Fracción de la calma (0-1) en que abre las alas y la columna se deshace.
@export_range(0.0, 1.0) var reveal_fraction: float = 0.8688
## Radio del fogonazo al abrir las alas, en unidades del modelo.
@export var reveal_flash_radius: float = 10.0
## Segundos que dura ese fogonazo.
@export var reveal_flash_seconds: float = 0.6
## Temblor de cámara de ese momento, en metros de pantalla.
@export var reveal_shake: float = 0.3
## Aletazo al abrir las alas (fila de Sfx.SOUND_LIBRARY).
@export var reveal_sfx: StringName = &"phoenix_flap"

@export_group("Grito")
## Fracción de la calma (0-1) en que grita de frente a la cámara.
@export_range(0.0, 1.0) var roar_fraction: float = 0.892
## Su grito (fila de Sfx.SOUND_LIBRARY).
@export var roar_sfx: StringName = &"phoenix_screech"
## Temblor de cámara del grito, en metros de pantalla.
@export var roar_shake: float = 0.3

var _boss: Mythos = null
var _path: MythosEntrancePath = MythosEntrancePath.new()
var _center: Vector3 = Vector3.ZERO
var _seconds: float = 8.0
var _live: bool = false
## True desde que golpea el suelo: ahí deja el recorrido y vuelve a sus poses.
var _grounded: bool = false
var _bird: Vector3 = Vector3.ZERO
var _beats: Array[Beat] = []
var _next_beat: int = 0
var _veil: MythosHordeVeil = MythosHordeVeil.new()

@onready var _ring: MythosFireRing = $Ring
@onready var _trail: CPUParticles3D = $CometTrail
@onready var _debris: CPUParticles3D = $Debris


# --- lo que pide la cinemática ----------------------------------------------------

## Radio del anillo para una party que está a `party_distance` metros del
## punto de llegada: nunca le pasa por encima.
func ring_radius_for(party_distance: float) -> float:
	return maxf(ring_radius, party_distance + ring_party_margin)


## Empieza la entrada: Mythos aterriza en `center`, la cámara lo filma desde
## el lado `toward`, el anillo tiene `radius` metros y la calma dura
## `calm_seconds`.
func begin(boss: Mythos, center: Vector3, toward: Vector3, radius: float,
		calm_seconds: float) -> void:
	_boss = boss
	_center = center
	_seconds = maxf(calm_seconds, 0.01)
	_live = true
	_grounded = false
	var rig := boss.rig
	_path.setup(self, center, toward, radius, _seconds, rig.perch_height * rig.body_scale)
	_ring.lay(center, radius, toward)
	_plan_beats()
	rig.set_pose(MythosRig.Pose.DIVE)
	_trail.global_position = _path.point_at(0.0)
	_trail.restart()
	_trail.emitting = true
	advance(0.0)


## Un frame de la entrada con la calma en `progress` (0-1).
func advance(progress: float) -> void:
	if not _live:
		return
	while _next_beat < _beats.size() and progress >= _beats[_next_beat].at:
		_next_beat += 1
		_beats[_next_beat - 1].run.call()
	if _grounded:
		var since := (progress - impact_fraction) * _seconds
		_bird = _center + Vector3.UP * _boss.rig.body_height()
		_ring.fade_out(since)
		# La onda del golpe se lleva de la vista a la horda que alcanza.
		_veil.sweep(get_tree(), _center, wave_start_radius + wave_speed * since, _boss)
		return
	var at := _path.sample(progress)
	_bird = at.point
	_boss.rig.fly_at(at.point, at.yaw, at.pitch, at.roll)
	_trail.global_position = at.point - _forward(at) * trail_back
	var lap := maxf(ring_until - comet_until, 0.001) / maxf(ring_laps, 0.01)
	_ring.draw((progress - comet_until) / lap, lap * _seconds)


## Dónde está el fénix ahora, en el mundo (lo que sigue la cámara).
func bird_point() -> Vector3:
	return _bird


## Corta la entrada (la calma terminó, alguien la saltó o la arena se va) y
## apaga lo que quede encendido. Se puede llamar siempre.
func stop() -> void:
	if not _live:
		return
	_live = false
	_trail.emitting = false
	_ring.clear()
	_veil.lift()
	for child: Node in get_children():
		if child.is_inside_tree() and child.has_method(&"dissipate"):
			child.call(&"dissipate")


# --- momentos ---------------------------------------------------------------------

## Arma la lista de momentos, en orden.
func _plan_beats() -> void:
	_beats.clear()
	_add_beat(0.0, _on_omen)
	_add_beat(level_fraction, _on_level)
	_add_beat(comet_until, _on_ring_entered)
	_add_beat(ring_until, _on_climb)
	_add_beat(apex_fraction, _on_apex)
	_add_beat(plunge_fraction, _on_plunge)
	_add_beat(impact_fraction, _on_impact)
	for index: int in range(1, waves):
		_add_beat(impact_fraction + wave_interval * float(index) / _seconds, _send_wave)
	_add_beat(rear_fraction, _on_rear)
	_add_beat(rise_fraction, _on_rise)
	_add_beat(reveal_fraction, _on_reveal)
	_add_beat(roar_fraction, _on_roar)
	_beats.sort_custom(func(a: Beat, b: Beat) -> bool: return a.at < b.at)
	_next_beat = 0


func _add_beat(at: float, run: Callable) -> void:
	var beat := Beat.new()
	beat.at = at
	beat.run = run
	_beats.append(beat)


func _on_omen() -> void:
	Sfx.play(omen_sfx)


## Sale de la picada: abre las alas y sigue rasante.
func _on_level() -> void:
	_boss.rig.set_pose(MythosRig.Pose.GLIDE)
	Sfx.play(level_sfx)


func _on_ring_entered() -> void:
	Sfx.play(ring_sfx)


func _on_climb() -> void:
	_boss.rig.gesture(&"flap")
	Sfx.play(climb_sfx)


## En lo alto: alas abiertas y un fogonazo, como un segundo sol.
func _on_apex() -> void:
	var rig := _boss.rig
	rig.set_pose(MythosRig.Pose.CAST)
	rig.pop_nova(apex_flash_radius, apex_flash_seconds)
	rig.burst()
	Sfx.play(apex_sfx)
	shake_requested.emit(apex_shake, apex_flash_seconds)


func _on_plunge() -> void:
	_boss.rig.set_pose(MythosRig.Pose.DIVE)
	Sfx.play(plunge_sfx)


## Golpea el suelo: deja el recorrido, y salen el fogonazo, los escombros, la
## primera onda y la columna.
func _on_impact() -> void:
	_grounded = true
	_trail.emitting = false
	var rig := _boss.rig
	rig.stop_flying()
	rig.set_trail(false)
	rig.burst()
	rig.pop_nova(impact_flash_radius, impact_flash_seconds)
	_debris.global_position = _center
	_debris.restart()
	_debris.emitting = true
	if waves > 0:
		_send_wave()
	_raise_pillar()
	Sfx.play(impact_sfx)
	shake_requested.emit(impact_shake, impact_shake_seconds)
	flash_requested.emit(impact_flash_alpha)


func _on_rear() -> void:
	_boss.rig.set_pose(MythosRig.Pose.REAR)


func _on_rise() -> void:
	_boss.rig.set_pose(MythosRig.Pose.WINDUP)


## Abre las alas de golpe y la columna se deshace a su alrededor.
func _on_reveal() -> void:
	var rig := _boss.rig
	rig.set_pose(MythosRig.Pose.CAST)
	rig.gesture(&"flap")
	rig.burst()
	rig.pop_nova(reveal_flash_radius, reveal_flash_seconds)
	Sfx.play(reveal_sfx)
	shake_requested.emit(reveal_shake, reveal_flash_seconds)


func _on_roar() -> void:
	_boss.rig.gesture(&"roar")
	Sfx.play(roar_sfx)
	shake_requested.emit(roar_shake, 1.0)


# --- efectos ----------------------------------------------------------------------

## Hacia dónde apunta el pico en la muestra `at` del recorrido.
func _forward(at: MythosEntrancePath.Sample) -> Vector3:
	var pitch := deg_to_rad(at.pitch)
	return Vector3(-sin(at.yaw) * cos(pitch), sin(pitch), -cos(at.yaw) * cos(pitch))


## Una onda de fuego que no daña, desde el punto del golpe.
func _send_wave() -> void:
	var node := _spawn(wave_scene)
	var wave := node as FireWave
	if wave != null:
		wave.open(_center, wave_start_radius, wave_radius, wave_speed, 0.0, 0.0, 0.0, null)
	elif node != null:
		node.queue_free()


## La columna de fuego: dura hasta que abre las alas; no quema ni se mueve.
func _raise_pillar() -> void:
	var node := _spawn(pillar_scene)
	var pillar := node as FireTornado
	if pillar != null:
		var life := (reveal_fraction - impact_fraction) * _seconds - pillar_form_seconds
		pillar.start(_center, pillar_radius, pillar_form_seconds, maxf(life, 0.1), 0.0, 0.0,
				false)
	elif node != null:
		node.queue_free()


## Una instancia propia de `scene`, colgada de este nodo. No sale del pool:
## lo del pool cuelga de la arena, que está congelada durante la calma.
func _spawn(scene: PackedScene) -> Node:
	if scene == null:
		return null
	var node := scene.instantiate()
	add_child(node)
	return node
