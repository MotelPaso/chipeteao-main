#!/usr/bin/env bash
# Verificación headless del proyecto: import limpio + lint de catálogos +
# harness de UI + harness del selector + soak por arena + soak de etapa +
# soak de co-op + soak del jefe de etapa (Mythos) + soak del minijefe (la
# Langosta Azul).
# Uso: tools/verificar.sh [segundos_por_arena]   (por defecto 360)
#
# 360 s no es arbitrario: por debajo, el recorrido del harness no da tiempo a
# cruzar una arena de 240x240 y la puerta de cobertura no puede exigir nada.
# La corrida completa tarda ~45 min (3 x 360 s + 1 x 720 s + 1 x 360 s de
# co-op + 1 x 450 s del jefe de etapa + 1 x 270 s del minijefe + el lint + el
# harness de UI + import).
#
# BONK_GAME_SEED fija el RNG del juego (cartas, spawns, scatter y por tanto
# el relieve). Sin él cada soak es un mundo distinto y cualquier comparación
# entre dos corridas mide ruido, no el cambio.
#
# GUARDADO: cada soak y cada harness recibe su PROPIO BONK_SAVE_PATH,
# borrado —con sus hermanos .bak y .tmp— antes de arrancar. Un guardado
# compartido acumularía los contadores que SaveData.bump acredita durante la
# corrida (bestiario kills_<script>, used_weapon_<id>) y, desde una corrida
# mortal o de UI, esquirlas, misiones y desbloqueos. Se borra también el
# .bak porque load_from_disk cae a él cuando falta el .json.
#
# Falla (exit 1) si:
#   - el import, el lint, el harness de UI, el del selector o algún soak
#     reporta errores/warnings de Godot
#   - el lint de catálogos no imprime CADA una de sus comprobaciones con
#     rows > 0, o el harness de UI no completa CADA uno de sus pasos
#   - el harness del selector no aprueba CADA tamaño de ventana (layout sin
#     cortes y navegación con control completa)
#   - una arena no llega al final del soak (se colgó o murió antes)
#   - un soak no ejercita los sistemas clave (cobertura): sin esto un soak
#     puede pasar "limpio" por no haber ejecutado nada.
#   - un soak GODMODE termina su partida (`Probe fog: skipped`): una
#     corrida inmortal no tiene por qué acabarse, y la puerta de niebla se
#     saltaría en silencio si no lo dijéramos aquí.
#   - el soak de ETAPA no cruza de mapa, deja algo vivo al
#     cruzar, o pierde progreso al hacerlo.
#   - el soak de CO-OP no arranca con dos raiders, no cruza
#     de etapa, ensucia un barrido o no reanima a nadie.
#   - el soak del JEFE DE ETAPA no ve llegar a Mythos, la calma no congela
#     el mundo, no renace, su muerte no sale exactamente una vez, o no abre
#     la puerta, el portal y el cruce de etapa.
#   - una etapa con RELIEVE POR ZONAS (el Bosque Hueco) no imprime sus
#     barridos, alguno no da cero, la pendiente pasa de su cota, o el bot
#     del soak del bosque no pisa una zona elevada ni cruza un puente.
#   - el soak del MINIJEFE no ve llegar a la Langosta Azul, su entrada no
#     congela el mundo o no devuelve la pantalla, la pelea no empieza y
#     termina exactamente una vez, o 5 s después de morir queda algo suyo.

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

