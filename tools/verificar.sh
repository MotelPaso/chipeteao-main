#!/usr/bin/env bash
# Verificación headless del proyecto: import limpio + lint de catálogos +
# harness de UI + soak por arena + soak de etapa + soak de co-op.
# Uso: tools/verificar.sh [segundos_por_arena]   (por defecto 360)
#
# 360 s no es arbitrario: por debajo, el recorrido del harness no da tiempo a
# cruzar una arena de 240x240 y la puerta de cobertura no puede exigir nada.
# La corrida completa tarda ~40 min (3 x 360 s + 1 x 720 s + 1 x 360 s de
# co-op + el lint + el harness de UI + import).
#
# BONK_GAME_SEED fija el RNG del juego (cartas, spawns, scatter y por tanto
# el relieve). Sin él cada soak es un mundo distinto y cualquier comparación
# entre dos corridas mide ruido, no el cambio.
#
# GUARDADO (iteración 57): cada soak y cada harness recibe su PROPIO
# BONK_SAVE_PATH, borrado —con sus hermanos .bak y .tmp— antes de arrancar.
# Antes todos compartían user://soak_save.json, que no acumula meta en los
# soaks godmode (nunca terminan la partida) pero sí los contadores que
# SaveData.bump acredita durante la corrida (bestiario kills_<script>,
# used_weapon_<id>), y cualquier corrida mortal o de UI le doblaba encima
# esquirlas, misiones y desbloqueos. Borrar solo el .json no era un reset:
# load_from_disk cae al .bak.
#
# Falla (exit 1) si:
#   - el import, el lint, el harness de UI o algún soak reporta
#     errores/warnings de Godot
#   - el lint de catálogos no imprime CADA una de sus comprobaciones con
#     rows > 0, o el harness de UI no completa CADA uno de sus pasos
#   - una arena no llega al final del soak (se colgó o murió antes)
#   - un soak no ejercita los sistemas clave (cobertura): sin esto un soak
#     puede pasar "limpio" por no haber ejecutado nada.
#   - un soak GODMODE termina su partida (`Probe fog: skipped`): una
#     corrida inmortal no tiene por qué acabarse, y la puerta de niebla se
#     saltaría en silencio si no lo dijéramos aquí.
#   - el soak de ETAPA (iteración 49) no cruza de mapa, deja algo vivo al
#     cruzar, o pierde progreso al hacerlo.
#   - el soak de CO-OP (iteración 57) no arranca con dos raiders, no cruza
#     de etapa, ensucia un barrido o no reanima a nadie.
set -uo pipefail
cd "$(dirname "$0")/.."

SECS="${1:-360}"
FRAMES=$(( SECS * 60 ))
LOGDIR="${TMPDIR:-/tmp}/bonkraiders-verify"
mkdir -p "$LOGDIR"
FALLOS=0
INTERACCIONES=0

PATRON_ERROR='SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid get index|Invalid set index|Invalid access|null instance|Cannot call method|Trying to assign|USER ERROR|USER WARNING|Attempt to call|previously freed|nonexistent|Resource file not found|Failed to load'

# --- Guardado por corrida ---------------------------------------------------
# Devuelve la ruta de guardado de un soak, ya borrada junto a sus hermanos.
# El .bak importa: load_from_disk cae a él, así que borrar solo el .json
# deja la partida anterior intacta.
save_path_for() {
	local nombre="$1"
	local ruta="$LOGDIR/save_$nombre.json"
	rm -f "$ruta" "$ruta.bak" "$ruta.tmp"
	printf '%s' "$ruta"
}

# --- Reloj por fase ---------------------------------------------------------
# El costo real de cada soak depende del tamaño de la horda, y en co-op la
# horda escala por jugador: sin esta medida, "tarda ~40 min" es una
# suposición que envejece mal.
FASE_INICIO=$SECONDS
fase() {
	FASE_INICIO=$SECONDS
}
fase_fin() {
	printf '  (%d s)\n' "$(( SECONDS - FASE_INICIO ))"
}

