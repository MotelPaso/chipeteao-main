extends SceneTree
## Escribe el ÚNICO ícono provisional que usa la franja del HUD cuando una
## fila del catálogo todavía no tiene sprite propio:
##   res://assets/icons/placeholder.png  (64x64, casilla neutra con borde)
##
## Córrelo desde la raíz del proyecto y luego reimporta para que exista el
## .ctex:
##   godot --headless --path . -s res://scripts/tools/generate_placeholder_icon.gd
##   godot --headless --import
##
## Sin autoloads ni ningún class_name del proyecto, a propósito: un harness
## `-s` de SceneTree NO instancia autoloads, y cualquier cosa que tocara
## RunState/SaveData/Sfx/Pools abortaría antes del primer píxel. Hermano de
## generate_sfx.gd, mismo contrato: determinista, un recurso, se regenera a
## mano y se commitea.

const OUTPUT_PATH: String = "res://assets/icons/placeholder.png"
const SIZE: int = 64
## Grosor del borde en píxeles, y paso del rayado diagonal de "sin arte".
const BORDER: int = 3
const HATCH_STEP: int = 10

## Pizarra neutra que se lee bajo cualquier borde de rareza de la casilla
## sin competir con ninguno de los cuatro colores de rareza.
const FILL: Color = Color(0.16, 0.17, 0.22, 1.0)
const BORDER_COLOR: Color = Color(0.42, 0.45, 0.54, 1.0)
const HATCH_COLOR: Color = Color(0.24, 0.26, 0.32, 1.0)


func _init() -> void:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(FILL)
	# Primero el rayado diagonal, para que el borde se dibuje sobre sus puntas.
	for y in SIZE:
		for x in SIZE:
			if (x + y) % HATCH_STEP == 0:
				image.set_pixel(x, y, HATCH_COLOR)
	for y in SIZE:
		for x in SIZE:
			if x < BORDER or y < BORDER or x >= SIZE - BORDER or y >= SIZE - BORDER:
				image.set_pixel(x, y, BORDER_COLOR)
	var directory := OUTPUT_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("generate_placeholder_icon: save_png failed (%d)" % error)
	else:
		print("Placeholder icon written: %s" % OUTPUT_PATH)
	quit()