# --- Tope de cofres de élite ------------------------------------------------
# Cada soak imprime `Probe bounty chests: max=N cap=M` al salir. Falla si la
# línea falta o si hubo más cofres de élite SIN ABRIR que el tope a la vez.
# El conteo no pasa por el tope (cuenta los cofres que hay), así que quitar
# el tope se ve en cuanto un soak deja caer más de M, lo que no pasa en
# toda corrida: la cantidad de cofres varía mucho de una a otra.
chequear_tope_cofres() {
	local log="$1"
	local tope
	tope=$(sed -n 's/^Probe bounty chests: max=\([0-9]\{1,\}\) cap=\([0-9]\{1,\}\)$/\1 \2/p' "$log")
	if [ -z "$tope" ]; then
		echo "  FALLO: falta la línea 'Probe bounty chests:' del harness"
		FALLOS=$((FALLOS + 1))
	elif [ "${tope% *}" -gt "${tope#* }" ]; then
		echo "  FALLO: max=${tope% *} cap=${tope#* } — más cofres de élite sin abrir que el tope"
		FALLOS=$((FALLOS + 1))
	fi
}

# --- Relieve por zonas ------------------------------------------------------
# Toda etapa en una arena con relieve por zonas (hoy, el Bosque Hueco)
# imprime los barridos `Relief sweep:` de relief_sweeps.gd. Falla si falta
# alguno, si un conteo no da cero en CUALQUIERA de sus líneas (el soak de
# etapa vuelve al bosque con otro trazado), si la pendiente p95 del suelo
# abierto pasa de su cota, si una celda alcanzable junto al muro se aparta
# del nivel del borde (rim), si el suelo de afuera del muro no es la malla
# del Terrain o deja costura (edge) o si queda una malla que el infierno no
# quemaría. Con "paseo" exige además la colocación a los 120 s y que el bot
# haya pisado una zona elevada y cruzado un puente.
#
# La cota de pendiente es la p95 del suelo de antes del relieve (12.76
# grados, semilla 4242) más 5. No se sube para hacer pasar un cambio.
RELIEVE_PENDIENTE_MAX="17.76"
RELIEVE_BARRIDOS=("gap faces=" "raider open=" "horde open=" "placement at=start"
	"slope p95=" "rim band=" "edge " "hell skipped=")
chequear_relieve() {
	local log="$1"
	local paseo="${2:-}"
	local mal=0
	local clave
	for clave in "${RELIEVE_BARRIDOS[@]}"; do
		if ! grep -q "^Relief sweep: $clave" "$log"; then
			echo "  FALLO (relieve): falta el barrido '$clave'"
			mal=1
		fi
	done
	if grep '^Relief sweep: gap ' "$log" | grep -qv ' faces=0 '; then
		echo "  FALLO (relieve): hay caras tocables entre 45 y 60 grados"
		grep -n '^Relief sweep\( detail\)\{0,1\}: gap ' "$log" | head -6
		mal=1
	fi
	if grep '^Relief sweep: \(raider\|horde\) ' "$log" | grep -qv ' unreachable=0 no_return=0$'; then
		echo "  FALLO (relieve): hay suelo abierto que el raider o la horda no alcanzan"
		grep -n '^Relief sweep\( detail\)\{0,1\}: \(raider\|horde\) ' "$log" | head -8
		mal=1
	fi
	if grep '^Relief sweep: placement ' "$log" \
		| grep -qv ' on_relief=0 misplaced=0 raider_unreachable=0 horde_unreachable=0 crowding=0$'; then
		echo "  FALLO (relieve): algo quedó mal colocado"
		grep -n '^Relief sweep\( detail\)\{0,1\}: placement ' "$log" | head -10
		mal=1
	fi
	if grep '^Relief sweep: rim ' "$log" | grep -qv ' off_level=0 '; then
		echo "  FALLO (relieve): hay suelo alcanzable junto al muro fuera del nivel del borde"
		grep -n '^Relief sweep\( detail\)\{0,1\}: rim ' "$log" | head -6
		mal=1
	fi
	# Sin suelo de afuera (outside=none) la arena termina en el muro y no hay
	# nada que medir; con él, tiene que ser la malla del Terrain y sin costura.
	if grep '^Relief sweep: edge ' "$log" | grep -v ' outside=none$' \
		| grep -qv ' material=terrain .* bad=0$'; then
		echo "  FALLO (relieve): el suelo de afuera del muro no es el del Terrain o deja costura"
		grep -n '^Relief sweep\( detail\)\{0,1\}: edge ' "$log" | head -6
		mal=1
	fi
	if grep '^Relief sweep: hell ' "$log" | grep -qv ' unburnt=0$'; then
		echo "  FALLO (relieve): hay mallas que el infierno de Mythos no quemaría"
		grep -n '^Relief sweep\( detail\)\{0,1\}: hell ' "$log" | head -6
		mal=1
	fi
	if ! grep '^Relief sweep: slope ' "$log" | sed -n 's/.* p95=\([0-9.]*\) .*/\1/p' \
		| awk -v max="$RELIEVE_PENDIENTE_MAX" '$1 + 0 > max + 0 { bad = 1 } END { exit bad }'; then
		echo "  FALLO (relieve): la pendiente p95 del suelo abierto pasa de $RELIEVE_PENDIENTE_MAX grados"
		grep -n '^Relief sweep: slope ' "$log" | head -3
		mal=1
	fi
	if [ -n "$paseo" ]; then
		if ! grep -q '^Relief sweep: placement at=120 ' "$log"; then
			echo "  FALLO (relieve): falta el barrido de colocación de los 120 s"
			mal=1
		fi
		if ! grep -q '^Probe relief: stood on raised zone ' "$log"; then
			echo "  FALLO (relieve): el bot nunca pisó una zona elevada"
			mal=1
		fi
		if ! grep -q '^Probe relief: crossed bridge ' "$log"; then
			echo "  FALLO (relieve): el bot nunca cruzó un puente"
			mal=1
		fi
	fi
	if [ "$mal" -ne 0 ]; then
		FALLOS=$((FALLOS + 1))
	fi
}

