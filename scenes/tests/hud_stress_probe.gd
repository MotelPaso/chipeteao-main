extends Node
## Arnés del HUD con el equipo al máximo. Abre HUD.tscn solo (sin partida) en
## cada tamaño de WINDOWS y con 1 a 4 jugadores, le inyecta un caso extremo
## (3 armas, 3 tomos, mascota, BAG_ITEMS objetos, power-ups, dificultad,
## etapa con vuelta, puntos altos y una tarjeta de botín) y revisa:
##   - que nada salga de la pantalla;
##   - que ningún elemento toque a otro: información de partida, bajas,
##     compañeros, muelle de equipo, power-ups, tarjeta de botín, nivel, vida,
##     puntos, XP y minimapas;
##   - que la bolsa respete su tope y muestre la casilla "+N".
## También mide el costo por frame del HUD lleno.
##
## No es parte de tools/verificar.sh. Se corre a mano:
##   godot --headless --fixed-fps 60 --quit-after 3600 \
##     res://scenes/tests/HudStressProbe.tscn
## Con BONK_SHOT_DIR y sin --headless guarda una captura por caso.
##
## Salida:
##   HudStressProbe: size <ancho>x<alto> players=<n> ok ...   una por caso
##   HudStressProbe: done cases=%d                            solo si pasaron todos
## Cualquier falla es un push_error.

const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")
## Ventanas a probar. El proyecto estira un lienzo de 1280x720, así que
## 1920x1080 es el mismo layout a 1.5x.
const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
## Objetos de la bolsa del caso extremo: más que las filas de ItemCatalog, así
## que se repiten filas con ids inventados.
const BAG_ITEMS: int = 24
## Power-ups activos del caso extremo.
const POWERUPS: int = 4
## Frames de espera: a que la ventana aplique su tamaño y a que el HUD una al
## grupo (diferido) y acomode sus contenedores.
const RESIZE_FRAMES: int = 4
const SETTLE_FRAMES: int = 12
## Frames que se promedian para el costo del HUD lleno.
const PERF_FRAMES: int = 120
## Tolerancia (píxeles) al comparar rectángulos.
const SLACK: float = 0.75
const SHOT_DIR_ENV := "BONK_SHOT_DIR"
## Elementos del HUD que no deben tocarse entre sí, por nombre de nodo.
const PARTS: Array[String] = ["RunInfo", "KillsLabel", "MatePanel", "LoadoutDock",
	"PowerUpRow", "LootToast", "LevelLabel", "HpBar", "PointsLabel", "XpBar"]
## Elementos que pueden estar vacíos: la columna de compañeros en solitario.
const EMPTY_OK: Array[String] = ["MatePanel"]
## Elementos que llegan al borde de la ventana y lo pasan: no se les exige
## quedar dentro de la pantalla.
const BLEEDS: Array[String] = ["XpBar"]


## Jugador de mentira: lo justo para que el HUD lo una (ranura, billetera y un
## Health hijo). Sin armas, tomos ni bolsa, así las franjas no pisan lo inyectado.
class FakeRaider extends Node3D:
	signal points_changed(total: int)
	var player_index: int = 0
	var points: int = 0
	var pet_id: String = ""


var _failed: bool = false
var _hud: CanvasLayer = null
var _raiders: Array[FakeRaider] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var cases := 0
	for window: Vector2i in WINDOWS:
		for players in range(1, Coop.MAX_PLAYERS + 1):
			await _probe_case(window, players)
			cases += 1
			if _failed:
				get_tree().quit(1)
				return
	print("HudStressProbe: done cases=%d" % cases)
	get_tree().quit(0)


func _probe_case(window: Vector2i, players: int) -> void:
	get_tree().root.size = window
	_configure_party(players)
	await _frames(RESIZE_FRAMES)
	for slot in players:
		var raider := FakeRaider.new()
		raider.player_index = slot
		raider.add_child(Health.new())
		raider.add_to_group("player")
		add_child(raider)
		_raiders.append(raider)
	_hud = HUD_SCENE.instantiate() as CanvasLayer
	add_child(_hud)
	await _frames(SETTLE_FRAMES)
	_fill()
	await _frames(SETTLE_FRAMES)
	var screen := get_viewport().get_visible_rect()
	var where := "%dx%d players=%d" % [window.x, window.y, players]
	_check(where, screen)
	var frame_ms := await _measure()
	await _shoot("hud_%dx%d_p%d" % [window.x, window.y, players])
	if not _failed:
		var dock := _rect("LoadoutDock")
		print("HudStressProbe: size %dx%d players=%d ok canvas=%dx%d dock=%dx%d bag_tiles=%d frame_ms=%.3f" % [
				window.x, window.y, players, int(screen.size.x), int(screen.size.y),
				int(dock.size.x), int(dock.size.y), _node("BagStrip").get_child_count(),
				frame_ms])
	_hud.queue_free()
	_hud = null
	for raider: FakeRaider in _raiders:
		raider.queue_free()
	_raiders.clear()
	_configure_party(1)
	await _frames(RESIZE_FRAMES)


## Arma el grupo en Coop como lo hace el lobby (crea las acciones por
## ranura): el teclado en la ranura 0 y un control por cada compañero.
func _configure_party(players: int) -> void:
	var devices: Array[int] = [Coop.KEYBOARD_DEVICE]
	for slot in range(1, players):
		devices.append(slot - 1)
	var characters: Array[String] = []
	Coop.configure(players, devices, characters)


# --- caso extremo -------------------------------------------------------------

