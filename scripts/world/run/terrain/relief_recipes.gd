class_name ReliefRecipes
extends RefCounted
## Las RECETAS del relieve por zonas: qué composición tiene el mapa de una
## etapa. Cada una tiene su pieza propia, que ninguna otra arma:
##
##   massif  La Montaña Escalonada: macizo, segundo nivel y cumbre con el
##           Árbol Hueco; el cañón la abraza con un puente y la cascada baja
##           del macizo al río (ReliefPlanner).
##   river   El Gran Río: un río que cruza el mapa con varios puentes y vados
##           entre ellos; puede nacer en la cascada de una meseta-manantial
##           (RecipeRiver).
##   twin    El Paso de los Dos Montes: dos montañas de dos niveles
##           enfrentadas, el equipo en el valle entre ellas y el camino
##           antiguo atravesando el paso (RecipeTwin).
##   lake    El Lago de la Isla: un lago hundido con una isla en el medio que
##           lleva el Árbol Hueco, y un puente de la orilla a la isla; puede
##           tener una cascada que cae al lago (RecipeLake).
##
## La receta sale de la semilla de partida con su propio RNG (esta sal) y los
## pesos de ReliefSettings (grupo «Recetas»); las piezas opcionales de cada
## receta (el manantial del río, la cascada del lago, el camino), de otro RNG
## con otra sal. Ninguno saca números del trazado ni de la partida.
## BONK_RELIEF_RECIPE=<id> fuerza una receta y <id>:reserve su trazado de
## reserva; un id que no existe es un error. Cada receta declara su pieza
## propia en own_pieces: el harness la exige en la línea `Relief pieces:`.

## Las recetas, en orden de sorteo. Son llaves internas: no se renombran.
const IDS: Array[StringName] = [&"massif", &"river", &"twin", &"lake"]
## Variable de entorno del harness que fuerza una receta.
const FORCE_ENV := "BONK_RELIEF_RECIPE"
## Sufijo que fuerza, además, el trazado de reserva de esa receta.
const RESERVE_SUFFIX := ":reserve"
## Sales que separan el sorteo de la receta y el de sus piezas opcionales de
## los otros RNG sembrados con la misma semilla.
const SEED_SALT: int = 0x52435045
const PIECES_SALT: int = 0x50434553


## La receta de la etapa: {id, reserve}. `reserve` es true si el harness
## pidió el trazado de reserva.
static func choose(settings: ReliefSettings, run_seed: int) -> Dictionary:
	var forced := OS.get_environment(FORCE_ENV).strip_edges()
	if not forced.is_empty():
		var id := StringName(forced.trim_suffix(RESERVE_SUFFIX))
		if IDS.has(id):
			return {"id": id, "reserve": forced.ends_with(RESERVE_SUFFIX)}
		push_error("ReliefRecipes: unknown %s '%s', expected one of %s (with %s for the reserve layout)"
				% [FORCE_ENV, forced, IDS, RESERVE_SUFFIX])
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ SEED_SALT
	var total := 0.0
	for id: StringName in IDS:
		total += maxf(weight(settings, id), 0.0)
	if total <= 0.0:
		return {"id": IDS[0], "reserve": false}
	var pick := rng.randf() * total
	for id: StringName in IDS:
		pick -= maxf(weight(settings, id), 0.0)
		if pick < 0.0:
			return {"id": id, "reserve": false}
	return {"id": IDS[IDS.size() - 1], "reserve": false}


## El peso de la receta `id` en `settings`.
static func weight(settings: ReliefSettings, id: StringName) -> float:
	match id:
		&"river":
			return settings.river_weight
		&"twin":
			return settings.twin_weight
		&"lake":
			return settings.lake_weight
	return settings.massif_weight


## Las piezas opcionales de la receta `id`, sorteadas con su propio RNG: el
## manantial del río, la cascada del lago y el camino (que el paso de los dos
## montes lleva siempre).
static func options(settings: ReliefSettings, id: StringName, run_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ PIECES_SALT
	var picked := {}
	match id:
		&"river":
			picked["springhead"] = rng.randf() < settings.springhead_chance
		&"lake":
			picked["falls"] = rng.randf() < settings.lake_falls_chance
	if id != &"twin":
		picked["road"] = rng.randf() < settings.road_chance
	return picked


## La pieza propia de la receta `id`, la que ninguna otra arma: las llaves de
## la línea `Relief pieces:` (ReliefPieces) con lo mínimo que tiene que haber.
## Vacío si la receta no la declara (el harness lo da por fallo: una receta
## nueva declara aquí la suya).
static func own_pieces(id: StringName) -> Dictionary:
	match id:
		&"massif":
			return {"stepped_mountain": 1}
		&"river":
			return {"ravine": 1}
		&"twin":
			return {"twin_mounts": 2}
		&"lake":
			return {"lake": 1, "island": 1}
	return {}


## Un trazado entero de la receta de `layout`; false si una pieza
## obligatoria no cupo. Con `calm` es el de reserva.
static func try_plan(layout: ReliefLayout, rng: RandomNumberGenerator, calm: bool) -> bool:
	match layout.recipe:
		&"river":
			return RecipeRiver.try_plan(layout, rng, calm)
		&"twin":
			return RecipeTwin.try_plan(layout, rng, calm)
		&"lake":
			return RecipeLake.try_plan(layout, rng, calm)
	return ReliefPlanner.try_massif(layout, rng, calm)