# --- Listas fijas de líneas esperadas ---------------------------------------
# Se greppean UNA POR UNA, no por conteo: una comprobación que deja de
# ejecutarse desaparece del log sin ruido, y un conteo la daría por buena
# mientras otra se repite.
LINT_CHECKS=(ids_unique glyphs_unique paths_exist stat_ids character_weapons
	director_methods weapon_properties vendor_lucky_roulette_ids marker_labels
	id_format quest_stats text_numbers text_values item_kinds_unique sfx_ids
	stat_rows)
UI_STEPS=(collection quests relics hunt_back hunt coop_count_reject unlock_confirm cards_all
	start_run pause_open settings_toggle pause_close extract retry done)
# Lienzos que resultan de las ventanas de select_probe.gd (WINDOWS).
SELECT_SIZES=(1280x720 1280x831 1280x960 1706x720)

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

# --- Lint de catálogos ------------------------------------------------------
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

# --- Harness de UI ----------------------------------------------------------
# Abre las escenas de UI que ningún soak visita. --quit-after es un
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

# --- Harness del selector de personaje ---------------------------------------
# El layout y la navegación con control del selector en cada forma de
# ventana: lo que el harness de UI no mide.
echo "== harness del selector =="
fase
SELECT_LOG="$LOGDIR/select_probe.log"
BONK_SAVE_PATH="$(save_path_for select_probe)" \
	godot --headless --fixed-fps 60 --quit-after 3600 \
	res://scenes/tests/SelectProbe.tscn >"$SELECT_LOG" 2>&1