# --- Listas fijas de líneas esperadas ---------------------------------------
# Se greppean UNA POR UNA, no por conteo: una comprobación que deja de
# ejecutarse desaparece del log sin ruido, y un conteo la daría por buena
# mientras otra se repite.
LINT_CHECKS=(ids_unique glyphs_unique paths_exist stat_ids character_weapons
	director_methods weapon_properties vendor_lucky_roulette_ids marker_labels)
UI_STEPS=(collection quests relics coop_count_reject unlock_confirm cards_all
	start_run pause_open settings_toggle pause_close extract retry done)

echo "== import =="
fase
IMPORT_LOG="$LOGDIR/import.log"
godot --headless --import >"$IMPORT_LOG" 2>&1
if grep -qE "$PATRON_ERROR" "$IMPORT_LOG"; then
	echo "  FALLO: el import reportó problemas"
	grep -nE "$PATRON_ERROR" "$IMPORT_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	echo "  ok"
fi
fase_fin

# --- Lint de catálogos (iteración 57) ---------------------------------------
# Las referencias cruzadas que ningún soak puede comprobar: una rota no
# revienta, simplemente no hace nada.
echo "== lint de catálogos =="
fase
LINT_LOG="$LOGDIR/catalog_lint.log"
BONK_SAVE_PATH="$(save_path_for lint)" \
	godot --headless --fixed-fps 60 --quit-after 600 \
	res://scenes/tests/CatalogLint.tscn >"$LINT_LOG" 2>&1
if grep -qE "$PATRON_ERROR" "$LINT_LOG"; then
	echo "  FALLO: el lint reportó problemas"
	grep -nE "$PATRON_ERROR" "$LINT_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	LINT_FALTAN=0
	for CHECK in "${LINT_CHECKS[@]}"; do
		if ! grep -qE "^Catalog lint: check $CHECK ok rows=[1-9][0-9]*$" "$LINT_LOG"; then
			echo "  FALLO: la comprobación '$CHECK' no pasó (o inspeccionó 0 filas)"
			LINT_FALTAN=$((LINT_FALTAN + 1))
		fi
	done
	if [ "$LINT_FALTAN" -ne 0 ]; then
		FALLOS=$((FALLOS + 1))
	else
		echo "  ok (${#LINT_CHECKS[@]} comprobaciones)"
	fi
fi
fase_fin

# --- Harness de UI (iteración 57) -------------------------------------------
# Siete de las nueve escenas de UI no las arrancaba nada. --quit-after es un
# techo de dos minutos: el harness se va solo mucho antes.
echo "== harness de UI =="
fase
UI_LOG="$LOGDIR/ui_probe.log"
BONK_SAVE_PATH="$(save_path_for ui_probe)" \
	godot --headless --fixed-fps 60 --quit-after 7200 \
	res://scenes/tests/UiProbe.tscn >"$UI_LOG" 2>&1
if grep -qE "$PATRON_ERROR" "$UI_LOG"; then
	echo "  FALLO: el harness de UI reportó problemas"
	grep -nE "$PATRON_ERROR" "$UI_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	UI_FALTAN=0
	for STEP in "${UI_STEPS[@]}"; do
		if ! grep -qF "UiProbe: step $STEP ok" "$UI_LOG"; then
			echo "  FALLO: el paso de UI '$STEP' no se completó"
			UI_FALTAN=$((UI_FALTAN + 1))
		fi
	done
	if ! grep -qE "^UiProbe: done steps=[0-9]+$" "$UI_LOG"; then
		echo "  FALLO: el harness de UI no llegó al final"
		UI_FALTAN=$((UI_FALTAN + 1))
	fi
	if [ "$UI_FALTAN" -ne 0 ]; then
		FALLOS=$((FALLOS + 1))
	else
		echo "  ok (${#UI_STEPS[@]} pasos)"
	fi
fi
fase_fin

