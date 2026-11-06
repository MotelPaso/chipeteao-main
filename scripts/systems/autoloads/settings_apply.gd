extends Node
## Autoload "Settings": el único que APLICA los ajustes guardados en
## SaveData (volumen de efectos y ambiente, sensibilidad del mouse, pantalla
## completa, contador de FPS, calidad gráfica).
## Va después de Sfx para que existan los dos buses de código, y antes de
## cargar cualquier escena para que buses y modo de ventana estén bien desde
## el primer frame. El panel de ajustes escribe por la API set_* de aquí, que
## cambia SaveData, aplica el valor en vivo y agenda un guardado a disco
## (que se fuerza al cerrar el panel). Sin ventana, los buses mezclan en el
## driver falso y la llamada de ventana está resguardada.

## Los deslizadores van de 0 a 100 en línea recta sobre este rango de dB; el
## 0 además silencia el bus (-40 dB solo todavía se oye un poco).
const MIN_VOLUME_DB := -40.0
const MAX_VOLUME_DB := 0.0
## Segundos sin mover un deslizador antes de guardar el cambio a disco.
@export var save_debounce: float = 0.8

## --- Calidad gráfica --------------------------------------------------------
## Índice = SaveData.graphics_quality: 0 Alta, 1 Media, 2 Baja.
##
## POR QUÉ ESTAS DOS PERILLAS. La interfaz se estira en modo `canvas_items`,
## que dibuja el 3D a la resolución NATIVA de la ventana (pantalla completa
## en una MacBook retina es 3024x1964, 6.4 veces los 1280x720 de diseño). El
## costo por fragmento escala con esos píxeles, y las sombras de cuatro
## cortes del sol redibujan cada objeto hasta 100 m cuatro veces más. Son
## las dos palancas de GPU más grandes que no tocan el juego; el HUD se ve
## nítido a cualquier escala 3D porque el 2D se dibuja aparte.
## Alta es la imagen completa, sin recortes.
const RENDER_SCALE_BY_QUALITY: Array[float] = [1.0, 0.75, 0.5]
## Alcance de las sombras del sol por calidad, en metros; un negativo deja
## lo que trae la arena y cero apaga las sombras del sol.
const SUN_SHADOW_DISTANCE_BY_QUALITY: Array[float] = [-1.0, 60.0, 0.0]
## Cortes de sombra de Media: la mitad de las pasadas de los cuatro
## originales; a 60 m la cascada más lejana ya está bajo la niebla.
const REDUCED_SUN_SHADOW_MODE := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
## SubViewports por las que una partida en pantalla dividida dibuja el
## mundo. La escala 3D del viewport raíz no llega a ellas, así que
## SplitScreen.build mete cada una en este grupo y la calidad se aplica
## también al grupo.
const WORLD_VIEW_GROUP := &"world_views"
## Dónde guarda un sol la configuración de sombras de su arena, para que
## volver a Alta la restaure en vez de adivinar los valores del motor.
const SUN_AUTHORED_META := &"authored_sun_shadow"

var _save_timer: Timer


func _ready() -> void:
	# El menú de pausa abre el panel con el árbol pausado; el temporizador
	# del guardado tiene que seguir corriendo ahí.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_on_save_timeout)
	add_child(_save_timer)
	# Cada etapa trae su arena y su sol; la calidad tiene que llegar a cada
	# uno. RunState se registra antes que este autoload.
	RunState.stage_changed.connect(func(_index: int, _map_id: String) -> void:
		_apply_sun_shadows())
	apply_all()


## Cerrar la ventana es la única salida que no pasa por el panel ni por la
## pausa: sin esto, un deslizador movido en el último instante se perdería
## porque solo lo sabía el temporizador.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_save()


## Aplica todo lo guardado al arrancar (y cuando el harness recarga).
func apply_all() -> void:
	_apply_bus_volume(Sfx.BUS_NAME, SaveData.sfx_volume)
	_apply_bus_volume(Sfx.AMBIENT_BUS_NAME, SaveData.ambient_volume)
	_apply_fullscreen(SaveData.fullscreen)
	apply_graphics()


## --- API del panel (recorta, guarda, aplica en vivo, agenda el guardado) ----

func set_sfx_volume(value: float) -> void:
	SaveData.sfx_volume = clampf(value, 0.0, 100.0)
	_apply_bus_volume(Sfx.BUS_NAME, SaveData.sfx_volume)
	_request_save()


func set_ambient_volume(value: float) -> void:
	SaveData.ambient_volume = clampf(value, 0.0, 100.0)
	_apply_bus_volume(Sfx.AMBIENT_BUS_NAME, SaveData.ambient_volume)
	_request_save()