if grep -qE "$PATRON_ERROR" "$SELECT_LOG"; then
	echo "  FALLO: el harness del selector reportó problemas"
	grep -nE "$PATRON_ERROR" "$SELECT_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	SELECT_FALTAN=0
	for SIZE in "${SELECT_SIZES[@]}"; do
		if ! grep -qE "^SelectProbe: size $SIZE ok " "$SELECT_LOG"; then
			echo "  FALLO: el selector no aprobó el tamaño '$SIZE'"
			SELECT_FALTAN=$((SELECT_FALTAN + 1))
		fi
	done
	if ! grep -qE "^SelectProbe: done sizes=[0-9]+$" "$SELECT_LOG"; then
		echo "  FALLO: el harness del selector no llegó al final"
		SELECT_FALTAN=$((SELECT_FALTAN + 1))
	fi
	if [ "$SELECT_FALTAN" -ne 0 ]; then
		FALLOS=$((FALLOS + 1))
	else
		echo "  ok (${#SELECT_SIZES[@]} tamaños)"
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

	chequear_tope_cofres "$LOG"
	if [ "$ARENA" = "HollowWoods" ]; then
		chequear_relieve "$LOG" paseo
	fi

	# Cobertura: un soak que no sube de nivel ni toca un interactuable no
	# probó gran cosa, aunque no haya reventado.
	if [ "$NIVEL" -lt 3 ]; then
		echo "  FALLO (cobertura): el raider no pasó de nivel $NIVEL — ¿el arma no hace daño?"
		FALLOS=$((FALLOS + 1))
	fi
	INTERACCIONES=$(( INTERACCIONES + CHESTS + ALTARES + PORTALES ))
done

# --- Soak de etapa ------------------------------------------------------
# El cuarto soak es el único que cruza de mapa: con BONK_STAGE_FAST=1 la
# etapa se supera a los 60 s sin jefe, el harness se queda 70 s más (para
# que la rampa pseudo-infinita registre un minuto) y cruza el portal.
# Queda FUERA de la cuenta de interactuables a propósito: mide el cambio
# de etapa, no la cobertura de un mapa.
# Este soak necesita el DOBLE de reloj que los otros: 60 s hasta la puerta,
# 70 s de espera deliberada para que la rampa pseudo-infinita registre un
# minuto, y después cruzar el mapa hasta un portal que aparece a 40 m o más.
# Con 240 s el recorrido llega justo y falla por varianza: el mundo SÍ es
# reproducible (BONK_GAME_SEED fija cartas, spawns, scatter y relieve),
# pero el orden de contactos de la física diverge y la partida con él.
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
	chequear_tope_cofres "$STAGE_LOG"
	chequear_relieve "$STAGE_LOG"
	if [ "$CIELO_TRAS_AVANCE" -eq 0 ]; then
		echo "  FALLO: ningún evento de cielo tras el cambio de etapa"
		FALLOS=$((FALLOS + 1))
	fi
fi

# --- Soak de co-op ------------------------------------------------------
# El quinto soak es el único con DOS raiders: prueba el reparto de party
# (RunSystems._spawn_party lee Coop antes de instanciar), la pantalla
# dividida, el cruce de etapa con dos cuerpos y —lo que ningún soak solo
# puede alcanzar— el ciclo derribo/reanimación. BONK_DOWN_NOW derriba al
# slot 1 a propósito: esperar a que la horda lo elija no es una prueba.
# Fuera de la cuenta de interactuables, como el de etapa.
echo "== soak co-op (HollowWoods, 2 raiders, ${SECS}s de partida) =="
fase
COOP_LOG="$LOGDIR/soak_coop.log"
# BONK_GRAPHICS=1: el co-op corre en calidad Media porque
# es el único soak con pantalla dividida, y el preset tiene que llegar a
# las SubViewports además del sol de cada etapa.
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_PLAYERS=2 BONK_STAGE_FAST=1 \
	BONK_GODMODE=1 BONK_DOWN_NOW=45 BONK_SEED=4242 BONK_GAME_SEED=4242 \
	BONK_GRAPHICS=1 BONK_SAVE_PATH="$(save_path_for coop)" \
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
	chequear_tope_cofres "$COOP_LOG"
	chequear_relieve "$COOP_LOG"
	# El preset Media aplicado a un sol real con las dos vistas ya armadas.
	if ! grep -q '^Graphics: quality=1 scale=0.75 suns=1 views=2$' "$COOP_LOG"; then
		echo "  FALLO: el preset gráfico no llegó al sol y a las dos vistas"
		grep -n '^Graphics: ' "$COOP_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
