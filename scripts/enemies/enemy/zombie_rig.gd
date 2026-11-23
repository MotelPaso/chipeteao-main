class_name ZombieRig
extends Node3D
## Cuerpo del zombi oficinista (assets/models/enemies/zombie/zombie.tscn): el
## modelo .glb con esqueleto, girado para mirar a -Z como todo enemigo. Solo
## reproduce en bucle su caminata; la persecución, el destello de golpe y la
## caída al morir los pone EnemyBase sobre el nodo Visual que lo contiene.

@export_group("Animación")
## Animación que repite mientras vive (las demás del modelo: Idle, Death1-4, OfficeWorker_FlinchLeft/Right).
@export var walk_animation: StringName = &"OfficeWorker_Walk"
## Velocidad de la caminata (1 = la del modelo, 2 = el doble de rápida).
@export var walk_speed_scale: float = 1.4
## Si es true, cada zombi empieza la caminata en otro punto, para que la horda no camine al unísono.
@export var desync_start: bool = true


func _ready() -> void:
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(walk_animation):
		push_warning("ZombieRig: animation '%s' not found" % walk_animation)
		return
	var animation := player.get_animation(walk_animation)
	animation.loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = walk_speed_scale
	player.play(walk_animation)
	if desync_start:
		# Desfase por id de instancia y no por randf(): el RNG de la partida
		# es uno solo y un dado de más cambiaría las partidas con semilla.
		var phase := float(get_instance_id() % 997) / 997.0
		player.seek(phase * animation.length, true)
