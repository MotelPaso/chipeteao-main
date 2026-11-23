class_name ItemIcons
extends RefCounted
## Icono de un objeto o de un tomo del catálogo, para la Colección. Un objeto
## con comportamiento especial (`kind`: imán, veneno, arañas…) lleva un SVG
## propio de assets/ui/icons/items/; los demás usan el icono de la estadística
## que suben (StatIcons). Nunca falla: sin icono propio ni efectos devuelve el
## icono de respaldo de StatIcons.
##
## Es estático y nunca va en una escena: edita los valores aquí.

## Carpeta de los SVG de los objetos especiales.
const ICON_DIR := "res://assets/ui/icons/items/"
## Edita aquí: `kind` de ItemCatalog -> archivo dentro de ICON_DIR.
const KIND_FILES: Dictionary[String, String] = {
	"magnet": "kind_magnet.svg",
	"poison_on_hit": "kind_poison_on_hit.svg",
	"spiders": "kind_spiders.svg",
	"saiyan": "kind_saiyan.svg",
	"demonic_boost": "kind_demonic_boost.svg",
	"charge_boost": "kind_charge_boost.svg",
	"portal_recharge": "kind_portal_recharge.svg",
}

## Texturas ya cargadas, por nombre de archivo.
static var _cache: Dictionary[String, Texture2D] = {}


## El icono de esa fila de ItemCatalog o de Tome.TOME_LIBRARY.
static func texture(row: Dictionary) -> Texture2D:
	# Un `icon` en la fila (ruta res:// del SVG) manda sobre todo.
	var icon_path := String(row.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path, "Texture2D"):
		return load(icon_path) as Texture2D
	var kind := String(row.get("kind", ""))
	if KIND_FILES.has(kind):
		var own := _load(KIND_FILES[kind])
		if own != null:
			return own
	var stats := StatIcons.main_stats(row.get("effects", []), 1)
	return StatIcons.texture(stats[0] if not stats.is_empty() else "")


static func _load(file_name: String) -> Texture2D:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := ICON_DIR + file_name
	var icon: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		icon = load(path) as Texture2D
	_cache[file_name] = icon
	return icon