fi

# --- Soak del jefe de etapa ------------------------------------------------
# El sexto soak es el único que llega a un JEFE DE ETAPA y lo mata. Ningún
# otro alcanza el minuto 11, y BONK_STAGE_FAST quita la mitad de jefe de la
# puerta. Aquí BONK_STAGE_BOSS_AT trae a Mythos a los 60 s y BONK_STAGE_GOAL
# acorta SOLO la mitad de tiempo: la puerta sigue esperando su muerte. Mide
# la llegada con su calma (el mundo congelado), al menos un renacer, la
# muerte final, la puerta, el portal y el cruce de etapa. Fuera de la cuenta
# de interactuables, como el de etapa.
# A los 60 s y no más tarde: la pelea dura entre 2 y 3 minutos y el raider
# tiene que cruzar el portal ANTES del jefe del minuto 5. Con ese jefe y su
# horda encima, el raider del soak (casi sin daño a esa altura) queda
# rodeado y no llega.
MYTHOS_SECS=450
MYTHOS_FRAMES=$(( MYTHOS_SECS * 60 ))
echo "== soak jefe de etapa (HollowWoods, Mythos, ${MYTHOS_SECS}s de partida) =="
fase
MYTHOS_LOG="$LOGDIR/soak_mythos.log"
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
	BONK_GAME_SEED=4242 BONK_STAGE_BOSS_AT=60 BONK_STAGE_GOAL=90 \
	BONK_SAVE_PATH="$(save_path_for mythos)" \
	godot --headless --fixed-fps 60 --quit-after "$MYTHOS_FRAMES" \
	res://scenes/tests/ArenaProbe.tscn >"$MYTHOS_LOG" 2>&1