for ARENA in HollowWoods AshDunes Gloomfen; do
	echo "== soak $ARENA (${SECS}s de partida) =="
	fase
	LOG="$LOGDIR/soak_$ARENA.log"
	BONK_ARENA="res://scenes/world/$ARENA.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
		BONK_GAME_SEED=4242 BONK_SAVE_PATH="$(save_path_for "$ARENA")" \
		godot --headless --fixed-fps 60 --quit-after "$FRAMES" \
		res://scenes/tests/ArenaProbe.tscn >"$LOG" 2>&1

	if grep -qE "$PATRON_ERROR" "$LOG"; then
		echo "  FALLO: errores en tiempo de ejecución"
		grep -nE "$PATRON_ERROR" "$LOG" | head -30
		FALLOS=$((FALLOS + 1))
		fase_fin
		continue
	fi

	# El harness imprime "frame N ..." cada 120 frames; la última debe
	# alcanzar el total pedido, si no la corrida murió o se colgó antes.
	REPORTES=$(grep -c '^frame ' "$LOG")
	ESPERADO=$(( FRAMES / 120 ))
	if [ "$REPORTES" -lt "$ESPERADO" ]; then
		echo "  FALLO: terminó antes de tiempo ($REPORTES/$ESPERADO reportes)"
		tail -15 "$LOG"
		FALLOS=$((FALLOS + 1))
		continue
	fi

	# Una corrida GODMODE no se acaba. Si el probe saltó la puerta de
	# niebla por partida terminada, el raider inmortal murió: eso es un
	# fallo, no una exención.
	if grep -q '^Probe fog: skipped' "$LOG"; then
		echo "  FALLO: la partida godmode terminó sola"
		grep -n '^Probe fog: skipped\|^Run ended: ' "$LOG" | head -3
		FALLOS=$((FALLOS + 1))
		continue
	fi

	NIVEL=$(grep '^frame ' "$LOG" | tail -1 | sed -n 's/.*level=\([0-9]\{1,\}\).*/\1/p')
	if [ -z "$NIVEL" ]; then
		echo "  FALLO: no se pudo leer el nivel del log (¿cambió el formato de ArenaProbe?)"
		FALLOS=$((FALLOS + 1))
		continue
	fi
	CHESTS=$(grep -c 'Chest opened:' "$LOG")
	ALTARES=$(grep -c 'Altar charged:' "$LOG")
	# "Portal used: exit" es un cambio de etapa, no un teletransporte
	# dentro del mapa: no cuenta como interactuable ejercitado.
	PORTALES=$(grep 'Portal used:' "$LOG" | grep -vc 'Portal used: exit')
	echo "  nivel=$NIVEL cofres=$CHESTS altares=$ALTARES portales=$PORTALES"
	fase_fin

	# Cobertura: un soak que no sube de nivel ni toca un interactuable no
	# probó gran cosa, aunque no haya reventado.
	if [ "$NIVEL" -lt 3 ]; then
		echo "  FALLO (cobertura): el raider no pasó de nivel $NIVEL — ¿el arma no hace daño?"
		FALLOS=$((FALLOS + 1))
	fi
	INTERACCIONES=$(( INTERACCIONES + CHESTS + ALTARES + PORTALES ))
done

# --- Soak de etapa (iteración 49) ---------------------------------------
# El cuarto soak es el único que cruza de mapa: con BONK_STAGE_FAST=1 la
# etapa se supera a los 60 s sin jefe, el harness se queda 70 s más (para
# que la rampa pseudo-infinita registre un minuto) y cruza el portal.
# Queda FUERA de la cuenta de interactuables a propósito: mide el cambio
# de etapa, no la cobertura de un mapa.
# Este soak necesita el DOBLE de reloj que los otros: 60 s hasta la puerta,
# 70 s de espera deliberada para que la rampa pseudo-infinita registre un
# minuto, y después cruzar el mapa hasta un portal que aparece a 40 m o más.
# Con 240 s el recorrido llega justo y falla por varianza (el orden de
# contactos de la física diverge aunque el mundo sea reproducible).
STAGE_SECS=$(( SECS * 2 ))
STAGE_FRAMES=$(( STAGE_SECS * 60 ))
echo "== soak etapa (HollowWoods, BONK_STAGE_FAST, ${STAGE_SECS}s de partida) =="
fase
STAGE_LOG="$LOGDIR/soak_stage.log"
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
	BONK_GAME_SEED=4242 BONK_STAGE_FAST=1 BONK_SAVE_PATH="$(save_path_for stage)" \
	godot --headless --fixed-fps 60 --quit-after "$STAGE_FRAMES" \
	res://scenes/tests/ArenaProbe.tscn >"$STAGE_LOG" 2>&1

