class_name LobsterEntranceActors
extends Node
## LOS CUERPOS de la cinemática de la Langosta Azul (hijo Actors de
## LobsterEntrance.tscn): lo que hacen la langosta y el equipo en el fondo del
## mar mientras la cámara corre. La langosta nace escondida, espera enterrada
## bajo un montículo, sale de la arena de un salto y no le saca los ojos de
## encima a la cámara; los raiders se esconden mientras el equipo «cae» y
## vuelven a verse al tocar fondo. La salida va en dos tiempos: primero sube
## desde lo enterrado rompiendo su montículo, y después salta y vuelve a caer.
## Cuándo pasa cada cosa lo dice el plano que entra (LobsterEntranceShot.event);
## la pose y el gesto de cada plano los pone el director. release() deja a
## todos como los quiere la pelea.

@export_group("Salida de la langosta")
## Metros que la langosta espera enterrada antes de salir.
@export var buried_depth: float = 2.8
## Segundos que tarda en salir de la arena, saltar y volver a caer.
@export var eruption_seconds: float = 0.9
## Parte de ese tiempo (0-1) en que sube desde abajo de la arena hasta quedar a ras.
@export_range(0.05, 0.9) var emerge_fraction: float = 0.3
## Metros bajo la arena desde los que arranca la salida: su alto en la pose de salida, para que empiece tapada entera.
@export var emerge_depth: float = 6.5
## Metros que salta al salir.
@export var eruption_height: float = 5.2

var _boss: BlueLobster = null
## Segundos que lleva la langosta saliendo de la arena (< 0 = no está saliendo).
var _erupting: float = -1.0
## Los raiders escondidos mientras el equipo «cae».
var _hidden_party: Array[Node3D] = []


## Empieza el fondo del mar: la langosta recién nacida queda escondida, y los
## raiders también. Ya están parados en la arena, y la cámara que baja los
## vería esperándose a sí mismos.
func enter(boss: BlueLobster, party: Array[Node3D]) -> void:
	_boss = boss
	_erupting = -1.0
	boss.rig.visible = false
	boss.rig.fidgets = false
	boss.rig.set_near_fade(false)
	boss.rig.add_visual_layer(LobsterEntranceCamera.ISOLATION_LAYER)
	for raider: Node3D in party:
		if is_instance_valid(raider) and raider.visible:
			raider.visible = false
			_hidden_party.append(raider)


## Lo que pide el plano que entra (ver LobsterEntranceShot.event). `fx` son
## los efectos del viaje y `arena` la arena del jefe, donde el equipo toca fondo.
func play(event: StringName, fx: LobsterAbductionFx, arena: BossArena) -> void:
	match event:
		&"bury":
			if is_instance_valid(_boss):
				_boss.rig.visible = true
				_boss.rig.sink = buried_depth
				_boss.rig.set_mound(1.0)
				_boss.rig.set_dust(true)
		&"land":
			fx.set_descent(false)
			show_party()
			if arena != null:
				fx.land(arena.spawn_origin())
		&"erupt":
			if is_instance_valid(_boss):
				_boss.rig.visible = true
				_boss.rig.set_dust(false)
				_erupting = 0.0
				_pose_eruption(0.0)
				fx.erupt(_boss.global_position)


## Un frame del fondo del mar: la langosta mira a `eye` (la cámara) y, si está
## saliendo de la arena, sigue su salida.
func tick(delta: float, eye: Vector3) -> void:
	if not is_instance_valid(_boss):
		return
	if _boss.rig.visible:
		_boss.rig.gaze_at(eye)
	if _erupting < 0.0:
		return
	_erupting += delta
	var along := clampf(_erupting / maxf(eruption_seconds, 0.01), 0.0, 1.0)
	_pose_eruption(along)
	if along >= 1.0:
		_erupting = -1.0


## La langosta cuando lleva `along` (0-1) de su salida. Hasta emerge_fraction
## sube desde emerge_depth metros bajo la arena, de corrido, mientras su
## montículo se deshace; desde ahí salta eruption_height metros y vuelve a
## caer en su lugar.
func _pose_eruption(along: float) -> void:
	var rig := _boss.rig
	if along < emerge_fraction:
		var out := along / emerge_fraction
		rig.sink = emerge_depth * (1.0 - out)
		rig.lift = 0.0
		rig.set_mound(1.0 - out)
		return
	var jump := (along - emerge_fraction) / maxf(1.0 - emerge_fraction, 0.01)
	rig.sink = 0.0
	rig.lift = eruption_height * sin(jump * PI) if along < 1.0 else 0.0
	rig.set_mound(0.0)


## Vuelven a verse los raiders escondidos.
func show_party() -> void:
	for raider: Node3D in _hidden_party:
		if is_instance_valid(raider):
			raider.visible = true
	_hidden_party.clear()


## Deja al equipo a la vista y a la langosta como la quiere la pelea. Se puede
## llamar siempre.
func release() -> void:
	show_party()
	_erupting = -1.0
	if not is_instance_valid(_boss):
		return
	_boss.rig.visible = true
	_boss.rig.fidgets = true
	_boss.rig.sink = 0.0
	_boss.rig.lift = 0.0
	_boss.rig.set_mound(0.0)
	_boss.rig.set_dust(false)
	_boss.rig.set_near_fade(true)
	_boss.rig.gaze_ahead()