func set_mouse_sensitivity(value: float) -> void:
	SaveData.mouse_sensitivity = clampf(value,
			SaveData.MIN_MOUSE_SENSITIVITY, SaveData.MAX_MOUSE_SENSITIVITY)
	# El jugador lee SaveData.mouse_sensitivity en cada evento del mouse, así
	# que el valor nuevo rige sin aviso.
	_request_save()


func set_fullscreen(on: bool) -> void:
	SaveData.fullscreen = on
	_apply_fullscreen(on)
	_request_save()


## El HUD consulta SaveData.show_fps, así que cambiarlo rige en todas
## partes a la vez, incluso en un HUD que aún no existe (menú -> partida).
func set_show_fps(on: bool) -> void:
	SaveData.show_fps = on
	_request_save()


func set_graphics_quality(quality: int) -> void:
	SaveData.graphics_quality = clampi(quality, 0, SaveData.MAX_GRAPHICS_QUALITY)
	apply_graphics()
	_request_save()


## La escala 3D de la calidad actual (1.0 = nativa).
static func render_scale() -> float:
	return RENDER_SCALE_BY_QUALITY[clampi(SaveData.graphics_quality, 0,
			RENDER_SCALE_BY_QUALITY.size() - 1)]


## Da a un viewport la escala 3D de la calidad. FSR 1 bajo la nativa (un
## reescalador espacial que funciona en todo driver Forward+, Metal
## incluido) y bilineal simple en 1.0, donde no se escala nada.
static func apply_render_scale(viewport: Viewport) -> void:
	if viewport == null:
		return
	var scale := render_scale()
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 \
			else Viewport.SCALING_3D_MODE_BILINEAR


## Gancho de cierre del panel / salida al menú: guarda ya cualquier cambio
## pendiente.
func flush_save() -> void:
	if _save_timer.is_stopped():
		return
	_save_timer.stop()
	SaveData.save()


## --- Aplicación ---------------------------------------------------------------

## Valor del deslizador 0..100 -> dB del bus (0 -> -40, 50 -> -20, 100 -> 0).
static func volume_to_db(value: float) -> float:
	return lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, clampf(value, 0.0, 100.0) / 100.0)


static func _apply_bus_volume(bus_name: StringName, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, volume_to_db(value))
	AudioServer.set_bus_mute(idx, value <= 0.0)


## La calidad de SaveData sobre los viewports y el sol de la escena actual.
## Pública para el harness de soak, que apunta SaveData a su propio guardado
## después de que este autoload ya aplicó el del jugador.
func apply_graphics() -> void:
	apply_render_scale(get_tree().root)
	for node: Node in get_tree().get_nodes_in_group(WORLD_VIEW_GROUP):
		apply_render_scale(node as Viewport)
	_apply_sun_shadows()


## Cada DirectionalLight3D bajo la escena actual: el sol de la arena en una
## partida, nada en la pantalla de selección. El primer toque guarda en la
## luz lo que traía la arena, que es a lo que vuelve Alta.
func _apply_sun_shadows() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var distance: float = SUN_SHADOW_DISTANCE_BY_QUALITY[clampi(
			SaveData.graphics_quality, 0, SUN_SHADOW_DISTANCE_BY_QUALITY.size() - 1)]
	var suns := scene.find_children("*", "DirectionalLight3D", true, false)
	# Una línea por aplicación (convención de RunManager): lo que un soak
	# busca para probar que la calidad llegó a su arena. La escala se lee del
	# viewport raíz y no de la tabla, así la línea dice lo que de verdad se
	# está dibujando.
	print("Graphics: quality=%d scale=%.2f suns=%d views=%d" % [
			SaveData.graphics_quality, get_tree().root.scaling_3d_scale, suns.size(),
			get_tree().get_node_count_in_group(WORLD_VIEW_GROUP)])
	for node: Node in suns:
		var sun := node as DirectionalLight3D
		if not sun.has_meta(SUN_AUTHORED_META):
			sun.set_meta(SUN_AUTHORED_META, [sun.shadow_enabled,
					sun.directional_shadow_mode, sun.directional_shadow_max_distance])
		var authored: Array = sun.get_meta(SUN_AUTHORED_META)
		if distance < 0.0:
			sun.shadow_enabled = authored[0]
			sun.directional_shadow_mode = authored[1]
			sun.directional_shadow_max_distance = authored[2]
		elif distance == 0.0:
			sun.shadow_enabled = false
		else:
			sun.shadow_enabled = authored[0]
			sun.directional_shadow_mode = REDUCED_SUN_SHADOW_MODE
			sun.directional_shadow_max_distance = minf(distance, authored[2])


static func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
			else DisplayServer.WINDOW_MODE_WINDOWED)


func _request_save() -> void:
	# Timer.start(0) es un error en Godot; un retardo cero significa "guarda ya".
	if save_debounce <= 0.0:
		SaveData.save()
		return
	_save_timer.start(save_debounce)


func _on_save_timeout() -> void:
	SaveData.save()