if grep -qE "$PATRON_ERROR" "$STAGE_LOG"; then
	echo "  FALLO: errores en tiempo de ejecución"
	grep -nE "$PATRON_ERROR" "$STAGE_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	AVANCES=$(grep -c '^Stage advanced: ' "$STAGE_LOG")
	SWEEPS_SUCIOS=$(grep '^Stage sweep: ' "$STAGE_LOG" | grep -cv 'enemies=0 gems=0 orbs=0 chests=0 altars=0 beacons=0 pickups=0 boxes=0 vendors=0 possessed=0')
	CARRIES=$(grep -c '^Stage carry: ' "$STAGE_LOG")
	# Las líneas van en PARES (una antes del cruce y otra después). Cada
	# par tiene que coincidir consigo mismo; entre un cruce y el siguiente
	# el equipo sí crece, así que compararlas todas contra todas sería
	# exigir que la partida no avance.
	PARES_ROTOS=$(grep '^Stage carry: ' "$STAGE_LOG" \
		| awk 'NR % 2 == 1 { prev = $0; next } { if ($0 != prev) bad++ } END { print bad + 0 }')
	CIELO_TRAS_AVANCE=$(sed -n '/^Stage advanced: /,$p' "$STAGE_LOG" | grep -c '^Sky event: ')
	echo "  avances=$AVANCES sweeps_sucios=$SWEEPS_SUCIOS carries=$CARRIES pares_rotos=$PARES_ROTOS cielo_tras_avance=$CIELO_TRAS_AVANCE"
	fase_fin
	if grep -q '^Probe fog: skipped' "$STAGE_LOG"; then
		echo "  FALLO: la partida godmode terminó sola"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q 'Exit portal opened' "$STAGE_LOG"; then
		echo "  FALLO: la etapa nunca abrió su portal de salida"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q '^Stage advanced: 1 -> 2 (ash_dunes)' "$STAGE_LOG"; then
		echo "  FALLO: no se cruzó de Bosque Hueco a Dunas de Ceniza"
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$SWEEPS_SUCIOS" -ne 0 ]; then
		echo "  FALLO: un cambio de etapa dejó objetos vivos"
		grep '^Stage sweep: ' "$STAGE_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
	# Dos líneas por avance (antes y después) e idénticas entre sí: si el
	# equipo perdiera algo al cruzar, el par no coincidiría.
	if [ "$CARRIES" -lt 2 ] || [ $((CARRIES % 2)) -ne 0 ] || [ "$PARES_ROTOS" -ne 0 ]; then
		echo "  FALLO: el equipo no cruzó intacto ($CARRIES línea(s), $PARES_ROTOS par(es) roto(s))"
		grep '^Stage carry: ' "$STAGE_LOG" | head -6
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -qE '^Stage carry: level=([2-9]|[0-9]{2,}) weapons=[1-9]' "$STAGE_LOG"; then
		echo "  FALLO: el equipo cruzó sin nivel ni armas"
		FALLOS=$((FALLOS + 1))
	fi
	# El director sobrevive al cambio de mapa: si no volviera a cachear
	# el Sol de la arena nueva, este evento de cielo no saldría.
	if [ "$CIELO_TRAS_AVANCE" -eq 0 ]; then
		echo "  FALLO: ningún evento de cielo tras el cambio de etapa"
		FALLOS=$((FALLOS + 1))
	fi
fi