if grep -qE "$PATRON_ERROR" "$MYTHOS_LOG"; then
	echo "  FALLO: errores en tiempo de ejecución"
	grep -nE "$PATRON_ERROR" "$MYTHOS_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	MYTHOS_REPORTES=$(grep -c '^frame ' "$MYTHOS_LOG")
	MYTHOS_ESPERADO=$(( MYTHOS_FRAMES / 120 ))
	MYTHOS_VIDAS=$(grep -c '^Mythos scaling: life=' "$MYTHOS_LOG")
	MYTHOS_MUERTES=$(grep -c '^Stage boss slain: Mythos at ' "$MYTHOS_LOG")
	MYTHOS_SUCIOS=$(grep '^Stage sweep: ' "$MYTHOS_LOG" | grep -cv 'enemies=0 gems=0 orbs=0 chests=0 altars=0 beacons=0 pickups=0 boxes=0 vendors=0 possessed=0')
	MYTHOS_PELEA=$(sed -n 's/^Mythos fight over: took=\([0-9.]*\)s.*/\1/p' "$MYTHOS_LOG" | head -1)
	echo "  vidas=$MYTHOS_VIDAS muertes=$MYTHOS_MUERTES pelea=${MYTHOS_PELEA:-?}s sweeps_sucios=$MYTHOS_SUCIOS"
	fase_fin
	if [ "$MYTHOS_REPORTES" -lt "$MYTHOS_ESPERADO" ]; then
		echo "  FALLO: terminó antes de tiempo ($MYTHOS_REPORTES/$MYTHOS_ESPERADO reportes)"
		tail -15 "$MYTHOS_LOG"
		FALLOS=$((FALLOS + 1))
	fi
	if grep -q '^Probe fog: skipped' "$MYTHOS_LOG"; then
		echo "  FALLO: la partida godmode terminó sola"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q '^Boss spawned: Mythos at ' "$MYTHOS_LOG"; then
		echo "  FALLO: Mythos nunca llegó (¿HollowWoods perdió su stage_boss_scene?)"
		grep -n '^Boss spawned: ' "$MYTHOS_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	# La calma: ninguna vida cambió y nada apareció mientras duró la cinemática.
	if ! grep -qE '^Probe calm: .* changed=0 born=0 ' "$MYTHOS_LOG"; then
		echo "  FALLO: el mundo no quedó congelado durante la calma de llegada"
		grep -n '^Probe calm: ' "$MYTHOS_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	# Mythos pelea solo: quemó a la horda que quedaba y no apareció nadie más.
	if ! grep -qE '^Probe alone: held=true .* others_max_after_purge=0 ' "$MYTHOS_LOG"; then
		echo "  FALLO: hubo enemigos normales durante la pelea con Mythos"
		grep -n '^Probe alone: \|^Mythos purge: \|^Spawns ' "$MYTHOS_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
	# ...y al terminar devolvió el HUD, el mundo y el reloj.
	if ! grep -qE '^Probe stage: reason=calm_end hud_visible=true .* cinematic_camera=false .* world_frozen=false clock_running=true$' "$MYTHOS_LOG"; then
		echo "  FALLO: la cinemática no devolvió el HUD, el mundo o el reloj"
		grep -n '^Probe stage: ' "$MYTHOS_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	# Una línea de escalado por vida: la de llegada y la de cada renacer.
	if [ "$MYTHOS_VIDAS" -lt 2 ]; then
		echo "  FALLO: Mythos no renació ni una vez ($MYTHOS_VIDAS línea(s) de escalado)"
		FALLOS=$((FALLOS + 1))
	fi
	# Health.died sale UNA vez: de ahí cuelgan la puerta, el respiro y el botín.
	if [ "$MYTHOS_MUERTES" -ne 1 ]; then
		echo "  FALLO: 'Stage boss slain: Mythos' salió $MYTHOS_MUERTES vez/veces (debe ser 1)"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -qE '^Stage gate: time=[0-9.]+ boss=true$' "$MYTHOS_LOG"; then
		echo "  FALLO: la puerta de etapa no se abrió con la muerte del jefe"
		grep -n '^Stage gate: ' "$MYTHOS_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q 'Exit portal opened' "$MYTHOS_LOG"; then
		echo "  FALLO: la etapa nunca abrió su portal de salida"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q '^Stage advanced: 1 -> 2 (ash_dunes)' "$MYTHOS_LOG"; then
		echo "  FALLO: no se cruzó de Bosque Hueco a Dunas de Ceniza"
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$MYTHOS_SUCIOS" -ne 0 ]; then
		echo "  FALLO: el cambio de etapa dejó objetos vivos"
		grep '^Stage sweep: ' "$MYTHOS_LOG" | head -5
		FALLOS=$((FALLOS + 1))
	fi
	chequear_tope_cofres "$MYTHOS_LOG"
	chequear_relieve "$MYTHOS_LOG"
fi

# --- Soak del minijefe ------------------------------------------------------
# El séptimo soak es el único que ve al MINIJEFE del Bosque Hueco (la Langosta
# Azul), que llega en el minuto 5: BONK_MINI_BOSS_AT lo trae a los 60 s. Mide
# su entrada (el mundo congelado, la pantalla tomada y devuelta), la pelea de
# punta a punta, que su muerte salga exactamente una vez y que 5 s después no
# quede nada suyo (ni efectos, ni cuerpo, ni canción). Si pelea sola
# (EnemySpawner.mini_boss_fights_alone), que se lleve a la horda y no haya
# ningún otro enemigo durante la pelea; si trae su marea
# (LobsterArrival.tide_scene), que esté alta al terminar la entrada y se haya
# ido tras su muerte. Fuera de la cuenta de interactuables, como el del jefe
# de etapa. Pasa igual con la canción puesta o con su hueco vacío.
LOBSTER_SECS=270
LOBSTER_FRAMES=$(( LOBSTER_SECS * 60 ))
echo "== soak minijefe (HollowWoods, Langosta Azul, ${LOBSTER_SECS}s de partida) =="
fase
LOBSTER_LOG="$LOGDIR/soak_minijefe.log"
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
	BONK_GAME_SEED=4242 BONK_MINI_BOSS_AT=60 \
	BONK_SAVE_PATH="$(save_path_for minijefe)" \
	godot --headless --fixed-fps 60 --quit-after "$LOBSTER_FRAMES" \
	res://scenes/tests/ArenaProbe.tscn >"$LOBSTER_LOG" 2>&1

