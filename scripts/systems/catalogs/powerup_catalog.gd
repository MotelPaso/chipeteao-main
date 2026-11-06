class_name PowerUpCatalog
extends RefCounted
## Catálogo estático de power-ups temporales: los que sueltan las bajas, da
## el manantial y vende el vendedor de power-ups. A diferencia de tomos y
## objetos, un power-up es RUIDOSO y BREVE — unos segundos en que la partida
## se juega distinto —, así que la lista es corta y cada fila cambia algo que
## se siente sin leer un número.
##
## Edita aquí: cada fila es un power-up.
##   id:            identificador (no se muestra; lo usan el log y los
##                  interruptores de prueba).
##   display_name:  texto para el jugador.
##   description:   una línea, texto para el jugador.
##   duration:      segundos, antes del duration_multiplier del raider.
##   weight:        peso de la tirada. La estrella es ~2% del total a propósito.
##   color:         tinte de la gema en el suelo, la casilla del HUD y el aviso.
##   glyph:         dos letras para el arte provisional (únicas entre los
##                  glifos de armas, tomos, objetos y power-ups).
##   icon:          OPCIONAL, textura explícita; si falta se usa
##                  res://assets/icons/powerups/<id>.png.
##   effects:       [{stat, amount}] que recibe PlayerStats.add_timed_boon.
##   kind:          comportamiento que resuelve PowerUps, una rama por tipo.
##
## Casi todas las filas son una cosa u otra a propósito: una fila de puros
## `effects` no necesita código (el canal de boons temporales ya existe) y
## una fila con `kind` tiene exactamente una rama en PowerUps. Dos filas
## llevan ambas cosas: el robo de vida del vampiro es una stat normal junto a
## su comportamiento por baja, y la estrella tiene kind y ningún efecto
## porque ES todas las demás filas a la vez.

const POWERUP_LIBRARY: Array[Dictionary] = [
	{
		"id": "haste", "display_name": "Celeridad total",
		"description": "Corres y atacas mucho más rápido.",
		"duration": 10.0, "weight": 1.0, "glyph": "VT",
		"color": Color(0.45, 0.95, 1.0),
		"effects": [{"stat": "move_speed", "amount": 100.0},
				{"stat": "cooldown", "amount": 40.0}],
	},
	{
		"id": "might", "display_name": "Furia",
		"description": "50% mas daño en todas tus armas!",
		"duration": 10.0, "weight": 1.0, "glyph": "FR",
		"color": Color(1.0, 0.4, 0.25),
		"effects": [{"stat": "damage", "amount": 50.0}],
	},
	{
		"id": "xp", "display_name": "Sabiduría brígida",
		"description": "Cada gema vale mucho más.",
		"duration": 10.0, "weight": 1.0, "glyph": "SB",
		"color": Color(0.55, 0.95, 0.55),
		"effects": [{"stat": "xp_gain", "amount": 150.0}],
	},
	{
		"id": "gold", "display_name": "Fiebre del oro",
		"description": "Cada baja paga el doble de puntos.",
		"duration": 10.0, "weight": 0.9, "glyph": "OR",
		"color": Color(1.0, 0.82, 0.3), "kind": "gold",
	},
	{
		"id": "reflect", "display_name": "Reflejo",
		"description": "Todo el daño que recibes vuelve a quien te lo hizo.",
		"duration": 10.0, "weight": 0.8, "glyph": "RJ",
		"color": Color(0.75, 0.55, 1.0), "kind": "reflect",
	},
	{
		"id": "vampire", "display_name": "Modo vampiro",
		"description": "Robas vida y cada baja te sube el HP máx. para siempre.",
		"duration": 5.0, "weight": 0.8, "glyph": "VP",
		"color": Color(0.85, 0.15, 0.35), "kind": "vampire",
		# El robo de vida es un boon temporal normal; solo el HP permanente
		# por baja necesita la rama de comportamiento.
		"effects": [{"stat": "lifesteal", "amount": 10.0}],
	},
	{
		"id": "flight", "display_name": "Vuelo",
		"description": "Mantén el salto para volar sobre el mapa.",
		"duration": 20.0, "weight": 0.8, "glyph": "VU",
		"color": Color(0.6, 0.85, 1.0), "kind": "flight",
	},
	{
		"id": "immortal", "display_name": "Inmortalidad",
		"description": "Nada te hace daño.",
		"duration": 10.0, "weight": 0.7, "glyph": "IN",
		"color": Color(1.0, 0.95, 0.7), "kind": "immortal",
	},
	{
		"id": "time_stop", "display_name": "Tiempo detenido",
		"description": "La horda se congela; tú no.",
		"duration": 10.0, "weight": 0.5, "glyph": "TD",
		"color": Color(0.7, 0.9, 1.0), "kind": "time_stop",
	},
	{
		# Más corta que el resto PORQUE es todas a la vez: unos pocos
		# segundos de todo se leen como premio gordo; más, como el estado
		# normal de la partida.
		"id": "star", "display_name": "Estrella",
		"description": "Todos los power-ups a la vez, durante poco.",
		"duration": 5.0, "weight": 0.15, "glyph": "ES",
		"color": Color(1.0, 0.9, 0.35), "kind": "star",
	},
]

## Índice id -> fila, construido al primer uso (ver CatalogIndex).
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(powerup_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(POWERUP_LIBRARY)
	return _by_id.get(powerup_id, {})


## Tirada ponderada. `exclude_star` es lo NORMAL para toda fuente que no sea
## el avistamiento de la estrella: la estrella se encuentra rondando el mapa,
## no la da una baja ni un manantial.
static func roll_id(exclude_star: bool = true) -> String:
	var total := 0.0
	for row: Dictionary in POWERUP_LIBRARY:
		if exclude_star and String(row.get("kind", "")) == "star":
			continue
		total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in POWERUP_LIBRARY:
		if exclude_star and String(row.get("kind", "")) == "star":
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return String(POWERUP_LIBRARY[0].id)


## Cada fila que enciende la estrella: todas menos la estrella misma. Lo lee
## PowerUps.apply(); una fila nueva se suma a la estrella sola.
static func star_components() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in POWERUP_LIBRARY:
		if String(row.get("kind", "")) != "star":
			rows.append(row)
	return rows


static func color_of(powerup_id: String) -> Color:
	var row := by_id(powerup_id)
	return row.get("color", Color.WHITE) if not row.is_empty() else Color.WHITE


static func display_name_of(powerup_id: String) -> String:
	var row := by_id(powerup_id)
	return String(row.get("display_name", powerup_id))
