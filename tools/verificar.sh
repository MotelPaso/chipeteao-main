#!/usr/bin/env bash
# Verificación headless del proyecto: import limpio + soak por arena.
# Uso: tools/verificar.sh [segundos_por_arena]   (por defecto 360)
#
# 360 s no es arbitrario: por debajo, el recorrido del harness no da tiempo a
# cruzar una arena de 240x240 y la puerta de cobertura no puede exigir nada.
# La corrida completa tarda ~32 min (3 x 360 s + 1 x 720 s + import).
#
# BONK_GAME_SEED fija el RNG del juego (cartas, spawns, scatter y por tanto
# el relieve). Sin él cada soak es un mundo distinto y cualquier comparación
# entre dos corridas mide ruido, no el cambio.
#
# Falla (exit 1) si:
#   - el import o algún soak reporta errores/warnings de Godot
#   - una arena no llega al final del soak (se colgó o murió antes)
#   - un soak no ejercita los sistemas clave (cobertura): sin esto un soak
#     puede pasar "limpio" por no haber ejecutado nada.
#   - el soak de ETAPA (iteración 49) no cruza de mapa, deja algo vivo al
#     cruzar, o pierde progreso al hacerlo.
set -uo pipefail
cd "$(dirname "$0")/.."

SECS="${1:-360}"
FRAMES=$(( SECS * 60 ))
LOGDIR="${TMPDIR:-/tmp}/bonkraiders-verify"
mkdir -p "$LOGDIR"
FALLOS=0
INTERACCIONES=0

PATRON_ERROR='SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid get index|Invalid set index|Invalid access|null instance|Cannot call method|Trying to assign|USER ERROR|USER WARNING|Attempt to call|previously freed|nonexistent|Resource file not found|Failed to load'

echo "== import =="
IMPORT_LOG="$LOGDIR/import.log"
godot --headless --import >"$IMPORT_LOG" 2>&1
if grep -qE "$PATRON_ERROR" "$IMPORT_LOG"; then
	echo "  FALLO: el import reportó problemas"
	grep -nE "$PATRON_ERROR" "$IMPORT_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	echo "  ok"
fi

for ARENA in HollowWoods AshDunes Gloomfen; do
	echo "== soak $ARENA (${SECS}s de partida) =="
	LOG="$LOGDIR/soak_$ARENA.log"
	BONK_ARENA="res://scenes/world/$ARENA.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
		BONK_GAME_SEED=4242 \
		godot --headless --fixed-fps 60 --quit-after "$FRAMES" \
		res://scenes/tests/ArenaProbe.tscn >"$LOG" 2>&1

	if grep -qE "$PATRON_ERROR" "$LOG"; then
		echo "  FALLO: errores en tiempo de ejecución"
		grep -nE "$PATRON_ERROR" "$LOG" | head -30
		FALLOS=$((FALLOS + 1))
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
# Con 240 s el recorrido llega justo y falla por varianza (el RNG del juego
# se randomize()a: la semilla solo fija el paseo del harness).
STAGE_SECS=$(( SECS * 2 ))
STAGE_FRAMES=$(( STAGE_SECS * 60 ))
echo "== soak etapa (HollowWoods, BONK_STAGE_FAST, ${STAGE_SECS}s de partida) =="
STAGE_LOG="$LOGDIR/soak_stage.log"
BONK_ARENA="res://scenes/world/HollowWoods.tscn" BONK_GODMODE=1 BONK_SEED=4242 \
	BONK_GAME_SEED=4242 BONK_STAGE_FAST=1 \
	godot --headless --fixed-fps 60 --quit-after "$STAGE_FRAMES" \
	res://scenes/tests/ArenaProbe.tscn >"$STAGE_LOG" 2>&1

if grep -qE "$PATRON_ERROR" "$STAGE_LOG"; then
	echo "  FALLO: errores en tiempo de ejecución"
	grep -nE "$PATRON_ERROR" "$STAGE_LOG" | head -30
	FALLOS=$((FALLOS + 1))
else
	AVANCES=$(grep -c '^Stage advanced: ' "$STAGE_LOG")
	SWEEPS_SUCIOS=$(grep '^Stage sweep: ' "$STAGE_LOG" | grep -cv 'enemies=0 gems=0 orbs=0 chests=0 altars=0 beacons=0 pickups=0')
	CARRIES=$(grep -c '^Stage carry: ' "$STAGE_LOG")
	# Las líneas van en PARES (una antes del cruce y otra después). Cada
	# par tiene que coincidir consigo mismo; entre un cruce y el siguiente
	# el equipo sí crece, así que compararlas todas contra todas sería
	# exigir que la partida no avance.
	PARES_ROTOS=$(grep '^Stage carry: ' "$STAGE_LOG" \
		| awk 'NR % 2 == 1 { prev = $0; next } { if ($0 != prev) bad++ } END { print bad + 0 }')
	CIELO_TRAS_AVANCE=$(sed -n '/^Stage advanced: /,$p' "$STAGE_LOG" | grep -c '^Sky event: ')
	echo "  avances=$AVANCES sweeps_sucios=$SWEEPS_SUCIOS carries=$CARRIES pares_rotos=$PARES_ROTOS cielo_tras_avance=$CIELO_TRAS_AVANCE"
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
if [ "$FALLOS" -eq 0 ]; then
	echo "VERIFICACIÓN OK — logs en $LOGDIR"
	exit 0
fi
echo "VERIFICACIÓN FALLIDA: $FALLOS problema(s) — logs en $LOGDIR"
exit 1
