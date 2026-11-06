class_name SecretTrigger
extends Interactable
## Base de los disparadores de jefe oculto: un objeto disfrazado del mundo
## que, al cumplirse su condición (la define la subclase), se gasta y hace
## aparecer su minijefe cerca con un cartel de aviso. Un uso por partida; la
## escena se reinicia sola al recargar. Sin contador propio: las misiones
## cuentan la MUERTE del minijefe (SecretBossBase).
##
## NUNCA es un marcador de mapa: `marker_kind` queda vacío a propósito,
## porque encontrarlos es la mecánica entera.

@export_group("Secreto")
## Escena del minijefe oculto (su raíz debe extender BossBase).
@export var miniboss_scene: PackedScene
## Dónde aparece el minijefe respecto del disparador (ejes del mundo, metros); apúntalo a terreno abierto.
@export var spawn_offset: Vector3 = Vector3(4.0, 0.1, -4.0)
## Línea del cartel de aviso (grupo "boss_ui") al despertar.
@export var awaken_text: String = "Algo oculto se remueve..."
@export_group("Frase flotante")
## Tamaño de letra de la frase flotante (show_flavor), en píxeles.
@export var flavor_font_size: int = 48
## Grosor del contorno de la frase, en píxeles.
@export var flavor_outline_size: int = 12
## Color de la frase.
@export var flavor_color: Color = Color(0.9, 0.98, 0.7)
## Altura a la que aparece la frase sobre el disparador, en metros.
@export var flavor_height: float = 2.2
## Metros que sube la frase mientras dura.
@export var flavor_rise: float = 1.0
## Segundos que dura la frase.
@export var flavor_time: float = 1.4
## Segundos que espera la frase antes de empezar a desvanecerse.
@export var flavor_fade_delay: float = 0.9
## Segundos que tarda en desvanecerse.
@export var flavor_fade_time: float = 0.5

## El minijefe despertado (null hasta que aparece; lo lee el harness).
var spawned_boss: BossBase = null


## Gasta el disparador y saca al minijefe. El guardia sobre `available`
## impide que una subclase lo despierte dos veces.
func _awaken() -> void:
	if not available:
		return
	consume()
	dim_visuals()
	_emit_completed()
	get_tree().call_group("boss_ui", "announce", awaken_text)
	_spawn_miniboss()


func _spawn_miniboss() -> void:
	if miniboss_scene == null:
		return
	# Va colgado de la ARENA, no de current_scene: el minijefe es de la etapa
	# que lo despertó.
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	var node := miniboss_scene.instantiate()
	var boss := node as BossBase
	if boss == null:
		node.free()
		push_warning("SecretTrigger: miniboss scene root does not extend BossBase.")
		return
	spawned_boss = boss
	scene_root.add_child(boss)
	boss.global_position = global_position + spawn_offset
	# Línea de log para las corridas headless.
	print("Secret miniboss awakened: %s" % boss.boss_title)


## Frase flotante corta sobre el disparador. Va colgada de la arena para que
## sobreviva a los cambios de estado del disparador.
func show_flavor(line: String) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	var label := Label3D.new()
	label.text = line
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = flavor_font_size
	label.outline_size = flavor_outline_size
	label.modulate = flavor_color
	scene_root.add_child(label)
	label.global_position = global_position + Vector3.UP * flavor_height
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + flavor_rise, flavor_time)
	tween.tween_property(label, "modulate:a", 0.0, flavor_fade_time).set_delay(flavor_fade_delay)
	tween.chain().tween_callback(label.queue_free)
