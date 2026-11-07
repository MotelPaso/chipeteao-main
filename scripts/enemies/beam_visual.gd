class_name BeamVisual
extends MeshInstance3D
## Segmento de rayo: una caja unitaria estirada entre dos puntos del mundo,
## sin sombreado y emisiva (material en BeamVisual.tscn). Se usa como instancia de
## BeamVisual.tscn dentro de la escena de cada enemigo (líneas de aviso y
## láseres del Sunspitter y del barrido del Sarcognath), y cada instancia
## guarda su color, su grosor y su zumbido. Es top_level: cuelga del enemigo
## y se libera con él, pero sus extremos son coordenadas globales. Solo es
## visual: el raycast, el impacto y el daño los resuelve quien lo usa.

@export_group("Aspecto")
## Color del rayo y de su emisión; la opacidad (0.8) y el brillo (2.2) salen del material de BeamVisual.tscn.
@export var color: Color = Color.WHITE
## Grosor en metros cuando span() no recibe uno.
@export var default_thickness: float = 0.1

@export_group("Sonido")
## Bucle de Sfx que suena mientras el rayo dispara (vacío = mudo); ver start_hum().
@export var hum_loop: StringName = &""

var _hum_held: bool = false


func _ready() -> void:
	# Copia propia del material: los dos rayos de un enemigo tienen colores distintos.
	var material := material_override as StandardMaterial3D
	if material == null:
		return
	material = material.duplicate() as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, material.albedo_color.a)
	material.emission = color
	material_override = material


func _exit_tree() -> void:
	# Liberado a mitad del rayo (cambio de mapa, cierre, recortes del tope):
	# nunca dejar una referencia del zumbido colgada.
	_release_hum()


## Muestra el rayo de `from` a `to`; thickness < 0 usa default_thickness.
## Se llama cada frame mientras un extremo se mueve.
func span(from: Vector3, to: Vector3, thickness: float = -1.0) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		visible = false
		return
	visible = true
	var girth := default_thickness if thickness < 0.0 else thickness
	var direction := (to - from) / length
	# Los rayos son casi horizontales, pero safe_up cubre el caso colineal con
	# UP de Basis.looking_at (el mismo umbral que toda puntería del juego).
	var look := Basis.looking_at(direction, WeaponBase.safe_up(direction))
	global_transform = Transform3D(
			look * Basis.from_scale(Vector3(girth, girth, length)),
			(from + to) * 0.5)


## Oculta el rayo y corta su zumbido.
func clear() -> void:
	visible = false
	_release_hum()


## Empieza el zumbido de hum_loop. Sfx cuenta referencias por id, así que
## cada rayo toma a lo sumo una y la suelta en clear() o al salir del árbol.
func start_hum() -> void:
	if _hum_held or hum_loop.is_empty():
		return
	_hum_held = true
	Sfx.acquire_loop(hum_loop)


func _release_hum() -> void:
	if not _hum_held:
		return
	_hum_held = false
	Sfx.release_loop(hum_loop)