func _fill() -> void:
	var build := _node("BuildStrip") as LoadoutStrip
	var bag := _node("BagStrip") as LoadoutStrip
	build.show_entries(_build_entries(build))
	bag.show_entries(_bag_entries())
	(_node("PowerUpRow") as PowerUpRow).show_entries(_powerup_entries())
	RunState.difficulty_changed.emit(1.15)
	get_tree().call_group("hud", "show_stage_tag", 11, 11)
	_raiders[0].points_changed.emit(123456)
	for raider: FakeRaider in _raiders:
		if raider.player_index > 0:
			raider.points_changed.emit(123456)
	get_tree().call_group("hud", "show_loot", "Vial de sangre",
			"Un objeto con una descripción larga para la tarjeta.", Color.WHITE, 0)


func _build_entries(strip: LoadoutStrip) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in 3:
		var weapon: Dictionary = WeaponCatalog.WEAPON_LIBRARY[i]
		entries.append({
			"glyph": LoadoutTile.catalog_glyph(weapon, String(weapon.id)),
			"library": LoadoutTile.ICON_LIBRARY_WEAPONS, "entry_id": String(weapon.id),
			"color": strip.evolved_weapon_color if i == 0 else strip.weapon_color,
			"corner": "★3" if i == 0 else "N10", "icon": String(weapon.get("icon", "")),
			"tip": String(weapon.get("display_name", weapon.id)),
		})
	for i in 3:
		var tome: Dictionary = Tome.TOME_LIBRARY[i]
		entries.append({
			"glyph": LoadoutTile.catalog_glyph(tome, String(tome.id)),
			"library": LoadoutTile.ICON_LIBRARY_TOMES, "entry_id": String(tome.id),
			"color": strip.tome_color, "corner": Tome.stack_label(10),
			"icon": String(tome.get("icon", "")), "row": tome,
			"tip": String(tome.get("display_name", tome.id)),
		})
	var pet: Dictionary = PetCatalog.PET_LIBRARY[0]
	entries.append({
		"glyph": String(pet.get("glyph", "??")),
		"library": LoadoutTile.ICON_LIBRARY_PETS, "entry_id": String(pet.id),
		"color": pet.get("color", Color.WHITE) as Color, "corner": "",
		"icon": String(pet.get("icon", "")), "tip": String(pet.get("display_name", pet.id)),
	})
	return entries


func _bag_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var library := ItemCatalog.ITEM_LIBRARY
	for i in BAG_ITEMS:
		var row: Dictionary = library[i % library.size()]
		entries.append({
			"glyph": LoadoutTile.catalog_glyph(row, String(row.id)),
			"library": LoadoutTile.ICON_LIBRARY_ITEMS,
			"entry_id": "%s_%d" % [row.id, i],
			"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			"corner": "x10" if i % 3 == 0 else "", "icon": String(row.get("icon", "")),
			"row": row, "tip": String(row.get("display_name", row.id)),
		})
	return entries


func _powerup_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in POWERUPS:
		var row: Dictionary = PowerUpCatalog.POWERUP_LIBRARY[i]
		entries.append({
			"glyph": String(row.get("glyph", "??")),
			"library": LoadoutTile.ICON_LIBRARY_POWERUPS, "entry_id": String(row.id),
			"color": row.get("color", Color.WHITE) as Color, "corner": "30s",
			"icon": String(row.get("icon", "")),
			"tip": String(row.get("display_name", row.id)),
		})
	return entries


# --- comprobaciones ----------------------------------------------------------

func _check(where: String, screen: Rect2) -> void:
	var rects: Dictionary[String, Rect2] = {}
	for node_name: String in PARTS:
		rects[node_name] = _rect(node_name)
	var minimaps := _node("ViewWidgets").find_children("*", "Minimap", false, false)
	for i in minimaps.size():
		rects["Minimap%d" % i] = (minimaps[i] as Control).get_global_rect()
	var bounds := screen.grow(SLACK)
	var names := rects.keys()
	for i in names.size():
		var rect := rects[names[i]]
		if not rect.has_area():
			if not EMPTY_OK.has(names[i]):
				_fail(where, "%s is not on screen" % names[i])
		elif not BLEEDS.has(names[i]) and not bounds.encloses(rect):
			_fail(where, "%s leaves the screen: %s" % [names[i], rect])
		for j in range(i + 1, names.size()):
			if _touch(rect, rects[names[j]]):
				_fail(where, "%s %s overlaps %s %s" % [names[i], rect, names[j],
						rects[names[j]]])
	var bag := _node("BagStrip") as LoadoutStrip
	if bag.get_child_count() != bag.max_tiles:
		_fail(where, "BagStrip shows %d tiles, cap is %d" % [bag.get_child_count(),
				bag.max_tiles])
	if not (_node("DifficultyChip") as Control).visible:
		_fail(where, "DifficultyChip hidden with difficulty set")


func _touch(a: Rect2, b: Rect2) -> bool:
	return a.has_area() and b.has_area() and a.grow(-SLACK).intersects(b)


## Milisegundos reales por frame con el HUD lleno, promediados.
func _measure() -> float:
	var start := Time.get_ticks_usec()
	await _frames(PERF_FRAMES)
	return float(Time.get_ticks_usec() - start) / 1000.0 / PERF_FRAMES


# --- utilidades ---------------------------------------------------------------

func _node(node_name: String) -> Node:
	return _hud.get_node("%" + node_name) if _hud.has_node("%" + node_name) \
			else _hud.find_child(node_name, true, false)


func _rect(node_name: String) -> Rect2:
	var control := _node(node_name) as Control
	if control == null or not control.is_visible_in_tree():
		return Rect2()
	return control.get_global_rect()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shoot(stem: String) -> void:
	var dir := OS.get_environment(SHOT_DIR_ENV).strip_edges()
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(stem + ".png"))


func _fail(where: String, message: String) -> void:
	_failed = true
	push_error("HudStressProbe: %s: %s" % [where, message])
