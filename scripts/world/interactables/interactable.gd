class_name Interactable
extends Area3D
## Base de los interactuables del mundo (altares, cofres, secretos). El
## Area3D es el anillo de detección: mientras un raider está dentro y el
## interactuable sigue disponible, se ve un aviso flotante (Label3D) y la
## acción "interact" llama a _interact(). Las subclases emiten las señales
## con los _emit_* y llaman a consume() al gastarse. El jugador se encuentra
## por su grupo y los premios salen por call_group.

signal interaction_started
signal interaction_completed
signal interaction_cancelled

## Marcador del botón en cada línea de aviso. "interact" está en E y en un
## botón del control (Coop.PAD_INTERACT_BUTTON): la etiqueta lo cambia según
## el raider que está en el anillo.
const INTERACT_TOKEN: String = "[E]"
## Lo que muestra el marcador para un slot que juega con control.
const PAD_INTERACT_GLYPH: String = "[Y]"

@export_group("Aviso flotante")
## Línea del aviso mientras un raider está en el anillo; el botón se escribe [E] y se cambia por el del raider.
@export var prompt_text: String = "[E] Interactuar"
## Altura del aviso sobre el origen del interactuable, en metros.
@export var prompt_height: float = 3.4
## Tamaño de letra del aviso, en píxeles (el mismo para todos los interactuables).
@export var prompt_font_size: int = 52
## Grosor del contorno del aviso, en píxeles.
@export var prompt_outline_size: int = 14
## Color del texto del aviso.
@export var prompt_color: Color = Color(0.96, 0.93, 0.8)
@export_group("Al completarse")
## Sonido (id de Sfx) que suena al completarse.
@export var complete_sound: StringName = &"shrine_done"
## Contador de SaveData que sube al gastarse ("" = ninguno); lo leen las misiones.
@export var meta_stat_id: String = ""
@export_group("Gastado")
## Color plano de piedra que toman todas las mallas al apagarse (dim_visuals).
@export var spent_color: Color = Color(0.34, 0.34, 0.37)
## Segundos que tarda en hundirse y desaparecer (sink_away).
@export var sink_duration: float = 0.5
## Metros que baja mientras se hunde (0 = solo se encoge).
@export var sink_depth: float = 0.0
## Escala final antes de liberarse, como fracción del tamaño (0-1).
@export var sink_end_scale: float = 0.05
@export_group("Mapa")
## Punto que dibuja en el minimapa y el mapa (Tab); vacío = no aparece (los secretos lo dejan vacío a propósito).
@export var marker_kind: StringName = &""

## Lo apaga consume(); un interactuable gastado ignora "interact".
var available: bool = true
var player_in_range: bool = false

## Raiders dentro del anillo (en co-op, varios); player_in_range dice si hay
## alguno. Un raider caído sigue en la lista (su cuerpo no sale del área):
## para saber quién puede sostener un ritual, usa live_players_in_range().
var _players_in_range: Array[Node3D] = []

## Loop de Sfx con contador de referencias que retiene este nodo (&"" = ninguno).
var _held_loop: StringName = &""

var _prompt: Label3D
## Lo enciende sink_away para no apilar dos salidas.
var _sinking: bool = false


func _ready() -> void:
	if not marker_kind.is_empty():
		add_to_group(&"map_markers")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = prompt_font_size
	_prompt.outline_size = prompt_outline_size
	_prompt.modulate = prompt_color
	_prompt.position = Vector3.UP * prompt_height
	add_child(_prompt)
	_refresh_prompt()


## Los loops compartidos (el zumbido lo usan los altares y el Cráneo
## zumbante) llevan contador: una liberación por cada toma, y otra aquí para
## que salir a mitad de un canal no deje la voz sonando.
func _exit_tree() -> void:
	_drop_loop()


func _unhandled_input(event: InputEvent) -> void:
	if not available or not player_in_range:
		return
	# Cada raider responde solo a SU acción (solo: la del proyecto; co-op: la
	# copia de su slot), así el altar se resuelve para quien apretó.
	for body: Node3D in live_players_in_range():
		var interact_name: StringName = &"interact"
		if body.has_method(&"interact_action"):
			interact_name = body.call(&"interact_action")
		if event.is_action_pressed(interact_name):
			_interact(body)
			# Una pulsación resuelve UN interactuable aunque los anillos se
			# solapen.
			get_viewport().set_input_as_handled()
			return


## Marca el interactuable como gastado: sin aviso y sin más interacciones.
func consume() -> void:
	if available and meta_stat_id != "":
		SaveData.bump(meta_stat_id)
	available = false
	_refresh_prompt()


## Cambia la línea del aviso (por ejemplo, el texto de "reanudar").
func set_prompt(text: String) -> void:
	prompt_text = text
	_refresh_prompt()


