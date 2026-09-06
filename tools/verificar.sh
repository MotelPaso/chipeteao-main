#!/usr/bin/env bash
# Verificación headless del proyecto: import limpio + soak por arena.
# Uso: tools/verificar.sh [segundos_por_arena]   (por defecto 240)
#
# 240 s no es arbitrario: por debajo, el recorrido del harness no da tiempo a
# cruzar una arena de 160x160 y la puerta de cobertura no puede exigir nada.
#
# Falla (exit 1) si:
#   - el import o algún soak reporta errores/warnings de Godot
#   - una arena no llega al final del soak (se colgó o murió antes)
#   - un soak no ejercita los sistemas clave (cobertura): sin esto un soak
#     puede pasar "limpio" por no haber ejecutado nada.
set -uo pipefail
cd "$(dirname "$0")/.."

SECS="${1:-240}"
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
	PORTALES=$(grep -c 'Portal used:' "$LOG")
	echo "  nivel=$NIVEL cofres=$CHESTS altares=$ALTARES portales=$PORTALES"

	# Cobertura: un soak que no sube de nivel ni toca un interactuable no
	# probó gran cosa, aunque no haya reventado.
	if [ "$NIVEL" -lt 3 ]; then
		echo "  FALLO (cobertura): el raider no pasó de nivel $NIVEL — ¿el arma no hace daño?"
		FALLOS=$((FALLOS + 1))
	fi
	INTERACCIONES=$(( INTERACCIONES + CHESTS + ALTARES + PORTALES ))
done

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
