class_name LobsterArrival
extends Node
## La llegada de la Langosta Azul (nodo Arrival de BlueLobster.tscn). Hay dos:
##   - En su arena propia la trae LA CINEMÁTICA del viaje (LobsterEntrance, que
##     cuelga de BossArenaHost): la langosta nace escondida, sin barra, flecha
##     ni marcador, y espera a que la cinemática la muestre y le diga que la
##     pelea empieza.
##   - Sin cinemática en curso (un mapa que la invoca directamente, una
##     prueba suelta) llega sola: aparece dentro de un anillo, ruge y,
##     pasados plain_seconds, empieza a pelear.
## La llegada termina cuando alguien llama a BlueLobster.finish_entrance(): la
## cinemática, o este nodo en la llegada simple.

@export_group("Llegada simple")
## Segundos que tarda en empezar a pelear desde que aparece.
@export var plain_seconds: float = 0.9
## Radio en metros del anillo con que aparece.
@export var plain_ring_radius: float = 3.5
## Rugido con que aparece (fila de Sfx.SOUND_LIBRARY).
@export var plain_roar_sfx: StringName = &"boss_roar"

var _boss: BlueLobster = null
var _plain_left: float = 0.0


## Arranca la llegada con la langosta ya ubicada en la arena.
func begin(boss: BlueLobster) -> void:
	_boss = boss
	var cinematic := _running_cinematic()
	# Línea de log para los soaks: la llegada se mide desde aquí.
	print("%s entrance started: seconds=%.2f plain=%s at %.1fs" % [boss.boss_title,
			cinematic.intro_seconds if cinematic != null else plain_seconds,
			cinematic == null, RunState.stage_time])
	if cinematic != null:
		# Sin aviso: ni barra, ni flecha, ni marcador hasta que empiece la pelea.
		boss.hide_presence()
		return
	_plain_left = plain_seconds
	boss.pop_in(plain_ring_radius)
	Sfx.play(plain_roar_sfx)


## Un frame de física de la llegada: solo trabaja en la llegada simple.
func tick(delta: float) -> void:
	if _plain_left <= 0.0 or _boss == null:
		return
	_plain_left -= delta
	if _plain_left <= 0.0:
		_boss.finish_entrance(plain_seconds, false)


## La langosta murió: su canción se apaga de a poco. Su caída sigue aunque
## otro jefe congele el mundo mientras tanto (la calma de Mythos): no queda a
## medias, quieta en el aire, todo lo que dura.
func on_boss_dead() -> void:
	if _boss != null and is_instance_valid(_boss):
		WorldFreeze.exempt(_boss)
	get_tree().call_group(LobsterEntrance.GROUP, &"fade_out_song")


## La cinemática de la langosta que está en curso, o null.
func _running_cinematic() -> LobsterEntrance:
	for node: Node in get_tree().get_nodes_in_group(LobsterEntrance.GROUP):
		var cinematic := node as LobsterEntrance
		if cinematic != null and cinematic.is_calm_active():
			return cinematic
	return null