# --- Soak de co-op (iteración 57) ---------------------------------------
# El quinto soak es el único con DOS raiders: prueba el reparto de party
# (RunSystems._spawn_party lee Coop antes de instanciar), la pantalla
# dividida, el cruce de etapa con dos cuerpos y —lo que ningún soak solo
# puede alcanzar— el ciclo derribo/reanimación. BONK_DOWN_NOW derriba al
# slot 1 a propósito: esperar a que la horda lo elija no es una prueba.
# Fuera de la cuenta de interactuables, como el de etapa.
echo "== soak co-op (HollowWoods, 2 raiders, ${SECS}s de partida) =="
fase
COOP_LOG="$LOGDIR/soak_coop.log"
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_PLAYERS=2 BONK_STAGE_FAST=1 \
	BONK_GODMODE=1 BONK_DOWN_NOW=45 BONK_SEED=4242 BONK_GAME_SEED=4242 \
	BONK_SAVE_PATH="$(save_path_for coop)" \
	godot --headless --fixed-fps 60 --quit-after "$FRAMES" \
	res://scenes/tests/ArenaProbe.tscn >"$COOP_LOG" 2>&1

if grep -qE "$PATRON_ERROR" "$COOP_LOG"; then
	echo "  FALLO: errores en tiempo de ejecución"
	grep -nE "$PATRON_ERROR" "$COOP_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	COOP_REPORTES=$(grep -c '^frame ' "$COOP_LOG")
	COOP_ESPERADO=$(( FRAMES / 120 ))
	COOP_AVANCES=$(grep -c '^Stage advanced: ' "$COOP_LOG")
	COOP_REVIVES=$(grep -c '^Player revived: ' "$COOP_LOG")
	COOP_SUCIOS=$(grep '^Stage sweep: ' "$COOP_LOG" | grep -cv 'enemies=0 gems=0 orbs=0 chests=0 altars=0 beacons=0 pickups=0 boxes=0 vendors=0 possessed=0')
	echo "  avances=$COOP_AVANCES reanimaciones=$COOP_REVIVES sweeps_sucios=$COOP_SUCIOS"
	fase_fin
	if [ "$COOP_REPORTES" -lt "$COOP_ESPERADO" ]; then
		echo "  FALLO: terminó antes de tiempo ($COOP_REPORTES/$COOP_ESPERADO reportes)"
		tail -15 "$COOP_LOG"
		FALLOS=$((FALLOS + 1))
	fi
	# Contado sobre los GRUPOS después de _spawn_party, no sobre el
	# interruptor: una party que salió corta es justo lo que esto detecta.
	if ! grep -q '^ArenaProbe: players=2 ' "$COOP_LOG"; then
		echo "  FALLO: la party no arrancó con dos raiders"
		grep -n '^ArenaProbe: players=' "$COOP_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$COOP_AVANCES" -lt 1 ]; then
		echo "  FALLO: la party de dos no cruzó de etapa"
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$COOP_SUCIOS" -ne 0 ]; then
		echo "  FALLO: un cambio de etapa en co-op dejó objetos vivos"
		grep '^Stage sweep: ' "$COOP_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$COOP_REVIVES" -lt 1 ]; then
		echo "  FALLO: nadie reanimó a nadie (¿BONK_DOWN_NOW no derribó, o el rescate no llega?)"
		grep -n '^Party: \|forced down' "$COOP_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
	if grep -q '^Probe fog: skipped' "$COOP_LOG"; then
		echo "  FALLO: la partida godmode terminó sola"
		FALLOS=$((FALLOS + 1))
	fi
fi

# La cobertura de interactuables se mide SUMANDO las tres arenas, no por
# arena: el recorrido es aleatorio y la máscara irregular puede dejar una
# arena concreta muy fragmentada (hasta mask_min_open_fraction), así que
# exigirlo arena por arena falla por varianza legítima y entrena a ignorar
# la puerta de calidad. Que ninguna de las tres resuelva nada sí es señal.
if [ "$SECS" -ge 240 ] && [ "$INTERACCIONES" -eq 0 ]; then
	echo "FALLO (cobertura): ningún interactuable se resolvió en NINGUNA arena"
	FALLOS=$((FALLOS + 1))
fi

echo
echo "Tiempo total: $(( SECONDS / 60 )) min $(( SECONDS % 60 )) s"
if [ "$FALLOS" -eq 0 ]; then
	echo "VERIFICACIÓN OK — logs en $LOGDIR"
	exit 0
fi
echo "VERIFICACIÓN FALLIDA: $FALLOS problema(s) — logs en $LOGDIR"
exit 1