## Hunde y encoge el interactuable (sink_duration, sink_depth, sink_end_scale) y
## lo libera al terminar; detiene _physics_process. Con `keep_alive` el nodo
## sigue vivo hasta esos segundos aunque el hundimiento ya haya terminado.
## Una sola vez: las llamadas siguientes no hacen nada.
func sink_away(keep_alive: float = 0.0) -> void:
	if _sinking:
		return
	_sinking = true
	set_physics_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	if keep_alive > 0.0:
		tween.tween_interval(keep_alive)
	if not is_zero_approx(sink_depth):
		tween.tween_property(self, "position:y", position.y - sink_depth, sink_duration) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * sink_end_scale, sink_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Gris de "usado": toda malla recibe un material plano de spent_color y las
## luces se apagan, para que se lea gastado desde lejos.
func dim_visuals() -> void:
	var dim := StandardMaterial3D.new()
	dim.albedo_color = spent_color
	dim.roughness = 1.0
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = dim
	for node: Node in find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if light != null:
			light.visible = false


## Raiders del anillo que siguen EN PIE. Un caído no sale del Area3D (solo
## deja el grupo "player"), así que toda pregunta de "quién sostiene el
## ritual / quién paga / de quién cuentan los stats" pasa por aquí. Los
## cuerpos liberados se descartan de la lista al pasar.
func live_players_in_range() -> Array[Node3D]:
	var live: Array[Node3D] = []
	var kept: Array[Node3D] = []
	for body: Node3D in _players_in_range:
		if not is_instance_valid(body):
			continue
		kept.append(body)
		if body.is_in_group("player"):
			live.append(body)
	if kept.size() != _players_in_range.size():
		_players_in_range = kept
		player_in_range = not _players_in_range.is_empty()
	return live


## Raider en pie más cercano del anillo (null si no hay ninguno); decide las
## partes del aviso que dependen del raider.
func nearest_live_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for body: Node3D in live_players_in_range():
		var distance := global_position.distance_squared_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## Mayor cantidad de copias de `item_id` entre los raiders del anillo (la
## party junta sus llaves y su sangre: manda el que más tiene).
func best_item_count_in_range(item_id: String) -> int:
	var best := 0
	for body: Node3D in live_players_in_range():
		var bag := ItemBag.find_in(body)
		if bag != null:
			best = maxi(best, bag.count(item_id))
	return best


## true mientras el aviso se ve (raider en rango y disponible).
func prompt_visible() -> bool:
	return _prompt != null and _prompt.visible


## Contrato de marcadores de mapa (grupo "map_markers").
func map_marker_kind() -> StringName:
	return marker_kind


## Virtual: el efecto. `player` es el nodo del grupo "player" que apretó.
func _interact(_player: Node) -> void:
	pass


## Virtuales para cuando alguien entra o sale del anillo.
func _on_range_entered() -> void:
	pass


func _on_range_exited() -> void:
	pass


func _emit_started() -> void:
	interaction_started.emit()


func _emit_completed() -> void:
	Juice.sparkle(global_position + Vector3.UP * 1.2)
	Sfx.play(complete_sound)
	interaction_completed.emit()


func _emit_cancelled() -> void:
	interaction_cancelled.emit()


## Empieza (o cambia a) un loop de Sfx con contador que retiene este nodo.
## Una liberación por cada toma: el campo _held_loop lo garantiza.
func _hold_loop(id: StringName) -> void:
	if _held_loop == id:
		return
	_drop_loop()
	_held_loop = id
	Sfx.acquire_loop(id)


func _drop_loop() -> void:
	if _held_loop == &"":
		return
	Sfx.release_loop(_held_loop)
	_held_loop = &""


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not _players_in_range.has(body):
		_players_in_range.append(body)
	player_in_range = true
	_refresh_prompt()
	_on_range_entered()


func _on_body_exited(body: Node3D) -> void:
	if not _players_in_range.has(body):
		return
	_players_in_range.erase(body)
	if not _players_in_range.is_empty():
		return  # sigue habiendo alguien en el anillo: no hay salida de rango
	player_in_range = false
	_refresh_prompt()
	_on_range_exited()


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	_prompt.text = prompt_text.replace(INTERACT_TOKEN, _interact_glyph())
	_prompt.visible = available and player_in_range


## Glifo del botón para el raider más cercano: el slot de teclado (y toda
## partida solo) ve "[E]"; un slot con control ve su botón.
func _interact_glyph() -> String:
	var body := nearest_live_player()
	if body == null:
		return INTERACT_TOKEN
	var slot: Variant = body.get("player_index")
	if slot == null or Coop.device_for_slot(int(slot)) == Coop.KEYBOARD_DEVICE:
		return INTERACT_TOKEN
	return PAD_INTERACT_GLYPH
