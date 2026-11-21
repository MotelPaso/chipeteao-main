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
## Dónde aparece el minijefe respecto del disparador (ejes del mundo, metros); se corre al suelo libre más cercano y la y es la altura sobre ese suelo.
@export var spawn_offset: Vector3 = Vector3(4.0, 0.1, -4.0)
## Línea del cartel de aviso (grupo "boss_ui") al despertar.
@export var awaken_text: String = "Algo oculto se remueve..."
## Aviso del HUD si se cumple la condición mientras el jefe de etapa pelea solo: el minijefe no sale hasta que esa pelea termine.
@export var held_text: String = "Lo que duerme aquí no se atreve a salir..."
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


## Dónde aparece `boss`: el punto más cercano a spawn_offset donde se puede
## poner algo a su relief_margin de todo corte (arena_bounds.nearest_place) y
## donde su cuerpo cabe apoyado en el suelo real, más spawn_offset.y.
func miniboss_spawn_point(boss: BossBase) -> Vector3:
	var at := global_position + spawn_offset
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"nearest_place"):
		var spot: Vector2 = bounds.call(&"nearest_place", Vector2(at.x, at.z), boss.relief_margin,
				func(xz: Vector2) -> bool: return _fits(boss, xz))
		at = Vector3(spot.x, at.y, spot.y)
	return _on_ground(Vector2(at.x, at.z))


## Gasta el disparador y saca al minijefe. El guardia sobre `available`
## impide que una subclase lo despierte dos veces.
func _awaken() -> void:
	if not available:
		return
	if EnemySpawner.is_holding(get_tree()):
		# El jefe de etapa pelea solo: el disparador no se gasta y el
		# minijefe espera a que esa pelea termine.
		get_tree().call_group("boss_ui", "announce", held_text)
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
	boss.global_position = miniboss_spawn_point(boss)
	# Línea de log para las corridas headless.
	print("Secret miniboss awakened: %s" % boss.boss_title)


## `xz` apoyado en el suelo real que tiene debajo, más spawn_offset.y.
func _on_ground(xz: Vector2) -> Vector3:
	var at := Vector3(xz.x, 0.0, xz.y)
	at.y = StageLayout.ground_under(get_tree(), at) + spawn_offset.y
	return at


## True si el cuerpo de `boss` cabe parado en `xz`: sus formas de colisión,
## apoyadas en el suelo real, no cruzan nada sólido del mundo (una roca, un
## tronco, un raider) salvo el terreno que tienen bajo los pies.
func _fits(boss: BossBase, xz: Vector2) -> bool:
	var feet := _on_ground(xz)
	var skip: Array[RID] = []
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		skip.append(terrain.get_rid())
	for body: Node in find_children("*", "CollisionObject3D", true, false):
		skip.append((body as CollisionObject3D).get_rid())
	var space := get_world_3d().direct_space_state
	for node: Node in boss.get_children():
		var holder := node as CollisionShape3D
		if holder == null or holder.disabled or holder.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = holder.shape
		query.transform = Transform3D(Basis.IDENTITY, feet + holder.position)
		query.collision_mask = 1
		query.exclude = skip
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true
