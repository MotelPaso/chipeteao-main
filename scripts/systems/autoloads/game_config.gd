extends Node
## Autoload "GameConfig": la configuración elegida fuera de una partida que
## debe sobrevivir a cambios de escena y a RunState.reset(); vive aparte de
## RunState para que reiniciar una partida nunca la borre. No se guarda a
## disco: los valores por defecto rigen en cada apertura de la app.

## Id de CharacterCatalog con que aparece la próxima partida. Lo pone la
## pantalla de selección; un soak sin ventana usa el valor por defecto.
var selected_character_id: String = CharacterCatalog.DEFAULT_ID

## Id de MapCatalog del mapa que se juega AHORA. Lo escribe RunRoot en cada
## cambio de etapa; lo leen el registro meta y la pantalla final. No es una
## elección: una partida recorre toda la lista de mapas.
var selected_map_id: String = MapCatalog.DEFAULT_ID

## Id de MapCatalog del bioma de la etapa 1. Siempre el de por defecto en
## juego normal y en la diaria (toda partida abre en el bosque); el harness
## de soak lo apunta a un bioma para que BONK_ARENA siga significando
## "prueba este mapa", y empezar más adelante solo llega antes a la vuelta 1.
var start_map_id: String = MapCatalog.DEFAULT_ID

## --- Cacería diaria -------------------------------------------------------
## True mientras la partida próxima/actual es el desafío diario con semilla:
## personaje y mapa fijos para todos ese día, RNG determinista (RunState
## siembra el flujo global y el scatter adopta daily_seed) y un puntaje
## guardado bajo daily_date. Lo apaga un Empezar normal; Reintentar lo deja.
var daily_mode: bool = false
## Semilla derivada de la fecha de hoy; también la del scatter y del RNG global.
var daily_seed: int = 0
## "AAAA-MM-DD" para la que se lanzó la diaria (nombra el contador del mejor
## puntaje).
var daily_date: String = ""
## Puntaje de la última diaria terminada (lo escribe RunManager; lo lee la
## pantalla final).
var last_daily_score: int = 0


## Una sola fórmula determinista para que toda diaria sea comparable: cada
## baja vale 1, cada nivel 25 y cada segundo sobrevivido 1.
static func daily_score(kills: int, level: int, run_seconds: float) -> int:
	return kills + level * 25 + int(run_seconds)
