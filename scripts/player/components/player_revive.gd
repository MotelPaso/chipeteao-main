class_name PlayerRevive
extends Node3D
## Caído y rescate en co-op. Al caer, el raider sale del grupo "player"
## (todo el targeting lo ignora), sus armas se detienen y su colisión se
## vuelve fantasma; un compañero en pie que mantiene SU acción de
## interactuar cerca lo revive. Es el nodo Revive de Player.tscn y su hijo
## RevivePrompt es el cartel. Player llama a set_downed() y tick() en su
## propio orden; nunca es caído en solo.

@export_group("Rescate")
## Radio de rescate, en metros; arena_probe.gd se acerca a 2 m para revivir.
@export var revive_radius: float = 3.0
## Segundos que un compañero debe mantener Interactuar para revivir.
@export var revive_time: float = 3.0
## Fracción de la vida máxima con que vuelve el revivido (0-1).
@export var revive_heal_fraction: float = 0.5
## Progreso de rescate que se pierde por segundo sin nadie ayudando (0-1 por segundo).
@export var revive_decay_rate: float = 0.5

@onready var _body: Player = get_parent() as Player
@onready var _prompt: RevivePrompt = $RevivePrompt

var _is_downed: bool = false
## Progreso del rescate en curso (0-1).
var _progress: float = 0.0
var _saved_collision_layer: int = 0


func is_downed() -> bool:
	return _is_downed


## Las cinco cosas que cambian juntas al caer o levantarse: grupo (todo el
## targeting usa "player"), colisión fantasma, armas, la caída del rig y el
## cartel. Juntas aquí para que los dos caminos no se separen.
func set_downed(down: bool) -> void:
	_is_downed = down
	_progress = 0.0
	if down:
		# Fuera del grupo "player", todo sistema que apunta (enemigos, imán
		# de gemas, interactuables, el conteo de vivos de RunManager) ignora
		# este cuerpo sin chequeos extra; revivir lo devuelve.
		_body.remove_from_group("player")
		_body.add_to_group("downed_players")
		# Limpiar ANTES de detener el montaje: un arma que deja campos con
		# tiempo (charcos de sangre o de baba) los avanza en su propio
		# _physics_process, y congelada los dejaría en el suelo sin fin.
		_clear_weapon_fields()
		# Las armas dejan de disparar con el cuerpo (los hijos del montaje
		# procesan física).
		_body.weapons_mount.process_mode = Node.PROCESS_MODE_DISABLED
		# Colisión fantasma: el cuerpo no bloquea a compañeros ni a la horda.
		_saved_collision_layer = _body.collision_layer
		_body.collision_layer = 0
		_body.seal_rig.play_death()
		# Si cayó toda la party, RunManager termina la partida en este mismo
		# frame y pausa el árbol: un cartel mostrado ahora quedaría encima de
		# la pantalla de fin (es no_depth_test).
		if not get_tree().get_nodes_in_group("player").is_empty():
			_prompt.open()
	else:
		_body.remove_from_group("downed_players")
		_body.add_to_group("player")
		_body.weapons_mount.process_mode = Node.PROCESS_MODE_INHERIT
		_body.collision_layer = _saved_collision_layer
		_body.seal_rig.reset_death()
		_prompt.close()


## Un tick mientras está caído: un compañero en pie dentro de revive_radius
## que mantiene SU acción de interactuar llena la barra; soltar la vacía
## despacio.
func tick(delta: float) -> void:
	if not RunState.run_active:
		# La partida terminó (derrota total, extracción): se quita el cartel
		# para que no flote sobre la pantalla de fin.
		_prompt.close()
		return
	var rescuing := false
	# Se guarda QUIÉN rescata: el log lo nombra, y así el soak distingue un
	# rescate real de un raider que volvió solo.
	var rescuer: Player = null
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate == null or not mate.is_inside_tree():
			continue
		if _body.global_position.distance_to(mate.global_position) > revive_radius:
			continue
		if Input.is_action_pressed(mate.interact_action()):
			rescuing = true
			rescuer = mate
			break
	if rescuing:
		# Protegido: con revive_time = 0 todo caído se levantaría en el
		# primer frame de contacto.
		_progress += delta / maxf(revive_time, 0.01)
		if _progress >= 1.0:
			_revive(rescuer)
			return
	else:
		_progress = maxf(_progress - revive_decay_rate * delta, 0.0)
	_prompt.refresh(rescuing, _progress)


## Pide a cada arma con campos en el suelo que los suelte. Parte opcional
## del contrato: el arma que deja campos expone clear_weapon_fields().
func _clear_weapon_fields() -> void:
	for weapon: Node in _body.weapons_mount.get_children():
		if weapon.has_method("clear_weapon_fields"):
			weapon.call("clear_weapon_fields")


func _revive(rescuer: Player = null) -> void:
	set_downed(false)
	_body.health.revive(revive_heal_fraction)
	Juice.sparkle(_body.global_position + Vector3.UP * 1.0)
	Sfx.play(&"heal")
	# Log de una línea: ningún soak en solo llega a caer y revivir, y
	# tools/verificar.sh cuenta las líneas "Player revived:".
	print("Player revived: p%d by p%d" % [
			_body.player_index, rescuer.player_index if rescuer != null else -1])