if grep -qE "$PATRON_ERROR" "$LOBSTER_LOG"; then
	echo "  FALLO: errores en tiempo de ejecución"
	grep -nE "$PATRON_ERROR" "$LOBSTER_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	LOBSTER_REPORTES=$(grep -c '^frame ' "$LOBSTER_LOG")
	LOBSTER_ESPERADO=$(( LOBSTER_FRAMES / 120 ))
	LOBSTER_PLANES=$(grep -c '^Langosta Azul scaling: life=1 ' "$LOBSTER_LOG")
	LOBSTER_MUERTES=$(grep -c '^Langosta Azul fight over: took=' "$LOBSTER_LOG")
	LOBSTER_PELEA=$(sed -n 's/^Langosta Azul fight over: took=\([0-9.]*\)s.*/\1/p' "$LOBSTER_LOG" | head -1)
	LOBSTER_ATAQUES=$(sed -n 's/^Langosta Azul move: \([a-z_]*\) at .*/\1/p' "$LOBSTER_LOG" | sort -u | wc -l | tr -d ' ')
	echo "  planes=$LOBSTER_PLANES muertes=$LOBSTER_MUERTES pelea=${LOBSTER_PELEA:-?}s ataques_distintos=$LOBSTER_ATAQUES"
	fase_fin
	if [ "$LOBSTER_REPORTES" -lt "$LOBSTER_ESPERADO" ]; then
		echo "  FALLO: terminó antes de tiempo ($LOBSTER_REPORTES/$LOBSTER_ESPERADO reportes)"
		tail -15 "$LOBSTER_LOG"
		FALLOS=$((FALLOS + 1))
	fi
	if grep -q '^Probe fog: skipped' "$LOBSTER_LOG"; then
		echo "  FALLO: la partida godmode terminó sola"
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -q '^Boss spawned: Langosta Azul at ' "$LOBSTER_LOG"; then
		echo "  FALLO: la Langosta Azul nunca llegó (¿HollowWoods perdió su mini_boss_scene?)"
		FALLOS=$((FALLOS + 1))
	fi
	# La entrada congela el mundo: ninguna vida cambió y nada nació mientras duró.
	if ! grep -qE '^Probe mini calm: frames=[0-9]+ .* changed=0 born=0 ' "$LOBSTER_LOG"; then
		echo "  FALLO: algo cambió de vida o apareció durante la entrada de la langosta"
		grep -n '^Probe mini calm: ' "$LOBSTER_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	# En plena entrada la pantalla es de la langosta; al terminar vuelve entera.
	if ! grep -qE '^Probe mini stage: reason=entrance hud_visible=false .*cinematic_camera=true .*world_frozen=true clock_running=false tide=[a-z]+$' "$LOBSTER_LOG"; then
		echo "  FALLO: en plena entrada el HUD, la cámara o el mundo no estaban tomados"
		grep -n '^Probe mini stage: ' "$LOBSTER_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	if ! grep -qE '^Probe mini stage: reason=entrance_end hud_visible=true .*cinematic_camera=false .*world_frozen=false clock_running=true tide=[a-z]+$' "$LOBSTER_LOG"; then
		echo "  FALLO: la entrada no devolvió el HUD, la cámara, el mundo o el reloj"
		grep -n '^Probe mini stage: ' "$LOBSTER_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$LOBSTER_PLANES" -ne 1 ]; then
		echo "  FALLO: 'Langosta Azul scaling: life=1' salió $LOBSTER_PLANES vez/veces (debe ser 1)"
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$LOBSTER_MUERTES" -ne 1 ]; then
		echo "  FALLO: 'Langosta Azul fight over' salió $LOBSTER_MUERTES vez/veces (debe ser 1)"
		FALLOS=$((FALLOS + 1))
	fi
	if [ "$LOBSTER_ATAQUES" -lt 3 ]; then
		echo "  FALLO: la langosta usó $LOBSTER_ATAQUES ataque(s) distinto(s) (se esperan al menos 3)"
		FALLOS=$((FALLOS + 1))
	fi
	# Si pelea sola: se llevó a la horda al empezar y no hubo nadie más.
	if grep -q '^Spawns held: mini boss fights alone at ' "$LOBSTER_LOG"; then
		if ! grep -qE '^Langosta Azul purge: swept=[0-9]+ bosses=[0-9]+ at ' "$LOBSTER_LOG"; then
			echo "  FALLO: la langosta pelea sola pero no barrió a la horda al empezar"
			FALLOS=$((FALLOS + 1))
		fi
		if ! grep -q '^Probe mini alone: held=true others_max_after_purge=0$' "$LOBSTER_LOG"; then
			echo "  FALLO: hubo otros enemigos durante la pelea de la langosta, o los spawns no estaban cortados"
			grep -n '^Probe mini alone: ' "$LOBSTER_LOG" | head -3
			FALLOS=$((FALLOS + 1))
		fi
		if ! grep -q '^Spawns resumed at ' "$LOBSTER_LOG"; then
			echo "  FALLO: los spawns no volvieron después de la muerte de la langosta"
			FALLOS=$((FALLOS + 1))
		fi
	else
		echo "  nota: la langosta pelea en medio de la horda (mini_boss_fights_alone apagado)"
	fi
	# Si trae su marea: alta cuando la entrada devuelve la pantalla, y nada
	# de ella (ni el cielo azul) tras su muerte.
	if grep -q '^Lobster tide: rising over ' "$LOBSTER_LOG"; then
		if ! grep -qE '^Probe mini stage: reason=entrance_end .* tide=high$' "$LOBSTER_LOG"; then
			echo "  FALLO: la marea no estaba alta al terminar la entrada de la langosta"
			grep -n '^Probe mini stage: ' "$LOBSTER_LOG" | head -3
			FALLOS=$((FALLOS + 1))
		fi
		# Baja con el reloj del juego (una pausa por subir de nivel la detiene):
		# se mira al final del soak, no unos segundos después de la muerte.
		if ! grep -q '^Lobster tide: gone at ' "$LOBSTER_LOG" \
				|| ! grep -q '^Probe mini tide: left=none$' "$LOBSTER_LOG"; then
			echo "  FALLO: la marea de la langosta no se fue después de su muerte"
			grep -n '^Lobster tide: \|^Probe mini tide: ' "$LOBSTER_LOG" | head -6
			FALLOS=$((FALLOS + 1))
		fi
	else
		echo "  nota: la langosta llega sin marea (tide_scene vacío)"
	fi
	# Cinco segundos después de morir no queda nada suyo.
	if ! grep -qE '^Probe mini hazards: .* total=0 body=false song_playing=false died_signals=1$' "$LOBSTER_LOG"; then
		echo "  FALLO: tras su muerte quedó algo de la langosta (efectos, cuerpo o canción), o murió más de una vez"
		grep -n '^Probe mini hazards: ' "$LOBSTER_LOG" | head -3
		FALLOS=$((FALLOS + 1))
	fi
	chequear_tope_cofres "$LOBSTER_LOG"
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
