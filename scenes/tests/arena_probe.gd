extends Node
## Arnés de soak headless: arranca una arena como HIJA de una raíz que
## procesa siempre, imprime una línea de estado cada 2 s de partida y elige
## la primera carta de mejora cada vez que se abre la UI de cartas (en un
## soak no hay nadie en el mouse). Se corre con:
##   godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
##
## Variables de entorno:
##   BONK_ARENA=res://...   escena de arena (por defecto: Hollow Woods)
##   BONK_CHARACTER=<id>    raider de CharacterCatalog
##   BONK_PLAYERS=<1-4>     tamaño del grupo. Coop.configure corre ANTES de
##                          instanciar Run.tscn, que es lo que lee
##                          RunSystems._spawn_party; todos los slots usan el
##                          teclado, porque un soak no tiene mandos. El slot 0
##                          guía e interactúa, los slots 1+ lo SIGUEN y nunca
##                          interactúan por su cuenta
##   BONK_CHARACTER2=<id>   raider del slot 1 (por defecto: la fila del
##                          catálogo después de la del slot 0, para que difieran)
##   BONK_DOWN_NOW=<secs>   da un golpe letal al slot 1 en ese tiempo de
##                          partida y cada 60 s después, para FORZAR el camino
##                          de caída y revivir en vez de esperarlo
##   BONK_GODMODE=1         raider inmortal, para ejercitar sistemas tardíos.
##                          SOLO el slot 0: el slot 1 sigue mortal, que es lo
##                          que permite que BONK_DOWN_NOW funcione
##   BONK_SAVE_PATH=<path>  dónde vive el guardado de este soak (por defecto:
##                          user://soak_save.json). Se respeta aquí, antes de
##                          arrancar la partida, y también en SaveData
##   BONK_WALK=0            deja al raider quieto (por defecto camina, ver abajo)
##   BONK_SEED=<int>        caminata determinista, para reproducir un soak
##   BONK_ELITE_BOOST=1     todo spawn sale brillante (prueba de amontonamiento)
##   BONK_STAGE_FAST=1      las etapas se completan a los 60 s sin jefe, para
##                          que un soak cruce un cambio de etapa (lo lee RunManager)
##   BONK_GAME_SEED=<int>   siembra el RNG del JUEGO (RunState.reset), lo que
##                          hace reproducible un soak entero
##   BONK_POWERUP_NOW=<id>  da ese power-up al slot 0 a los 20 s y lo VUELVE a
##                          dar cada vez que expira, para que un soak de 120 s
##                          pase todo su reloj dentro del efecto
##   BONK_POWERUP_AT=<s>    mueve la primera entrega de BONK_POWERUP_NOW fuera
##                          de los 20 s por defecto. Un congelamiento que empieza
##                          a los 20 s y se renueva siempre atrapa a cada enemigo
##                          mientras está EN LA SUPERFICIE, así que los estados
##                          que existen más tarde en su ciclo (un Duneburrower
##                          bajo tierra) no se alcanzan con el valor por defecto
##   BONK_STAR_NOW=1        suelta una estrella QUIETA a los pies del raider a
##                          los 30 s (la que deambula es difícil de alcanzar a
##                          propósito, y un soak tiene que poder)
##   BONK_POWERUP_BOOST=1   multiplica la probabilidad de drop por muerte (lo lee
##                          EnemySpawner), para que aparezcan drops en un soak
##   BONK_POI_NOW=a,b,c     crea esos POI a 8 m del raider a los 20 s
##                          (vendor_items, vendor_powerups, vendor_animals,
##                          pet_box, event_altar, lucky_block); el ritmo del
##                          director tardaría muchos minutos en ofrecer los seis.
##                          Los repetidos cuentan: seis lucky_block crean seis bloques
##   BONK_LUCKY_REWARD=a,b  cola de ids de recompensa que pagan los lucky blocks
##                          sucesivos en vez de sortear (la última entrada se
##                          repite). Seis bloques y los seis ids ejecutan cada
##                          rama de LUCKY_REWARDS en un soak
##   BONK_SWAP_MENU=1       fuerza el ÚNICO cruce posible entre un cambio de
##                          etapa y un menú bloqueante: el frame en que un menú
##                          cerrable tiene la pausa, el probe dispara un cambio
##                          de etapa por el grupo run_root e informa
##                          `Swap menu: paused=%s` cinco segundos después.
##                          `true` es la traba que deja la partida sin salida.
##                          Necesita que se abra un menú, por ejemplo
##                          BONK_POI_NOW=vendor_items BONK_POINTS=2000
##   BONK_POINTS=<n>        da al slot 0 esa cantidad de puntos de partida al
##                          inicio, para que un soak de vendedor pueda comprar
##   BONK_WEATHER_NOW=<id>  fuerza ese clima a los 30 s (el ritmo propio de
##                          WeatherDirector tarda muchos minutos en ofrecer los nueve)
##   BONK_WEAPON=<id>       el raider empieza con ESA arma en vez de la del
##                          personaje, por el mismo camino de entrega
##   BONK_ITEM_NOW=a,b:2    da esos ítems al slot 0 a los 10 s (`id:n` para n
##                          copias) y hace que el recorrido haga DASH cada ~3 s
##   BONK_ZENKAI_TEST=1     a los 60 s: un golpe del 95%, tres segundos de
##                          invulnerabilidad y luego curación total; es la caída
##                          y supervivencia que arma Zenkai y que si no
##                          necesitaría mala suerte real
##   BONK_SHOT_DIR=<dir>    guarda frames PNG del soak en <dir>: la variable que
##                          convierte este arnés en CÁMARA. Los gates corren
##                          --headless, cuyo renderer dummy no compila shaders
##                          ni dibuja nada, así que un suelo que no se rasteriza
##                          se lee igual que uno sano en el log. Con --headless
##                          se ignora (avisando una vez): `Shots skipped: headless`
##   BONK_GRAPHICS=<0-2>    preset gráfico del soak: 0 Alta, 1 Media, 2 Baja.
##                          Se aplica antes de arrancar la partida, así el sol
##                          de la primera etapa ya lo recibe
##   BONK_SHOT_EVERY=<s>    segundos entre fotos periódicas (por defecto 10).
##                          Las fotos de eventos se toman igual
##
## Por defecto el raider CAMINA E INTERACTÚA. Un raider quieto se salta en
## silencio todo sistema que depende del movimiento (Slime Trail solo deja
## charcos al moverse, los altares solo cargan con un jugador en el anillo,
## cofres y portales necesitan que alguien llegue Y apriete interactuar), y
## un soak quieto informa "sin errores" sobre código que nunca corrió. El
## recorrido visita primero los Interactables disponibles (se queda al llegar
## para que los altares Charge terminen su canalización y la interacción
## entre) y vuelve a puntos caminables al azar cuando no quedan.
##
## Tres revisiones corren siempre en todo soak y avisan (lo que hace fallar
## tools/verificar.sh) cuando saltan: el detector de vuelo, el BARRIDO DE
## MÁSCARA de la arena (una vez) y la VIGILANCIA DE CELDAS BLOQUEADAS
## (continua). Ninguna tiene variable de entorno: un guardia que se puede
## apagar es un guardia que nadie ve fallar. Ver los dos bloques de
## constantes más abajo.

const DEFAULT_ARENA := "res://scenes/world/HollowWoods.tscn"
## Archivo de guardado si BONK_SAVE_PATH no está definido. Nunca el progreso del jugador.
const DEFAULT_SAVE_PATH := "user://soak_save.json"
## La única escena en que arranca una partida. BONK_ARENA no nombra la escena
## a instanciar sino el BIOMA del soak, que pasa a GameConfig.start_map_id y
## por lo tanto a la etapa 1.
const RUN_SCENE := "res://scenes/world/Run.tscn"
## Segundos que el recorrido espera tras abrirse el portal de salida antes de
## tomarlo, con BONK_STAGE_FAST. Alcanza para registrar al menos un minuto
## completo de la rampa pseudo-infinita, lo que prueba que corre.
const PSEUDO_INFINITE_DWELL: float = 70.0
## Retraso (segundos) tras un cambio de etapa antes de que el probe dispare un
## evento de cielo en la arena nueva. Las luces se vuelven a cachear en el
## cambio; una luna de sangre que no tiñe nada delata una referencia vieja al Sun.
const STAGE_SKY_DELAY: float = 5.0

## Radio (metros) del cuadrado donde la caminata elige puntos, cuando la arena
## no publica sus límites por el grupo "arena_bounds".
const FALLBACK_HALF_EXTENT: float = 60.0
## Un tramo termina cuando el raider llega a esta distancia (metros) de su
## punto... Se mide SOLO en XZ: con relieve, un punto en el fondo de una hondonada
## y un raider en su borde están a metros en Y aun pisando el mismo lugar, y
## una revisión 3D no converge nunca.
const WAYPOINT_REACHED: float = 2.5
## ...o tras este tiempo (segundos), para que la geometría que no puede rodear
## nunca lo trabe. Holgado: una arena de 240x240 con muros de máscara y relieve
## necesita desvíos, y un plazo corto convierte el recorrido en caminata al azar.
const LEG_TIMEOUT: float = 40.0
## Segundos antes de que el recorrido vuelva a un interactuable que ya probó.
## Evita que un altar gastado pero aún disponible atrape la caminata.
const REVISIT_COOLDOWN: float = 45.0
## Cuánto (metros) se desvía el recorrido por un power-up en el suelo. Corto:
## un pickup es un extra en el camino, no un destino que valga cruzar 240 m.
const PICKUP_DETOUR: float = 20.0
## El progreso se mide cada STALL_WINDOW segundos; moverse menos de
## STALL_DISTANCE metros en esa ventana cuenta como atascado y provoca un salto.
const STALL_WINDOW: float = 1.0
const STALL_DISTANCE: float = 1.5
## Segundos que el raider se queda quieto al llegar a un interactuable. Debe
## superar ChargeShrine.channel_time (8 s): "llegó" es el player_in_range del
## propio juego, que salta en el BORDE del anillo, así que una espera más
## corta que la canalización abandona cada altar a medias y el soak nunca
## ejercita una carga completa.
const LINGER_TIME: float = 10.0
## Mientras espera, aprieta interactuar cada tantos segundos (los cofres
## responden al primero; uno gastado ignora el resto).
const INTERACT_INTERVAL: float = 0.75
## Un árbol pausado tanto tiempo (segundos) sin UI de cartas abierta significa
## que alguna UI bloqueante trabó el soak: merece una línea de log, porque una
## partida trabada se ve igual que una sana en el contador de frames.
const PAUSE_WEDGE_WARN: float = 20.0

## --- co-op ------------------------------------------------------------------
## Los slots 1+ SIGUEN al líder con una correa CORTA. Ambos números los fija
## REVIVE_NOTICE_RANGE (abajo), no el gusto: el líder solo nota un cuerpo
## caído a menos de 6 m, así que un seguidor que se aleja más cae fuera de
## vista y su cuerpo queda abandonado el resto del soak.
## Nunca apuntan a un interactuable: todos los gates están calibrados con un
## solo raider recorriendo.
const FOLLOW_DISTANCE: float = 2.5
## Un seguidor sin nada que perseguir hace tramos cortos al azar en vez de
## quedarse quieto, para que su código de movimiento (y el interés de la
## horda en él) siga corriendo. Lo bastante cortos para no salir del rango de aviso.
const FOLLOW_LEG_TIME: float = 3.0
const FOLLOW_LEG_RANGE: float = 3.0
## A qué distancia (metros) de un cuerpo caído el líder mantiene interactuar.
## PlayerRevive.revive_radius es 3.0; esto deja margen para la revisión de llegada.
const REVIVE_APPROACH: float = 2.0
## Un cuerpo caído a esta distancia (metros) hace que el rescate supere a TODO,
## incluida la carrera a la salida: un grupo que abandona a su caído no es grupo.
const REVIVE_NOTICE_RANGE: float = 6.0
## BONK_DOWN_NOW: tras la primera caída forzada, otra cada tantos segundos,
## para que un soak ejercite el camino más de una vez.
const DOWN_NOW_PERIOD: float = 60.0
## Vida de los SEGUIDORES con BONK_GODMODE. No los diez millones del líder:
## un seguidor que no puede caer deja a BONK_DOWN_NOW sin probar nada. Pero
## con la vida base es un saco de boxeo (la horda co-op escala +50% de vida
## y +30% de spawn por raider extra, y el seguidor entra en ella sin
## recorrer), y como el rescate supera incluso a la carrera a la salida, el
## líder pasaría el soak junto al cuerpo y el grupo nunca cruzaría una etapa.
## Esta reserva aguanta el contacto normal cerca de un minuto y aun así muere
## al instante con BONK_DOWN_NOW, que pega el doble de max_hp.
const FOLLOWER_GODMODE_HP: float = 2000.0
## Segundos que el líder dedica a UN rescate antes de abandonar ese cuerpo y
## volver al recorrido. Diez veces PlayerRevive.revive_time, así que solo
## salta cuando el rescate es imposible de verdad: un cuerpo detrás de una
## roca, o uno que siguen empujando fuera de alcance. Sin esto un solo cuerpo
## inalcanzable atrapa el recorrido el resto del soak y la etapa nunca se
## cruza: una falla del arnés disfrazada de falla del juego.
const RESCUE_TIMEOUT: float = 30.0
## ...y se lo deja tranquilo tantos segundos después, para que el recorrido
## avance en vez de volver apenas se aleja.
const RESCUE_COOLDOWN: float = 45.0

var _players: int = 1
var _down_now_at: float = -1.0
var _down_next: float = 0.0
var _party_downs: int = 0
var _party_revives: int = 0
## Última lectura de mascotas tomada con la partida viva (ver _party_pets_text).
var _party_pets_seen: String = "none"
## instance ids que están en "downed_players", para contar una transición
## una vez y no en cada frame.
var _down_seen: Dictionary[int, bool] = {}
## Estado de cada seguidor, por slot: segundos que le quedan a su tramo al
## azar y hacia dónde va.
var _follow_left: Dictionary[int, float] = {}
var _follow_to: Dictionary[int, Vector3] = {}
## El cuerpo caído que el líder está rescatando, o null.
var _rescue_target: Node3D = null
## Segundos dedicados al rescate actual (ver RESCUE_TIMEOUT).
var _rescue_time: float = 0.0
## instance id -> run_time en que se abandonó el rescate de ese cuerpo.
var _rescue_given_up: Dictionary[int, float] = {}
## Acciones mantenidas por slot, para que la liberación vaya al set de acciones correcto.
var _held: Dictionary[String, bool] = {}

## --- aserciones de auditoría -----------------------------------------------
## BONK_SWAP_MENU: segundos entre disparar el cambio y leer la pausa.
## Alcanza para el corte de ScreenFade (0.22 + 0.26), los frames de asiento
## del cambio y la construcción de la etapa siguiente.
const SWAP_MENU_REPORT: float = 5.0
var _swap_menu: bool = false
var _swap_menu_fired: bool = false
var _swap_menu_left: float = 0.0
## Mayor número de bonos temporales con etiqueta SAIYAN vistos a la vez en el
## líder. Tres es el aura entera; más significa que un re-disparo se apiló en
## vez de reemplazar, lo que item_bag dice que no puede pasar.
const SAIYAN_TAG: String = "saiyan"
const SAIYAN_BOONS_PER_AURA: int = 3
var _saiyan_watch: bool = false
var _saiyan_max: int = 0

## --- fin de partida ---------------------------------------------------------
## Un soak mortal termina con la muerte A PROPÓSITO: RunManager pausa el árbol
## y RunEndScreen no se juega sola en headless, así que sin esto el probe se
## quedaría en su propio aviso de TRABA hasta agotar los frames. Dos frames
## después de "Meta saved:" (que RunManager imprime justo antes de emitir
## run_ended) alcanzan para que lleguen los logs del cierre.
const RUN_END_QUIT_FRAMES: int = 2
var _run_end_left: int = -1
var _run_ended_at: float = -1.0

var _frames: int = 0
var _walking: bool = true
var _waypoint: Vector3 = Vector3.ZERO
var _leg_time_left: float = 0.0
var _linger_left: float = 0.0
var _interact_timer: float = 0.0
var _paused_for: float = 0.0
var _wedge_reported: bool = false
## BONK_PROBE_DEBUG=1 narra el recorrido (puntos, llegadas, interacciones)
## para poder diagnosticar un soak que nunca llega a un interactuable.
var _debug: bool = false
## instance id del Interactable -> run_time en que el recorrido fue hacia él por última vez.
var _visited: Dictionary[int, float] = {}
## El interactuable al que va este tramo (null si solo deambula).
var _target: Interactable = null
## Cuenta de tramos, resumida al final de cada soak (Probe legs:): un
## recorrido cuyos tramos vencen todos se ve igual que uno sano en el contador
## de frames, y eso es justo lo que produce un radio de llegada muy chico o un
## punto inalcanzable.
var _legs_reached: int = 0
var _legs_timed_out: int = 0
var _stall_check: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()

## --- capturas ---------------------------------------------------------------
## BONK_SHOT_DIR convierte el soak en cámara. La captura vive en ShotCamera,
## que también usa UiProbe; aquí va CUÁNDO vale la pena una foto en una
## partida. Nada de esta sección puede facilitar un gate: sin la variable,
## cada línea no hace nada.
var _camera: ShotCamera = null
## Medidor del costo por frame: una línea `Perf` cada 10 s de juego y un
## `Perf summary` al salir. Siempre activo: solo lee el reloj.
var _perf: PerfMeter = null
## Máximo de cofres de recompensa de élite sin abrir vistos a la vez en el
## mapa, muestreado con la línea de frame. Se compara con EnemyBase.BOUNTY_CHEST_CAP.
var _bounty_chests_max: int = 0
## instance ids ya contados en los grupos de vendedor / caja de mascota /
## lucky block, para que un nodo dé una sola foto aunque siga ahí.
var _shot_seen: Dictionary[int, bool] = {}
## Ids de power-up que llevaba el líder en la última muestra; uno nuevo es un pickup.
var _shot_powerups: Dictionary[String, bool] = {}
## Una sola foto del selector de cartas por soak: una partida larga sube de
## nivel decenas de veces y todas se ven igual.
var _card_shot_taken: bool = false

## --- detector de vuelo -------------------------------------------------------
## Regla fija y angosta a propósito, para que no se pueda ajustar hasta el
## silencio: un cuerpo cuenta como en el aire si estuvo SUBIENDO (velocity.y
## sobre AIRBORNE_RISE_SPEED, metros/segundo) SIN tocar el suelo, sin pausa,
## durante AIRBORNE_TIME segundos.
## Solo dos excepciones, ambas cuerpos que suben a propósito: un enemigo con
## su propio estado de trepar activo, y un Duneburrower en plena erupción.
## Cada caso nuevo emite UN aviso (uno por cuerpo), y cada aviso hace fallar
## tools/verificar.sh, que es la idea.
const AIRBORNE_RISE_SPEED: float = 0.5
const AIRBORNE_TIME: float = 0.5
## Duneburrower.State.ERUPTING, por valor: el probe no puede nombrar el enum
## sin acoplarse a ese script, y el orden es estable (SURFACED, BURROWED, ERUPTING).
const BURROWER_ERUPTING: int = 2
## instance id -> segundos que lleva subiendo sin tocar el suelo.
var _rising_for: Dictionary[int, float] = {}
## instance ids ya informados, para que cada cuerpo avise una vez.
var _airborne_seen: Dictionary[int, bool] = {}
## Cuenta acumulada de cuerpos DISTINTOS en el aire; va en cada línea de frame.
var _airborne_total: int = 0

## --- guardias de la máscara de la arena -------------------------------------
## Lo único que cierra una celda bloqueada son las rocas visibles, así que
## dos revisiones corren en TODO soak (sin variable de entorno, porque ambas
## existen justo para poder fallar):
##  (a) BARRIDO DE MÁSCARA, una vez: empuja una cápsula del tamaño del
##      jugador por cada borde que una celda bloqueada comparte con una
##      caminable e informa cada muestra que no toca nada. Un hueco por el
##      que pasa la cápsula es un agujero en la arena.
##  (b) VIGILANCIA DE CELDAS BLOQUEADAS, continua: el raider líder parado en
##      el SUELO de la arena dentro de una celda bloqueada significa que pasó.
## Paso de muestreo (metros) sobre un borde. Muy por debajo del diámetro de
## la cápsula, para que un hueco no se esconda entre dos muestras.
const SWEEP_STEP: float = 0.2
## La cápsula del jugador, copiada de Player.tscn (radio/altura y los 0.9 m
## a los que el CollisionShape3D está sobre el origen del cuerpo). Debe
## coincidir con esa escena.
const SWEEP_CAPSULE_RADIUS: float = 0.4
const SWEEP_CAPSULE_HEIGHT: float = 1.8
## Centro de la cápsula SOBRE EL SUELO (metros) en cada muestra.
const SWEEP_CAPSULE_CENTER_Y: float = 0.9
## La geometría del mundo (suelo, perímetro, props) está en la capa 1; los
## enemigos están en la capa 2 y nunca cuentan como "este borde está sellado".
const WORLD_COLLISION_LAYER: int = 1
## El barrido corre en este frame de física: lo bastante tarde para que cada
## prop que el scatter agregó en _ready tenga su transform en el servidor de
## física, y lo bastante pronto para que el recorrido aún no se haya movido.
const SWEEP_FRAME: int = 10
## Aberturas nombradas una por una antes de que el log pase a la línea de resumen.
const SWEEP_REPORT_LIMIT: int = 6
## Cuánto (metros) SOBRE EL TERRENO puede estar un raider y aún contar como
## parado en el suelo y no sobre una roca, una plataforma o una meseta.
const FLOOR_STAND_MAX_Y: float = 0.6
## Segundos seguidos dentro de una celda bloqueada antes de contar como
## "entró". Lo bastante largo para que un salto o un empujón no lo dispare.
const BLOCKED_CELL_GRACE: float = 2.0

var _swept: bool = false
## Frame de física en que toca el (próximo) barrido de máscara. Se rearma en
## cada cambio de etapa, porque cada etapa construye su propia máscara.
var _sweep_at_frame: int = SWEEP_FRAME
## Etapa en que el recorrido cree estar (solo para la narración de depuración).
var _seen_stage_index: int = 0
## Cuenta regresiva hasta el evento de cielo tras el cambio (ver STAGE_SKY_DELAY); <= 0 inactiva.
var _sky_probe_left: float = 0.0
## Segundos que quedan de la espera deliberada antes de tomar el portal de salida.
var _dwell_left: float = 0.0
## True mientras RunState.stage_cleared ya fue atendido.
var _stage_cleared_seen: bool = false
## True si BONK_STAGE_FAST está definido (se lee una vez, en ready).
var _stage_fast: bool = false
## Gate de niebla. Un soak que casi no explora es un soak cuyo raider no fue
## a ningún lado, justo la falla que la caminata existe para atrapar; la
## niebla es la única señal que la informa directamente.
##
## Calibrado con tres soaks de bioma de 360 s con BONK_SEED=4242
## BONK_GAME_SEED=4242: Hollow Woods 0.15, Ash Dunes 0.32, Gloomfen 0.16.
## El gate es el 60% del PEOR de ellos.
##
## Ese 60% no es holgura para un recorrido flojo, es varianza medida: el
## mundo es reproducible (misma máscara, mismo relieve, idéntico frame a frame
## los primeros ~38 s) pero la partida no; el orden de contactos de física
## diverge y la misma semilla cae en cualquier punto de 0.13-0.24 en el mismo
## mapa. Un gate en el mínimo observado sería inestable; este sigue atrapando
## la falla para la que existe, un raider que deja de caminar (0.08).
##
## Es un piso de cobertura (fracción 0-1): súbelo si el recorrido mejora,
## nunca lo bajes porque una partida quedó corta.
const FOG_MIN_EXPLORED: float = 0.09
## Golpes rechazados por Inmortalidad, guardados mientras la partida vive por
## la misma razón que la niebla: _exit_tree corre cuando el raider ya no está.
var _blocked_hits_seen: int = 0
## Última lectura de niebla tomada con la partida viva. _exit_tree corre en el
## cierre, cuando el RunSystems dueño de la niebla ya no existe, así que el
## resumen informa lo medido y no lo que queda.
var _explored_seen: float = 0.0
## Segundos entre pulsaciones de Tab, y cuánto queda abierto el mapa.
const MAP_OVERLAY_INTERVAL: float = 60.0
const MAP_OVERLAY_HOLD: float = 2.0
var _map_overlay_left: float = MAP_OVERLAY_INTERVAL
var _map_overlay_close_left: float = 0.0
## El mapa se refresca en su propio _process, que cae en un frame idle
## DESPUÉS de este de física; leer la cuenta de inmediato informaría el mapa
## de antes de abrirse.
const MAP_OVERLAY_REPORT_DELAY: float = 0.5
var _map_overlay_report_left: float = 0.0
var _map_overlay_open: bool = false

## True cuando se le ordenó al recorrido dejar todo e ir al portal de salida
## (ver _tick_stage_flow); se rearma en cada cambio de etapa.
var _exit_rush: bool = false
## --- variables de power-ups e instrumentación -------------------------------
## BONK_POWERUP_NOW=<id>: se entrega en este tiempo de partida y se renueva
## apenas expira. No es un ciclo de pickups: la idea es mantener UN efecto
## activo todo un soak corto para ejercitar sus casos borde.
const POWERUP_NOW_AT: float = 20.0
## BONK_POWERUP_AT reemplaza la línea de arriba; -1 significa "usar el valor por defecto".
var _powerup_at: float = POWERUP_NOW_AT
## BONK_STAR_NOW=1 suelta su estrella en este tiempo de partida.
const STAR_NOW_AT: float = 30.0
## Enemigos muestreados por frame durante un congelamiento. Tres alcanzan para
## atrapar un cuerpo que se movió sin recorrer toda la horda en cada frame.
const TIME_STOP_SAMPLE: int = 3
## Cuánto (metros) puede derivar un cuerpo congelado y aún contar como quieto.
## Nada debería moverse; esto es ruido de punto flotante, no algo que ajustar.
const TIME_STOP_EPSILON: float = 0.01

## Soak de vuelo: mantener salto tanto tiempo, cada tanto (segundos). Lo
## bastante para subir al techo y pasar sobre las celdas bloqueadas para las
## que existe la regla de aterrizaje.
const FLIGHT_HOLD_PERIOD: float = 15.0
const FLIGHT_HOLD_TIME: float = 5.0
var _flight_holding: bool = false

## El tope de sirvientes actual, sumado sobre TODO el grupo, o 0 si nadie
## lleva el báculo. Se lee del arma para que una carta de mejora o la
## evolución lo muevan, y para que el possessed=a/b del soak pruebe que a
## nunca supera a b. Es del grupo y no del líder porque possessed= cuenta
## cada sirviente del grupo.
func _possession_cap() -> int:
	var cap := 0
	for body: Node3D in _party_bodies():
		var mount := body.get_node_or_null("Weapons")
		if mount == null:
			continue
		for child: Node in mount.get_children():
			var staff := child as NecroStaff
			if staff != null:
				cap += staff.max_possessed
	return cap


## BONK_ITEM_NOW: ítems que se dan al slot 0 una vez, en este tiempo de partida.
const ITEM_NOW_AT: float = 10.0
## Con esa variable el recorrido hace DASH a este ritmo (segundos). El cinturón
## eléctrico no tiene otro disparador, y la caminata normal nunca hace dash (el
## dash es sprint mantenido más un deseo de movimiento).
const ITEM_DASH_PERIOD: float = 3.0
## Sprint debe mantenerse a través de un borde de frame (segundos) para que
## Player._can_start_slide lo vea junto con un deseo de movimiento.
const ITEM_DASH_HOLD: float = 0.12
var _item_now: Array[String] = []
var _items_granted: bool = false
var _dash_left: float = ITEM_DASH_PERIOD
var _dash_holding: bool = false

## BONK_ZENKAI_TEST: la caída y supervivencia que arma Zenkai, puesta en este
## tiempo de partida. Al azar necesita que un raider casi muera y luego se
## cure, cosa que un soak con godmode nunca hace.
const ZENKAI_TEST_AT: float = 60.0
## Segundos de invulnerabilidad entre el golpe y la cura, para que nada
## remate al raider entre medio.
const ZENKAI_TEST_SHIELD: float = 3.0
var _zenkai_test: bool = false
var _zenkai_stage: int = 0
var _zenkai_left: float = 0.0
## Health.invulnerable como lo dejó PowerUps; se restaura tras el golpe de prueba.
var _zenkai_invulnerable: bool = false

## BONK_WEATHER_NOW: se fuerza una vez, en este tiempo de partida. Lo bastante
## tarde para que la arena y sus luces estén cacheadas, y lo bastante pronto
## para que incluso un soak de 240 s vea la fila entera y su continuación.
## Precargado, no por nombre de clase: world_director.gd no declara
## class_name, y su weather_row() estático reenvía a
## WeatherDirector.weather_row (scripts/world/run/director/weather_director.gd).
const WEATHER_DIRECTOR := preload("res://scripts/world/run/world_director.gd")
const WEATHER_NOW_AT: float = 30.0
var _weather_now: String = ""
var _weather_forced: bool = false
## Último id de clima visto activo, para atrapar el frame en que el canal se
## vacía sin que el director tenga que avisarlo.
var _weather_seen: String = ""

## BONK_POI_NOW: POI que se sueltan junto al raider una vez, en POI_NOW_AT.
const POI_NOW_AT: float = 20.0
## Se colocan a esta distancia (metros) del raider: fuera del anillo de
## interacción para que el recorrido camine el último paso, y lo bastante
## cerca para que lo haga en un tramo.
const POI_NOW_RADIUS: float = 8.0
var _poi_now: Array[String] = []
var _poi_spawned: bool = false

var _powerup_now: String = ""
var _star_now: bool = false
var _star_dropped: bool = false
## Cuenta del congelamiento de una ventana de time_stop, impresa al descongelar.
var _freeze_active: bool = false
var _freeze_sampled: int = 0
var _freeze_moved: int = 0
var _freeze_damage_events: int = 0
## instance id -> posición en que este cuerpo se muestreó congelado por última vez.
var _freeze_positions: Dictionary[int, Vector3] = {}
## Cuenta de gusanos en la misma ventana, en su propia línea. Un Duneburrower
## BAJO TIERRA sale del grupo "enemies" a propósito, así que el conjunto
## congelado del spawner no lo contiene y `moved` de arriba no lo ve. Se
## recorren los hijos del spawner en vez de un grupo para verlo igual.
var _worms_sampled: int = 0
var _worms_moved: int = 0
## Muestras en que un gusano BURROWED no estaba en el conjunto congelado del
## spawner. Es la aserción de estado, la que no depende de la suerte: `moved`
## necesita que el gusano se esté deslizando justo al muestrearlo, `loose`
## solo que esté bajo tierra mientras el tiempo está detenido.
var _worms_loose: int = 0
var _worm_positions: Dictionary[int, Vector3] = {}
## Duneburrower.State.BURROWED, por valor: el probe no puede nombrar el enum
## sin acoplarse a ese script, y el orden es estable (SURFACED, BURROWED,
## ERUPTING), la misma suposición que hace el detector de vuelo con ERUPTING.
const BURROWER_BURROWED: int = 1
## Health del raider líder, conectado una vez para contar el daño enemigo
## durante un congelamiento.
var _lead_health: Health = null

var _bounds: Node3D = null
var _in_blocked_cell: bool = false
var _blocked_cell: Vector2i = Vector2i.ZERO
var _blocked_stay: float = 0.0
var _blocked_reported: bool = false


func _ready() -> void:
	# ANTES que todo: RunState.stage_changed se emite para la etapa 1 dentro del
	# add_child() de abajo y le pide un frame a esta cámara, así que si se crea
	# más abajo sería null cuando toca la primera foto.
	_camera = ShotCamera.new(get_viewport())
	_perf = PerfMeter.new(get_tree())
	# Nunca mezclar un soak con el guardado real: SaveData apunta a un archivo
	# temporal (valores por defecto) antes de arrancar la arena. BONK_SAVE_PATH
	# gana si está definido, para que tools/verificar.sh le dé a cada soak su
	# PROPIO archivo nuevo: el compartido user://soak_save.json arrastra el
	# bestiario y los contadores de armas usadas de un soak al siguiente.
	var save_override := OS.get_environment(SaveData.SAVE_PATH_ENV)
	SaveData.save_path = save_override if not save_override.is_empty() \
			else DEFAULT_SAVE_PATH
	SaveData.load_from_disk()
	# Settings aplicó el preset gráfico del JUGADOR al arrancar, antes de este
	# cambio de archivo: un soak con ventana renderizaría con lo que diga el
	# guardado real mientras el log informa el preset del guardado temporal.
	Settings.apply_graphics()
	print("ArenaProbe: save=%s" % SaveData.save_path)
	# BONK_CHARACTER=<id> elige el raider (por defecto: lo que diga la config).
	# Un id desconocido es ERROR, no se ignora: un soak pensado para un raider
	# que corre en silencio el de por defecto da verde sobre código que no tocó.
	var character := OS.get_environment("BONK_CHARACTER")
	if not character.is_empty():
		if CharacterCatalog.by_id(character).is_empty():
			push_error("ArenaProbe: unknown BONK_CHARACTER '%s'" % character)
		else:
			GameConfig.selected_character_id = character
	print("ArenaProbe: character=%s" % GameConfig.selected_character_id)
	# BONK_ARENA es una RUTA DE ESCENA por compatibilidad, pero lo que elige es
	# el bioma inicial: el probe siempre arranca Run.tscn, que es dueño de la
	# partida y cambia de arena en cada etapa.
	var path := OS.get_environment("BONK_ARENA")
	if path.is_empty():
		path = DEFAULT_ARENA
	GameConfig.start_map_id = _map_id_for_scene(path)
	var scene := load(RUN_SCENE) as PackedScene
	if scene == null:
		push_error("ArenaProbe: cannot load '%s'" % RUN_SCENE)
		get_tree().quit(1)
		return
	RunState.stage_changed.connect(_on_stage_changed)
	# ANTES de instanciar la partida: Player._apply_character lo lee mientras
	# aparece el raider, así que si se define después llega tarde.
	var weapon_id := OS.get_environment("BONK_WEAPON")
	if not weapon_id.is_empty():
		Player.starting_weapon_override = weapon_id
		print("ArenaProbe: weapon=%s" % weapon_id)
	# ANTES de instanciar la partida, por la misma razón que el arma:
	# RunSystems._spawn_party lee Coop.player_count en su propio _ready, así que
	# un grupo configurado después de esta línea es una partida solo.
	_configure_party()
	# ANTES de instanciar la partida: el preset llega al sol de la primera
	# etapa por RunState.stage_changed, que se emite dentro de add_child.
	# Un valor desconocido es ERROR, como BONK_CHARACTER: un soak pensado para
	# Media que corre en Alta en silencio es un log verde sobre nada.
	# Se escribe en SaveData sin Settings.set_graphics_quality, así que nada se
	# persiste: un soak manual con el guardado temporal compartido no debe
	# dejar al siguiente en un preset que nadie pidió.
	var graphics := OS.get_environment("BONK_GRAPHICS")
	if not graphics.is_empty():
		if not graphics.is_valid_int() \
				or graphics.to_int() < 0 or graphics.to_int() > SaveData.MAX_GRAPHICS_QUALITY:
			push_error("ArenaProbe: BONK_GRAPHICS must be 0-%d, got '%s'"
					% [SaveData.MAX_GRAPHICS_QUALITY, graphics])
		else:
			SaveData.graphics_quality = graphics.to_int()
			Settings.apply_graphics()
			print("ArenaProbe: graphics=%d" % SaveData.graphics_quality)
	add_child(scene.instantiate())
	# Los soaks mortales terminan con la muerte: RunManager pausa el árbol y la
	# pantalla de fin no se juega sola en headless, así que sin esto el probe se
	# quedaría en su aviso de TRABA el resto de sus frames. Por el grupo, como
	# todo acceso entre escenas.
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended"):
		manager.connect("run_ended", _on_run_ended)
	_walking = OS.get_environment("BONK_WALK") != "0"
	_debug = OS.get_environment("BONK_PROBE_DEBUG") == "1"
	var seed_text := OS.get_environment("BONK_SEED")
	if seed_text.is_valid_int():
		_rng.seed = int(seed_text)
	else:
		_rng.randomize()
	# BONK_GODMODE=1: un raider ocioso muere en menos de un minuto, lo que
	# oculta todo sistema tardío (jefes, hordas, altares); una vida enorme deja
	# correr el reloj completo. Solo interruptor del arnés, nunca del juego.
	if OS.get_environment("BONK_GODMODE") == "1":
		_apply_godmode.call_deferred()
	if OS.get_environment("BONK_ELITE_BOOST") == "1":
		_apply_elite_boost.call_deferred()
	_stage_fast = OS.get_environment("BONK_STAGE_FAST") == "1"
	_powerup_now = OS.get_environment("BONK_POWERUP_NOW")
	if not _powerup_now.is_empty() and PowerUpCatalog.by_id(_powerup_now).is_empty():
		push_error("ArenaProbe: unknown BONK_POWERUP_NOW '%s'" % _powerup_now)
		_powerup_now = ""
	var powerup_at := OS.get_environment("BONK_POWERUP_AT")
	if powerup_at.is_valid_float():
		_powerup_at = maxf(powerup_at.to_float(), 0.0)
	_star_now = OS.get_environment("BONK_STAR_NOW") == "1"
	_weather_now = OS.get_environment("BONK_WEATHER_NOW")
	if not _weather_now.is_empty() \
			and WEATHER_DIRECTOR.weather_row(_weather_now).is_empty():
		push_error("ArenaProbe: unknown BONK_WEATHER_NOW '%s'" % _weather_now)
		_weather_now = ""
	var poi_list := OS.get_environment("BONK_POI_NOW")
	if not poi_list.is_empty():
		for entry: String in poi_list.split(",", false):
			_poi_now.append(entry.strip_edges())
	var item_list := OS.get_environment("BONK_ITEM_NOW")
	if not item_list.is_empty():
		for entry: String in item_list.split(",", false):
			_item_now.append(entry.strip_edges())
	_zenkai_test = OS.get_environment("BONK_ZENKAI_TEST") == "1"
	_swap_menu = OS.get_environment("BONK_SWAP_MENU") == "1"
	# Se vigila solo donde puede pasar, para que el log de los demás soaks no cambie.
	for entry: String in _item_now:
		if entry.begins_with("saiyan_blood"):
			_saiyan_watch = true
	var points_text := OS.get_environment("BONK_POINTS")
	if points_text.is_valid_int():
		_grant_points.call_deferred(int(points_text))
	var down_text := OS.get_environment("BONK_DOWN_NOW")
	if down_text.is_valid_float():
		_down_now_at = maxf(down_text.to_float(), 0.0)
		_down_next = _down_now_at
	var lucky_list := OS.get_environment("BONK_LUCKY_REWARD")
	if not lucky_list.is_empty():
		var wanted: Array[String] = []
		for entry: String in lucky_list.split(",", false):
			wanted.append(entry.strip_edges())
		LuckyBlock.force_rewards(wanted)
		print("ArenaProbe: lucky rewards %s" % ", ".join(wanted))
	print("ArenaProbe: arena=%s walk=%s" % [path.get_file(), _walking])
	# Se cuenta en los GRUPOS, no en la variable: importa cuántos raiders creó
	# de verdad RunSystems, y un grupo que quedó corto es justo lo que esta
	# línea existe para mostrar.
	_report_party.call_deferred()


## Lo que el recorrido necesita de cada etapa: la espera que deja a la rampa
## pseudo-infinita registrar un minuto antes de que el grupo salga, y el
## evento de cielo disparado poco después de cada cambio. Ese evento es una
## PRUEBA, no decorado: WorldDirector.on_stage_started hace que
## WeatherDirector.begin_stage vuelva a buscar el Sun de la arena nueva, y
## una luna de sangre que no tiñe nada delata una referencia vieja a la luz.
func _tick_stage_flow(delta: float) -> void:
	if RunState.stage_cleared and not _stage_cleared_seen:
		_stage_cleared_seen = true
		_dwell_left = PSEUDO_INFINITE_DWELL if _stage_fast else 0.0
	elif not RunState.stage_cleared:
		_stage_cleared_seen = false
	_dwell_left = maxf(_dwell_left - delta, 0.0)
	if RunState.stage_cleared and _dwell_left <= 0.0 and not _exit_rush:
		_exit_rush = true
		# Abandona lo que estuviera haciendo el recorrido. El portal de salida cae
		# a 40 m o más y el soak tiene reloj fijo; terminar la espera y el tramo
		# actuales puede gastar 25 s en un cofre.
		_linger_left = 0.0
		_leg_time_left = 0.0
	if _sky_probe_left > 0.0:
		_sky_probe_left = maxf(_sky_probe_left - delta, 0.0)
		if _sky_probe_left <= 0.0:
			get_tree().call_group("world_director", "start_sky_event", "blood_moon")


## Id de MapCatalog cuya escena de arena es `scene_path`; el mapa por defecto
## si la ruta no existe, así un error de tipeo prueba el bosque en vez de caerse.
func _map_id_for_scene(scene_path: String) -> String:
	for row: Dictionary in MapCatalog.MAP_LIBRARY:
		if String(row.scene_path) == scene_path:
			return String(row.id)
	return MapCatalog.DEFAULT_ID


## Un cambio de etapa reemplaza toda la arena: cada estado por id de este
## arnés apunta a nodos liberados, y el mapa nuevo tiene su propia máscara,
## así que el barrido tiene que volver a correr.
func _on_stage_changed(stage_index: int, map_id: String) -> void:
	_target = null
	_visited.clear()
	_seen_stage_index = stage_index
	_swept = false
	_sweep_at_frame = _frames + SWEEP_FRAME
	_blocked_stay = 0.0
	_blocked_reported = false
	_rising_for.clear()
	_sky_probe_left = STAGE_SKY_DELAY
	_dwell_left = 0.0
	_exit_rush = false
	print("ArenaProbe: stage %d is %s" % [stage_index + 1, map_id])
	_request_settled_shot(SHOT_SETTLE, "stage%d" % (stage_index + 1))


## BONK_ELITE_BOOST=1: todo spawn sale brillante. Por el grupo, como toda
## llamada entre escenas del proyecto.
func _apply_elite_boost() -> void:
	get_tree().call_group("enemy_spawner", "force_elite_spawns", true)
	print("ArenaProbe: elite boost on")


## El líder recibe la reserva de diez millones; los seguidores reciben
## FOLLOWER_GODMODE_HP, de la que todavía pueden caer. Con todo el grupo
## inmortal BONK_DOWN_NOW no podría pegar y el camino de caída y revivir (la
## regla co-op que ningún soak solo alcanza) no se ejercitaría. El líder
## sigue inmortal porque un líder muerto termina el recorrido.
func _apply_godmode() -> void:
	for body: Node3D in _party_bodies():
		var health := Health.find_in(body)
		if health == null:
			continue
		var leader := int(body.get("player_index")) == 0
		health.max_hp = 10000000.0 if leader else FOLLOWER_GODMODE_HP
		health.heal_full()
	print("ArenaProbe: godmode on (slot 0 immortal, followers %.0f hp)"
			% FOLLOWER_GODMODE_HP)


## BONK_PLAYERS: fija el grupo en Coop ANTES de instanciar Run.tscn. Todos los
## slots usan el teclado: un soak no tiene mandos, y
## Coop._rebuild_slot_actions duplica los eventos de teclado por slot, así
## que p0_* y p1_* quedan como sets de acciones separados con las mismas
## teclas. Es justo lo que necesita el probe, que sintetiza acciones por
## nombre en vez de apretar teclas.
func _configure_party() -> void:
	var count_text := OS.get_environment("BONK_PLAYERS")
	if not count_text.is_valid_int():
		return
	_players = clampi(int(count_text), 1, Coop.MAX_PLAYERS)
	if _players <= 1:
		return
	var slot0 := GameConfig.selected_character_id
	var characters: Array[String] = [slot0]
	var second := OS.get_environment("BONK_CHARACTER2")
	if not second.is_empty() and CharacterCatalog.by_id(second).is_empty():
		push_error("ArenaProbe: unknown BONK_CHARACTER2 '%s'" % second)
		second = ""
	if second.is_empty():
		second = _next_character_id(slot0)
	characters.append(second)
	# Los slots 2 y 3 (verificar.sh no los usa, pero la variable acepta 1-4)
	# siguen recorriendo el catálogo para que dos slots no compartan raider.
	while characters.size() < _players:
		characters.append(_next_character_id(characters[characters.size() - 1]))
	var devices: Array[int] = []
	for i in _players:
		devices.append(Coop.KEYBOARD_DEVICE)
	Coop.configure(_players, devices, characters)


## La fila del catálogo después de `character_id`, dando la vuelta. No es al
## azar a propósito: un soak que cambia de raider entre partidas cambia lo
## que mide.
func _next_character_id(character_id: String) -> String:
	var rows := CharacterCatalog.CHARACTER_LIBRARY
	for i in rows.size():
		if String(rows[i].id) == character_id:
			return String(rows[(i + 1) % rows.size()].id)
	return String(rows[0].id)


## Tamaño del grupo leído de los GRUPOS después de RunSystems._spawn_party,
## nunca de la variable: un grupo que quedó corto (un slot que no apareció,
## un raider que murió en el primer frame) es justo lo que esta línea
## muestra, y la variable informaría el deseo.
func _report_party() -> void:
	var bodies := _party_bodies()
	var slot1 := "none"
	if _body_in_slot(1) != null:
		# Player no guarda id propio; Coop es donde se decidió el raider del slot,
		# y leerlo de vuelta prueba que el grupo se configuró antes de que
		# RunSystems lo creara.
		slot1 = Coop.character_for_slot(1)
	print("ArenaProbe: players=%d slot1=%s" % [bodies.size(), slot1])


## Cada raider, de pie o caído, ordenado por slot.
func _party_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and body.is_inside_tree():
				bodies.append(body)
	bodies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	return bodies


## El raider de un slot, de pie o caído, o null.
func _body_in_slot(slot: int) -> Node3D:
	for body: Node3D in _party_bodies():
		if int(body.get("player_index")) == slot:
			return body
	return null


## RunManager.run_ended: un soak mortal TERMINA aquí. Salir un momento
## después deja que las líneas del cierre ("Run ended:", "Run stages:",
## "Meta saved:") lleguen antes al log.
func _on_run_ended(victory: bool) -> void:
	_run_ended_at = RunState.run_time
	_run_end_left = RUN_END_QUIT_FRAMES
	print("Probe: run ended victory=%s" % victory)


## Se imprime una vez, al salir: un resumen que el script del soak puede leer.
func _exit_tree() -> void:
	_camera.final_shot()
	_perf.summary()
	print("Probe bounty chests: max=%d cap=%d" % [_bounty_chests_max,
			EnemyBase.BOUNTY_CHEST_CAP])
	# Log de una línea (convención de RunManager) para soaks headless.
	print("Probe legs: reached=%d timed_out=%d" % [_legs_reached, _legs_timed_out])
	var explored := _explored_seen
	print("Probe fog: explored=%.2f" % explored)
	# Inmortalidad solo se prueba si un enemigo lo INTENTÓ: el contador vive en
	# Health, así que un soak que nunca recibió golpes informa 0 y la revisión
	# de aceptación falla, que es la idea.
	print("Immortal blocked: %d" % _blocked_hits_seen)
	# Cuenta co-op. Cero/cero en un soak solo, que es la lectura honesta: nada
	# cayó y nada se levantó.
	print("Party: downs=%d revives=%d" % [_party_downs, _party_revives])
	print("Party pets: %s" % _party_pets_seen)
	if _saiyan_watch:
		# Un aura son SAIYAN_BOONS_PER_AURA bonos. Más a la vez significa que un
		# re-disparo se apiló con el aura que debía reemplazar, y la primera
		# expiración devuelve solo una parte.
		print("Saiyan boons: max=%d of %d" % [_saiyan_max, SAIYAN_BOONS_PER_AURA])
	# Se omite con BONK_STAGE_FAST: ese soak reinicia la niebla cada minuto al
	# cruzar una etapa, así que su cobertura no dice nada de la caminata.
	# Se omite con BONK_POWERUP_NOW por lo mismo: esa variable mantiene UN
	# power-up todo el soak, un estado que ninguna partida real alcanza. Con
	# time_stop la horda nunca entra en rango de las armas, nada muere, no cae
	# XP y el recorrido se arrastra; la cobertura mide la variable, no la
	# caminata. El gate conserva toda su fuerza donde se calibró: en cada soak
	# de tools/verificar.sh, ninguno de los cuales define esas variables.
	# Tercera excepción, SEMÁNTICA y no de variable: una partida terminada no
	# puede explorar. Un soak mortal termina con la muerte del raider, así que
	# su fracción dice cuánto vivió, no qué tan bien camina el recorrido. La
	# omisión nunca es silenciosa: la línea de abajo lo dice, y
	# tools/verificar.sh hace fallar cualquier soak GODMODE que la imprima,
	# porque una partida con godmode no tiene por qué terminar.
	if _run_ended_at >= 0.0:
		print("Probe fog: skipped (run ended at %.1fs)" % _run_ended_at)
	elif not _stage_fast and _powerup_now.is_empty() and explored < FOG_MIN_EXPLORED:
		push_warning("ArenaProbe: fog barely explored — %.2f < %.2f"
				% [explored, FOG_MIN_EXPLORED])



## Un campo por slot: la mascota que lleva cada raider. Se muestrea CON LA
## PARTIDA VIVA, como la fracción de niebla, porque _exit_tree corre en el
## cierre cuando los raiders ya no están.
## El vendedor y la caja de mascota le dan la mascota a quien pagó, y en
## co-op es la única forma de ver que el pago llegó al comprador.
func _party_pets_text() -> String:
	var text := ""
	for body: Node3D in _party_bodies():
		var pet: Variant = body.get("pet_id")
		var id := String(pet) if pet != null else ""
		text += "p%d=%s " % [int(body.get("player_index")),
				id if not id.is_empty() else "none"]
	return text.strip_edges() if not text.is_empty() else "none"


func _sample_blocked_hits() -> void:
	var pets := _party_pets_text()
	if pets != "none":
		_party_pets_seen = pets
	var lead := _lead_player()
	if lead == null:
		return
	var health := Health.find_in(lead)
	if health != null:
		_blocked_hits_seen = health.blocked_hits


func _explored_fraction() -> float:
	var fog := FogOfWar.find(get_tree())
	if fog != null:
		_explored_seen = fog.explored_fraction()
	return _explored_seen


## Abre el mapa de Tab cada MAP_OVERLAY_INTERVAL segundos y lo cierra
## MAP_OVERLAY_HOLD después. No es adorno: el mapa es un Control que compone
## una imagen y recorre el grupo de marcadores, y esto es lo único que
## ejercita ese camino en un soak.
func _tick_map_overlay(delta: float) -> void:
	if _map_overlay_open:
		if _map_overlay_report_left > 0.0:
			_map_overlay_report_left -= delta
			if _map_overlay_report_left <= 0.0:
				_report_map_markers()
		_map_overlay_close_left -= delta
		if _map_overlay_close_left <= 0.0:
			_map_overlay_open = false
			_send_action(0, &"map_overlay", true)
			_release_map_overlay.call_deferred()
			print("Map overlay: closed")
		return
	_map_overlay_left -= delta
	if _map_overlay_left > 0.0:
		return
	_map_overlay_left = MAP_OVERLAY_INTERVAL
	_map_overlay_open = true
	_map_overlay_close_left = MAP_OVERLAY_HOLD
	_map_overlay_report_left = MAP_OVERLAY_REPORT_DELAY
	_send_action(0, &"map_overlay", true)
	_release_map_overlay.call_deferred()
	_request_settled_shot(SHOT_SETTLE_MAP, "map")


func _release_map_overlay() -> void:
	_send_action(0, &"map_overlay", false)


## Cantidad de marcadores del mapa del slot 0, MAP_OVERLAY_REPORT_DELAY después
## de la pulsación: el mapa se refresca en su propio _process idle, que cae
## después de este frame de física, y leerlo antes informa el mapa de antes
## de abrirse (markers=0).
func _report_map_markers() -> void:
	var markers := 0
	for node: Node in get_tree().get_nodes_in_group(&"map_overlay"):
		if int(node.get("slot")) == 0 and node.has_method(&"marker_count"):
			markers = int(node.call(&"marker_count"))
			break
	print("Map overlay: open markers=%d" % markers)


## --- capturas ---------------------------------------------------------------

## Nombre de la foto periódica. Es un Callable porque el nombre lleva el
## reloj de la partida, que solo se conoce cuando toca la foto.
func _periodic_shot_stem() -> String:
	return "shot_%.1fs" % RunState.run_time


## Los eventos de la partida que valen un frame cada uno, leídos del ÁRBOL y
## no de los print de los sistemas (un print no es algo a lo que otro nodo se
## pueda suscribir). Un vendedor es un miembro nuevo de su grupo; la caja de
## mascota y el lucky block se anuncian con la señal de Interactable que ya
## emiten; un power-up es un id que el líder no llevaba en la muestra anterior.
func _watch_shot_events() -> void:
	if not _camera.enabled():
		return
	for node: Node in get_tree().get_nodes_in_group(&"vendors"):
		var id := node.get_instance_id()
		if _shot_seen.has(id):
			continue
		_shot_seen[id] = true
		_request_shot("vendor_%s" % String(node.get("kind")))
	_watch_shot_interactables(&"pet_boxes", "petbox")
	_watch_shot_interactables(&"lucky_blocks", "lucky")
	var lead := _lead_player()
	var powerups := PowerUps.find_in(lead) if lead != null else null
	if powerups == null:
		return
	var live: Dictionary[String, bool] = {}
	for row: Dictionary in powerups.active():
		var id := String(row.id)
		live[id] = true
		if not _shot_powerups.has(id):
			_request_shot("powerup_%s" % id)
	_shot_powerups = live


## Una conexión por nodo de `group`, para que la foto caiga cuando la cosa se
## USA y no cuando aparece: una caja sin abrir no es la foto de una caja
## abriéndose.
func _watch_shot_interactables(group: StringName, tag: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		var id := node.get_instance_id()
		if _shot_seen.has(id):
			continue
		_shot_seen[id] = true
		var spot := node as Interactable
		if spot != null:
			spot.interaction_completed.connect(_request_shot.bind(tag))


## Encola una foto de evento, nombrada con el tiempo de partida en que ocurrió.
func _request_shot(tag: String) -> void:
	_camera.request("%s_%s" % [_periodic_shot_stem(), tag])


## Segundos que espera una foto de "cómo se ve" tras su evento. El mapa se abre
## el frame después de Tab, el tinte del clima entra en cerca de un segundo y
## un cambio de etapa va detrás del corte de ScreenFade, así que una foto del
## frame del evento muestra siempre el momento ANTERIOR.
const SHOT_SETTLE: float = 1.5
const SHOT_SETTLE_MAP: float = 0.6


func _request_settled_shot(delay: float, tag: String) -> void:
	_camera.request_in(delay, "%s_%s" % [_periodic_shot_stem(), tag])


## Frames dibujados, no ticks de física: el medidor cronometra lo que espera un jugador.
func _process(_delta: float) -> void:
	_perf.tick()


func _physics_process(delta: float) -> void:
	_frames += 1
	# Un soak mortal termina apenas RunManager lo dice; la cuenta regresiva solo
	# existe para que las líneas de log del cierre lleguen antes de salir.
	if _run_end_left >= 0:
		_run_end_left -= 1
		if _run_end_left < 0:
			get_tree().quit(0)
			return
	if not _swept and _frames >= _sweep_at_frame:
		_swept = true
		_run_mask_sweep()
	_tick_stage_flow(delta)
	_tick_map_overlay(delta)
	_watch_shot_events()
	_camera.tick(delta, _periodic_shot_stem)
	_tick_party(delta)
	_tick_swap_menu(delta)
	_watch_saiyan_boons()
	_tick_powerup_switches()
	_tick_item_now(delta)
	_tick_zenkai_test(delta)
	_watch_time_stop()
	_watch_airborne(delta)
	_watch_blocked_cell(delta)
	if _frames % 120 == 0:
		# Solo se le AGREGAN campos al final, nunca se reordena: verificar.sh lee
		# level= de la última de estas líneas.
		print(("frame %d paused=%s run_time=%.1f active=%s enemies=%d level=%d"
				+ " airborne=%d explored=%.2f possessed=%d/%d") % [
				_frames, get_tree().paused, RunState.run_time, RunState.run_active,
				get_tree().get_node_count_in_group("enemies"), RunState.level,
				_airborne_total, _explored_fraction(),
				get_tree().get_node_count_in_group(&"possessed"), _possession_cap()])
		_sample_blocked_hits()
		_bounty_chests_max = maxi(_bounty_chests_max,
				EnemyBase.unopened_bounty_chests(get_tree()))
	var card_ui_open := false
	for node: Node in get_tree().get_nodes_in_group("upgrade_ui"):
		var ui := node as CanvasLayer
		if ui != null and ui.visible and ui.has_method("_on_card_pressed"):
			card_ui_open = true
			# ANTES del clic, y solo para el primer selector del soak: este arnés
			# responde la carta el mismo frame en que aparece, así que la única
			# pantalla que un level-up pone frente al jugador nunca se fotografiaría.
			# El clic NO se retrasa: se pide la foto, se responde la carta y la cámara
			# guarda lo que tenga el siguiente frame dibujado.
			if not _card_shot_taken:
				_card_shot_taken = true
				_request_shot("card")
			ui.call("_on_card_pressed", 0)
	_watch_for_wedge(delta, card_ui_open)
	if _walking and not get_tree().paused:
		_drive_walk(delta)


## --- variables de power-ups ------------------------------------------------

## BONK_POWERUP_NOW / BONK_STAR_NOW. La renovación es lo que hace útil un soak
## corto: una sola ventana de veinte segundos dejaría a un soak de 120 s con
## ochenta segundos de juego normal, y las revisiones de aceptación solo
## significan algo con el efecto activo.
func _tick_powerup_switches() -> void:
	if RunState.run_time < _powerup_at:
		return
	var lead := _lead_player()
	if lead == null:
		return
	if not _powerup_now.is_empty():
		var powerups := PowerUps.find_in(lead)
		if powerups != null and not powerups.is_active(_powerup_now):
			powerups.apply(_powerup_now)
	_tick_flight_hold()
	_tick_poi_now()
	_tick_weather_now()
	_watch_weather_end()
	if _star_now and not _star_dropped and RunState.run_time >= STAR_NOW_AT:
		_star_dropped = true
		var spawner := get_tree().get_first_node_in_group("enemy_spawner")
		if spawner != null and spawner.has_method("spawn_powerup_pickup"):
			# A los pies del raider y QUIETA: la estrella que deambula es difícil de
			# alcanzar a propósito, y esta variable existe para probar el pickup y su
			# efecto, no la persecución.
			var star := spawner.call("spawn_powerup_pickup",
					lead.global_position + Vector3.UP * 0.6, "star") as Node3D
			if star != null:
				star.set("roaming", false)


## Vuelo hay que VOLARLO para probarlo: el power-up solo hace algo mientras
## se mantiene la acción de salto. Depende de la variable que lo entregó:
## los demás soaks conservan la caminata normal, porque un recorrido que
## salta cada quince segundos sería otro recorrido.
func _tick_flight_hold() -> void:
	if _powerup_now != "flight":
		return
	var cycle := fmod(RunState.run_time, FLIGHT_HOLD_PERIOD)
	var want_hold := cycle < FLIGHT_HOLD_TIME
	if want_hold == _flight_holding:
		return
	_flight_holding = want_hold
	_send_action(0, &"jump", want_hold)


## BONK_ITEM_NOW: da los ítems de la lista una vez y luego mantiene al
## recorrido haciendo dash para que el cinturón eléctrico tenga con qué disparar.
func _tick_item_now(delta: float) -> void:
	if _item_now.is_empty():
		return
	var lead := _lead_player()
	if lead == null:
		return
	if not _items_granted and RunState.run_time >= ITEM_NOW_AT:
		_items_granted = true
		var bag := ItemBag.find_in(lead)
		if bag != null:
			for entry: String in _item_now:
				var parts := entry.split(":", false)
				var item_id := parts[0]
				var copies := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 1
				if ItemCatalog.by_id(item_id).is_empty():
					push_error("ArenaProbe: unknown BONK_ITEM_NOW '%s'" % item_id)
					continue
				for i in copies:
					bag.add_item(item_id)
				print("ArenaProbe: granted item %s x%d" % [item_id, copies])
	if not _items_granted:
		return
	_dash_left -= delta
	if _dash_holding:
		if _dash_left <= 0.0:
			_dash_holding = false
			_dash_left = ITEM_DASH_PERIOD
			_send_action(0, &"sprint", false)
		return
	if _dash_left <= 0.0:
		_dash_holding = true
		_dash_left = ITEM_DASH_HOLD
		_send_action(0, &"sprint", true)


## BONK_ZENKAI_TEST: baja al raider al 5% de su vida máxima, lo protege unos
## segundos para que nada lo remate y luego lo cura entero. Esa caída y
## recuperación son justo las dos señales con que Zenkai se arma y se dispara.
func _tick_zenkai_test(delta: float) -> void:
	if not _zenkai_test:
		return
	var lead := _lead_player()
	if lead == null:
		return
	var health := Health.find_in(lead)
	if health == null:
		return
	match _zenkai_stage:
		0:
			if RunState.run_time < ZENKAI_TEST_AT:
				return
			_zenkai_stage = 1
			_zenkai_left = ZENKAI_TEST_SHIELD
			# Invulnerabilidad APAGADA para el golpe: la señal que arma es damaged(), y
			# un golpe rechazado nunca la emite. Se guarda y se restaura en vez de
			# forzarla: la bandera pertenece a PowerUps._sync (Inmortalidad), y
			# combinar esta variable con ese power-up no debe cancelarlo.
			_zenkai_invulnerable = health.invulnerable
			health.invulnerable = false
			health.take_damage(health.max_hp * 0.95)
			health.invulnerable = true
		1:
			_zenkai_left -= delta
			if _zenkai_left > 0.0:
				return
			_zenkai_stage = 2
			health.heal_full()
			health.invulnerable = _zenkai_invulnerable
			print("ArenaProbe: zenkai test healed")


## Vigila el único espacio de clima del director e informa el desplazamiento
## del HUD apenas se vacía.
func _watch_weather_end() -> void:
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null:
		return
	var live: Variant = director.get("active_weather")
	var weather := live as Dictionary if live is Dictionary else {}
	var now := String(weather.get("id", "")) if not weather.is_empty() else ""
	if now == _weather_seen:
		return
	if not now.is_empty():
		_request_settled_shot(SHOT_SETTLE, "weather_%s" % now)
	if not _weather_seen.is_empty():
		_report_hud_offset()
		# La lluvia dorada es la única fila que escribe una FUENTE DE PUNTOS en cada
		# raider y un descuento de precios de toda la partida; ambos deben volver a
		# 1.00 el frame en que termina, también en el raider caído.
		if _weather_seen == "golden_rain":
			_report_points_sources()
	_weather_seen = now


## Los multiplicadores de puntos del grupo, un campo por slot. Se imprime
## cuando termina un clima que escribe puntos: una fuente olvidada no se ve
## en ningún otro log y paga mal el resto de la partida.
func _report_points_sources() -> void:
	var line := "Points sources:"
	for body: Node3D in _party_bodies():
		var factor: Variant = body.call("points_multiplier") \
				if body.has_method("points_multiplier") else null
		line += " p%d=%.2f" % [int(body.get("player_index")),
				float(factor) if factor != null else -1.0]
	print(line)


## El terremoto desplaza el CanvasLayer del HUD y tiene que devolverlo. Se lee
## en cada "Weather ended:" para que un soak lo pruebe, y se imprime aunque el
## clima no sea el terremoto: un desplazamiento distinto de cero tras CUALQUIER
## clima es una fuga.
func _report_hud_offset() -> void:
	for node: Node in get_tree().get_nodes_in_group("hud"):
		var hud := node as CanvasLayer
		if hud != null:
			print("HUD offset: %s" % hud.offset)
			return


## BONK_WEATHER_NOW: una invocación forzada. Por start_sky_event, la misma
## entrada forzada que usa el altar de eventos: corta lo que esté activo e
## ignora la pausa entre climas.
func _tick_weather_now() -> void:
	if _weather_forced or _weather_now.is_empty() or RunState.run_time < WEATHER_NOW_AT:
		return
	_weather_forced = true
	get_tree().call_group("world_director", "start_sky_event", _weather_now)


## BONK_POI_NOW: un anillo con los POI pedidos junto al raider. El director
## los ofrece a su propio ritmo, que tarda muchos minutos en producirlos
## todos; esto existe para que un soak corto pruebe de punta a punta cada
## puesto y la caja.
func _tick_poi_now() -> void:
	if _poi_spawned or _poi_now.is_empty() or RunState.run_time < POI_NOW_AT:
		return
	var lead := _lead_player()
	if lead == null:
		return
	_poi_spawned = true
	var terrain := Terrain.find(get_tree())
	for i in _poi_now.size():
		var angle := TAU * float(i) / float(_poi_now.size())
		var at := lead.global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * POI_NOW_RADIUS
		if terrain != null:
			at.y = terrain.height_at(at.x, at.z)
		var node := _build_poi(_poi_now[i])
		if node == null:
			push_error("ArenaProbe: unknown BONK_POI_NOW entry '%s'" % _poi_now[i])
			continue
		RunRoot.stage_parent(get_tree()).add_child(node)
		node.global_position = at
		print("ArenaProbe: placed POI %s" % _poi_now[i])


## Un POI por nombre, o null si el nombre no es uno que esta variable conozca.
func _build_poi(poi: String) -> Node3D:
	match poi:
		"pet_box":
			return load("res://scenes/world/PetBox.tscn").instantiate() as Node3D
		"event_altar":
			return load("res://scenes/world/shrines/EventAltar.tscn").instantiate() as Node3D
		"lucky_block":
			return load("res://scenes/world/chests/LuckyBlock.tscn").instantiate() as Node3D
		"vendor_items", "vendor_powerups", "vendor_animals":
			var vendor := load("res://scenes/world/Vendor.tscn").instantiate() as Node3D
			# Se define antes de entrar al árbol: Vendor._ready lo lee.
			vendor.set("kind", poi.trim_prefix("vendor_"))
			return vendor
	return null


## BONK_POINTS: una bolsa inicial para el slot 0. Diferido para que exista el Player.
func _grant_points(amount: int) -> void:
	var lead := _lead_player()
	if lead != null and lead.has_method("add_points"):
		lead.call("add_points", amount)
		print("ArenaProbe: granted %d points" % amount)


## Tiempo detenido: mientras el spawner mantiene un congelamiento, muestrea
## unos cuerpos congelados por frame e informa al descongelar. `moved` y
## `damage_events` son las dos formas en que un congelamiento miente (un
## cuerpo que siguió caminando, o uno que aún pegó) y ambas deben dar cero.
func _watch_time_stop() -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	var frozen := spawner != null and spawner.has_method("is_frozen") \
			and bool(spawner.call("is_frozen"))
	if frozen and not _freeze_active:
		_freeze_active = true
		_freeze_sampled = 0
		_freeze_moved = 0
		_freeze_damage_events = 0
		_freeze_positions.clear()
		_worms_sampled = 0
		_worms_moved = 0
		_worms_loose = 0
		_worm_positions.clear()
		_connect_lead_health()
	elif not frozen and _freeze_active:
		_freeze_active = false
		print("Time stop: sampled=%d moved=%d damage_events=%d"
				% [_freeze_sampled, _freeze_moved, _freeze_damage_events])
		# Línea aparte, nunca un campo de la de arriba: ese formato es la interfaz
		# de verificación de tres soaks y está congelado.
		print("Time stop worms: sampled=%d moved=%d loose=%d"
				% [_worms_sampled, _worms_moved, _worms_loose])
		return
	if not frozen:
		return
	var bodies: Array = spawner.call("frozen_bodies")
	_watch_frozen_worms(spawner as Node, bodies)
	for i in mini(TIME_STOP_SAMPLE, bodies.size()):
		var body := bodies[i] as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		if _freeze_positions.has(id):
			if body.global_position.distance_to(_freeze_positions[id]) > TIME_STOP_EPSILON:
				_freeze_moved += 1
			_freeze_sampled += 1
		_freeze_positions[id] = body.global_position


## Cada Duneburrower bajo el spawner, congelado o no: uno enterrado no está
## en NINGÚN grupo, así que solo se encuentra recorriendo los hijos del
## spawner. `_erupt` es el duck-typing: el probe no puede nombrar el script
## sin acoplarse a él, igual que el detector de vuelo con su enum de estado.
func _watch_frozen_worms(spawner: Node, frozen: Array) -> void:
	if spawner == null:
		return
	var frozen_ids: Dictionary[int, bool] = {}
	for node: Variant in frozen:
		var body := node as Node
		if body != null and is_instance_valid(body):
			frozen_ids[body.get_instance_id()] = true
	for child: Node in spawner.get_children():
		var body := child as Node3D
		if body == null or not body.is_inside_tree() or not body.has_method(&"_erupt"):
			continue
		var health := Health.find_in(body)
		if health != null and health.is_dead:
			# Un cuerpo que murió dentro de la ventana se suelta a propósito
			# (EnemyBase._on_died le devuelve el procesamiento), así que su deslizamiento
			# al morir no es un congelamiento que se escapó.
			continue
		var id := body.get_instance_id()
		var state: Variant = body.get("_state")
		if state != null and int(state) == BURROWER_BURROWED and not frozen_ids.has(id):
			_worms_loose += 1
		if _worm_positions.has(id):
			_worms_sampled += 1
			if body.global_position.distance_to(_worm_positions[id]) > TIME_STOP_EPSILON:
				_worms_moved += 1
		_worm_positions[id] = body.global_position


## Cuenta el daño de origen enemigo al raider líder mientras dura un
## congelamiento. Se conecta una vez y queda conectado: el Health del raider
## sobrevive a cada congelamiento, y reconectar por ventana contaría doble.
func _connect_lead_health() -> void:
	if _lead_health != null and is_instance_valid(_lead_health):
		return
	var lead := _lead_player()
	if lead == null:
		return
	_lead_health = Health.find_in(lead)
	if _lead_health != null and not _lead_health.damaged.is_connected(_on_lead_damaged):
		_lead_health.damaged.connect(_on_lead_damaged)


func _on_lead_damaged(_amount: float, _current: float) -> void:
	if _freeze_active:
		_freeze_damage_events += 1


## El LÍDER es el cuerpo con player_index 0, nunca "el primer nodo del grupo":
## con dos raiders el orden del grupo es el orden de aparición, y cada
## ayudante que guía, da godmode o lee "el raider" seguiría en silencio al
## que quedó primero.
func _lead_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body := node as Node3D
		if body != null and int(body.get("player_index")) == 0:
			return body
	return null


## Una pasada por la horda viva: los cuerpos que llevan bastante tiempo
## subiendo sin tocar el suelo son el bug de "enemigos voladores", y cada uno
## avisa una vez. Corre aunque el árbol esté pausado (los contadores no
## avanzan, porque nada se mueve) y se poda contra el grupo vivo para que un
## cuerpo liberado no mantenga un temporizador viejo.
func _watch_airborne(delta: float) -> void:
	if get_tree().paused:
		return
	var live: Dictionary[int, bool] = {}
	# "possessed" además de "enemies": los sirvientes no están en el grupo
	# enemies, y dejarlos fuera sacaría hasta max_possessed cuerpos por portador
	# de un detector cuya razón de ser es que no se pueda silenciar.
	var bodies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	bodies.append_array(get_tree().get_nodes_in_group(&"possessed"))
	for node: Node in bodies:
		var body := node as CharacterBody3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		if live.has(id):
			continue
		live[id] = true
		if _airborne_seen.has(id):
			continue
		if not _is_rising(body):
			_rising_for.erase(id)
			continue
		var elapsed := float(_rising_for.get(id, 0.0)) + delta
		_rising_for[id] = elapsed
		if elapsed < AIRBORNE_TIME:
			continue
		_airborne_seen[id] = true
		_airborne_total += 1
		push_warning("ArenaProbe: enemy airborne — %s rose %.1f m/s for %.1fs off the floor"
				% [body.name, body.velocity.y, elapsed])
	for id: int in _rising_for.keys():
		if not live.has(id):
			_rising_for.erase(id)


## True mientras este cuerpo sube por el aire con su propia velocidad hacia
## arriba y NO es uno de los dos que pueden: un enemigo en su estado de
## trepar (subiendo un muro o un prop) o un Duneburrower en plena erupción.
func _is_rising(body: CharacterBody3D) -> bool:
	if body.is_on_floor() or body.velocity.y <= AIRBORNE_RISE_SPEED:
		return false
	if bool(body.get("_climbing")):
		return false
	var state: Variant = body.get("_state")
	if state != null and int(state) == BURROWER_ERUPTING and body.has_method("_erupt"):
		return false
	return true


## Metros entre un cuerpo y el suelo bajo él.
func _height_above_ground(at: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	return at.y - (terrain.height_at(at.x, at.z) if terrain != null else 0.0)


## (a) Recorre cada borde que una celda bloqueada comparte con una CAMINABLE
## en pasos de SWEEP_STEP, con la cápsula del jugador a caballo sobre la
## línea del borde. Una muestra que no toca geometría del mundo es una
## abertura: un hueco por el que el raider entra a suelo que la máscara da
## por inalcanzable. Nunca aflojes esto: lo que tiene que ceder es la
## colocación de rocas (scatter.gd y rock_formation.gd).
func _run_mask_sweep() -> void:
	var bounds := _arena_bounds()
	if bounds == null:
		push_warning("ArenaProbe: mask sweep skipped — no arena_bounds node with blocked_cells()")
		return
	var cells := _blocked_cells(bounds)
	var cell_size := float(bounds.call("cell_size"))
	var steps := maxi(int(round(cell_size / SWEEP_STEP)), 1)
	var capsule := CapsuleShape3D.new()
	capsule.radius = SWEEP_CAPSULE_RADIUS
	capsule.height = SWEEP_CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = WORLD_COLLISION_LAYER
	# Se excluyen los raiders, que comparten la capa 1 con el mundo: un cuerpo
	# parado en un borde respondería por la roca que falta ahí. Y el terreno:
	# el suelo es geometría de capa 1, así que con un heightmap debajo cada
	# muestra tocaría algo y el barrido informaría un mapa perfecto que nunca
	# probó. Rocas, props y muros siguen contando, que es para lo que existe.
	var excluded := _raider_rids()
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		excluded.append(terrain.get_rid())
	query.exclude = excluded
	var space := bounds.get_world_3d().direct_space_state
	var samples := 0
	var openings := 0
	var named := 0
	for cell: Vector2i in cells:
		var center: Vector2 = bounds.call("cell_center", cell)
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not bool(bounds.call("is_walkable", bounds.call("cell_center", cell + dir))):
				continue
			var normal := Vector2(float(dir.x), float(dir.y))
			var along := Vector2(-normal.y, normal.x)
			var edge := center + normal * (cell_size * 0.5)
			for i in steps + 1:
				var spot := edge + along * ((float(i) / float(steps) - 0.5) * cell_size)
				samples += 1
				# Centrada sobre el SUELO en ese punto, no a una altura absoluta: en una
				# loma una altura fija quedaría dentro del terreno y en una hondonada
				# flotaría sobre las rocas.
				var ground := terrain.height_at(spot.x, spot.y) if terrain != null else 0.0
				query.transform = Transform3D(Basis(),
						Vector3(spot.x, ground + SWEEP_CAPSULE_CENTER_Y, spot.y))
				if not space.intersect_shape(query, 1).is_empty():
					continue
				openings += 1
				if named < SWEEP_REPORT_LIMIT:
					named += 1
					push_warning("ArenaProbe: mask opening at (%.1f, %.1f) — cell (%d, %d), edge (%d, %d)"
							% [spot.x, spot.y, cell.x, cell.y, dir.x, dir.y])
	print("Mask sweep: blocked=%d samples=%d openings=%d" % [cells.size(), samples, openings])
	if openings > 0:
		push_warning("ArenaProbe: mask sweep found %d opening(s) in %d samples over %d blocked cells"
				% [openings, samples, cells.size()])


## (b) El raider líder parado EN EL SUELO dentro de una celda bloqueada
## durante BLOCKED_CELL_GRACE segundos seguidos. La altura separa "entró por
## un hueco" de "está sobre una roca, una plataforma o una meseta en una
## celda bloqueada", que está bien: el temporizador solo corre a nivel del
## suelo y el aviso pertenece a la ENTRADA, así que un raider atascado que
## sigue saltando avisa una vez y no una por aterrizaje.
func _watch_blocked_cell(delta: float) -> void:
	if get_tree().paused:
		return
	var bounds := _arena_bounds()
	var lead := _lead_raider()
	if bounds == null or lead == null:
		_leave_blocked_cell()
		return
	var flat := Vector2(lead.global_position.x, lead.global_position.z)
	if bool(bounds.call("is_walkable", flat)):
		_leave_blocked_cell()
		return
	var cell: Vector2i = bounds.call("cell_of", flat)
	if not _in_blocked_cell or cell != _blocked_cell:
		_in_blocked_cell = true
		_blocked_cell = cell
		_blocked_stay = 0.0
		_blocked_reported = false
	if _height_above_ground(lead.global_position) > FLOOR_STAND_MAX_Y:
		_blocked_stay = 0.0
		return
	_blocked_stay += delta
	if _blocked_stay < BLOCKED_CELL_GRACE or _blocked_reported:
		return
	_blocked_reported = true
	push_warning("ArenaProbe: raider inside blocked cell (%d, %d) — stood at (%.1f, %.1f, %.1f) for %.1fs"
			% [_blocked_cell.x, _blocked_cell.y, lead.global_position.x,
			lead.global_position.y, lead.global_position.z, _blocked_stay])


func _leave_blocked_cell() -> void:
	_in_blocked_cell = false
	_blocked_stay = 0.0
	_blocked_reported = false


## El nodo de límites de la arena (scatter.gd), por el grupo como toda
## búsqueda entre escenas aquí. En caché: ambos guardias preguntan cada frame.
func _arena_bounds() -> Node3D:
	if is_instance_valid(_bounds):
		return _bounds
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		var bounds := node as Node3D
		if bounds != null and bounds.has_method("blocked_cells"):
			_bounds = bounds
			return bounds
	return null


## Duck-typing a propósito: scatter.gd no tiene class_name, así que el
## retorno llega como Variant y cada elemento se revisa antes de entrar a un
## arreglo tipado.
func _blocked_cells(bounds: Node3D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var raw: Variant = bounds.call("blocked_cells")
	if not (raw is Array):
		return cells
	for item: Variant in (raw as Array):
		if item is Vector2i:
			cells.append(item)
	return cells


## RIDs de física de cada raider, de pie o caído: el barrido pregunta por la
## geometría del mundo, y un raider está en su misma capa de colisión.
func _raider_rids() -> Array[RID]:
	var rids: Array[RID] = []
	var groups: Array[StringName] = [&"player", &"downed_players"]
	for group: StringName in groups:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if body != null and body.is_inside_tree():
				rids.append(body.get_rid())
	return rids


func _lead_raider() -> CharacterBody3D:
	var lead := _lead_player() as CharacterBody3D
	if lead == null or not lead.is_inside_tree():
		return null
	return lead


## Una UI bloqueante que nunca se cierra (ruleta, fin de partida) congela
## run_time mientras el contador de frames sigue subiendo, así que el soak
## parece sano sin correr nada. Se informa una vez, fuerte para un grep.
func _watch_for_wedge(delta: float, card_ui_open: bool) -> void:
	if not get_tree().paused or card_ui_open:
		_paused_for = 0.0
		return
	_paused_for += delta
	if _paused_for >= PAUSE_WEDGE_WARN and not _wedge_reported:
		_wedge_reported = true
		# Solo los bloqueantes VISIBLES: toda pantalla del grupo es miembro esté o
		# no en pantalla, y listarlas todas apunta al culpable equivocado.
		var blockers: Array[String] = []
		for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
			var shown: Variant = node.get("visible")
			if shown == null or bool(shown):
				blockers.append(node.name)
		push_warning("ArenaProbe: WEDGE — tree paused %.0fs with no card UI; blocking=%s"
				% [_paused_for, blockers])


## XZ de una posición del mundo. Toda distancia de este recorrido es plana:
## con relieve, las diferencias de altura no son avance.
func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## Guía al raider líder hacia el punto actual MANTENIENDO LAS ACCIONES REALES
## DE MOVIMIENTO. Escribir velocity no sirve: Player la reconstruye desde
## Input.get_vector() en cada frame de física y luego llama move_and_slide(),
## así que una velocidad escrita se pisa antes de mover nada. Apretar las
## acciones además ejercita el camino real de entrada (deslizar, condición de
## sprint, base de órbita libre) en vez de saltárselo.
func _drive_walk(delta: float) -> void:
	var lead := _lead_raider()
	if lead == null:
		_release_move()
		_release_holds()
		return
	# Un compañero caído dentro de REVIVE_NOTICE_RANGE supera al objetivo
	# actual, la espera y la carrera a la salida: el grupo sale junto o la
	# regla co-op que este soak existe para probar nunca corre.
	if _drive_rescue(lead, delta):
		return
	if _linger_left > 0.0:
		_linger_left -= delta
		_release_move()
		_interact_timer -= delta
		if _interact_timer <= 0.0:
			_interact_timer = INTERACT_INTERVAL
			_press_interact()
		return
	_leg_time_left -= delta
	# "Llegó" es la condición del propio juego (dentro del Area3D del objetivo,
	# que habilita el aviso y la interacción), no un radio fijo. Un cofre en
	# una loma queda a 4-5 m en horizontal y nunca pasaría una prueba de
	# distancia aun siendo interactuable.
	var reached := _flat(lead.global_position).distance_to(_flat(_waypoint)) <= WAYPOINT_REACHED
	if is_instance_valid(_target) and _target.player_in_range:
		reached = true
	if _waypoint == Vector3.ZERO or _leg_time_left <= 0.0 or reached:
		if reached:
			_legs_reached += 1
			# Quieto al llegar: los altares Charge necesitan una canalización sin
			# cortes y los cofres necesitan que llegue la pulsación de interactuar.
			_linger_left = LINGER_TIME
			_interact_timer = 0.0
			_release_move()
			_pick_waypoint(lead.global_position)
			return
		_legs_timed_out += 1
		if _debug:
			print("ArenaProbe: leg timed out %.1fm short of %v"
					% [_flat(lead.global_position).distance_to(_flat(_waypoint)), _waypoint])
		_pick_waypoint(lead.global_position)
	_hold_move_toward(lead, _waypoint)
	_unstick(lead, delta)


## Salta cuando se estanca el avance horizontal. Bordes, rampas y muros de
## máscara se leen todos como "caminar contra algo"; sin salto el recorrido
## nunca llega a los cofres puestos en puntos de verticalidad.
func _unstick(lead: CharacterBody3D, delta: float) -> void:
	_stall_check -= delta
	if _stall_check > 0.0:
		return
	_stall_check = STALL_WINDOW
	var moved := lead.global_position.distance_to(_last_position)
	_last_position = lead.global_position
	if moved > STALL_DISTANCE:
		return
	var jump := Coop.action(0, &"jump")
	Input.action_press(jump)
	Input.action_release.bind(jump).call_deferred()


## Convierte un rumbo del mundo en acciones de movimiento mantenidas. Player
## arma su dirección deseada como `transform.basis * Vector3(input.x, 0, input.y)`,
## así que el rumbo tiene que volver por la base del propio cuerpo.
func _hold_move_toward(body: CharacterBody3D, to: Vector3, slot: int = 0) -> void:
	var heading := to - body.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		_release_move(slot)
		return
	var local := body.transform.basis.inverse() * heading.normalized()
	_hold_axis(slot, &"move_right", &"move_left", local.x)
	_hold_axis(slot, &"move_back", &"move_forward", local.z)


func _hold_axis(slot: int, positive: StringName, negative: StringName, amount: float) -> void:
	var forward := Coop.action(slot, positive)
	var backward := Coop.action(slot, negative)
	if amount >= 0.0:
		Input.action_press(forward, absf(amount))
		Input.action_release(backward)
	else:
		Input.action_press(backward, absf(amount))
		Input.action_release(forward)


func _release_move(slot: int = 0) -> void:
	for base: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(Coop.action(slot, base))


## Sintetiza una pulsación real de "interact" para que altares, cofres,
## portales y disparadores secretos se resuelvan por su propio
## _unhandled_input (Interactable._unhandled_input). La liberación tiene que
## caer en un frame POSTERIOR a la pulsación: con ambas en el mismo vaciado
## la acción nunca se lee como "recién apretada".
func _press_interact() -> void:
	if _debug:
		var touching: Array[String] = []
		for node: Node in _all_interactables(get_tree().current_scene):
			var spot := node as Interactable
			if spot != null and spot.player_in_range:
				touching.append("%s(available=%s)" % [spot.name, spot.available])
		print("ArenaProbe: interact press; in range: %s" % [touching])
	_send_interact(true)
	_release_interact.call_deferred()


func _release_interact() -> void:
	_send_interact(false)


func _send_interact(pressed: bool) -> void:
	_send_action(0, &"interact", pressed)


## Una pulsación sintetizada para un SLOT. Un InputEventAction PARSEADO, no
## Input.action_press: un handler _unhandled_input solo ve el parseado, e
## Input.is_action_just_pressed ve ambos. En co-op el slot decide el SET de
## acciones (p0_* o p1_*), y eso hace funcionar el revivir: PlayerRevive.tick
## consulta la acción de interactuar del RESCATADOR, así que una pulsación
## enviada como slot 0 nunca revive a nadie si el que está junto al cuerpo es
## el slot 1.
func _send_action(slot: int, base: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = Coop.action(slot, base)
	event.pressed = pressed
	Input.parse_input_event(event)


## Modo MANTENER: deja una acción apretada entre frames hasta soltarla. Un
## revivir necesita PlayerRevive.revive_time (3 s) mantenido SIN PAUSA, algo
## que el patrón apretar/soltar-al-frame-siguiente no logra.
##
## Se REAFIRMA cada frame contra el estado real de Input, no se guarda como
## bool: el toque de interactuar del propio recorrido encola su liberación
## con call_deferred, y esa liberación puede caer DESPUÉS de que empezó un
## mantener en el mismo frame. Con una bandera en caché el líder "mantendría"
## una acción ya suelta y quedaría parado sobre su compañero caído mientras
## la barra de revivir decae: una traba del arnés que parece bug del juego.
func _hold_action(slot: int, base: StringName, held: bool) -> void:
	var key := "%d/%s" % [slot, base]
	if held:
		_held[key] = true
		if not Input.is_action_pressed(Coop.action(slot, base)):
			_send_action(slot, base, true)
		return
	if not bool(_held.get(key, false)):
		return
	_held[key] = false
	_send_action(slot, base, false)


## Suelta toda acción mantenida. Se llama cuando lo que se mantenía
## desaparece, para que un mantener no sobreviva a su razón.
func _release_holds() -> void:
	for key: String in _held.keys():
		if not bool(_held[key]):
			continue
		var parts := key.split("/", false)
		_send_action(int(parts[0]), StringName(parts[1]), false)
	_held.clear()


## Próximo destino: el Interactable disponible más cercano que este recorrido
## no visitó recién, para que un soak gaste puntos en cofres y cargue altares;
## un punto caminable al azar cuando todos están gastados o probados hace poco.
func _pick_waypoint(from: Vector3) -> void:
	_leg_time_left = LEG_TIMEOUT
	# El recorrido puede trabajar un área chica (ahí está el botín), pero no
	# para siempre: una horda que suelta más rápido de lo que la caminata
	# consume puede dejar al raider en una burbuja de 20 m todo un soak, con la
	# exploración congelada. Tras BUBBLE_LEGS tramos que nunca salieron de
	# BUBBLE_RADIUS desde donde empezó la racha, el próximo punto es un PASEO al
	# azar, haya lo que haya a los pies del raider.
	# ...pero NO durante la carrera a la salida. Un paseo forzado ahí aleja al
	# recorrido del único objetivo que la carrera existe para alcanzar, y el
	# portal cae a 40 m o más del grupo a propósito. Nada supera a la carrera
	# salvo un compañero caído.
	var roaming_forced := false if _exit_rush else _bubble_expired(from)
	# Un power-up en el suelo supera a todo lo cercano: es gratis, vence en
	# 45 s y pasar por encima es toda la interacción (sin pulsar, sin esperar).
	# Solo si está CERCA: un recorrido que cruzara el mapa por cada drop dejaría
	# de recorrer.
	# NO supera a la carrera a la salida: con un drop cada pocos segundos el
	# desvío ganaría siempre y el grupo nunca cruzaría, que es lo único que la
	# carrera existe para garantizar.
	var pickup := _nearest_pickup(from) if not _exit_rush and not roaming_forced else null
	if pickup != null:
		_target = null
		_waypoint = pickup.global_position
		if _debug:
			print("ArenaProbe: heading to power-up %s at %.1fm"
					% [pickup.get("powerup_id"), _flat(from).distance_to(_flat(_waypoint))])
		return
	var target := _nearest_interactable(from) if not roaming_forced else null
	_target = target
	if target != null:
		_visited[target.get_instance_id()] = RunState.run_time
		_waypoint = target.global_position
		if _debug:
			print("ArenaProbe: heading to %s at %.1fm (available=%s)"
					% [target.name, _flat(from).distance_to(_flat(_waypoint)), target.available])
		return
	# Prefiere la máscara caminable de la propia arena, para que ningún punto
	# caiga dentro de las celdas bloqueadas que recorta la máscara irregular.
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		if node.has_method("random_walkable_point"):
			var point: Variant = node.call("random_walkable_point")
			if point is Vector2:
				_waypoint = Vector3(point.x, from.y, point.y)
				if _debug:
					print("ArenaProbe: no fresh interactable, roaming to %v" % _waypoint)
				return
	var half := FALLBACK_HALF_EXTENT
	_waypoint = Vector3(_rng.randf_range(-half, half), from.y, _rng.randf_range(-half, half))


## BONK_SWAP_MENU: dispara un cambio de etapa el frame en que un menú
## bloqueante cerrable tiene la pausa, y luego informa si el árbol volvió.
## Esas capas cuelgan de la ARENA, así que el cambio las libera sin que corra
## su _close(), y _close() es el único lugar donde devuelven la pausa.
func _tick_swap_menu(delta: float) -> void:
	if not _swap_menu:
		return
	if _swap_menu_fired:
		_swap_menu_left -= delta
		if _swap_menu_left <= 0.0:
			_swap_menu = false
			print("Swap menu: paused=%s" % get_tree().paused)
		return
	if not get_tree().paused:
		return
	var open := false
	for node: Node in get_tree().get_nodes_in_group(&"blocking_ui_closable"):
		var shown: Variant = node.get("visible")
		if shown == null or bool(shown):
			open = true
			break
	if not open:
		return
	_swap_menu_fired = true
	_swap_menu_left = SWAP_MENU_REPORT
	print("Swap menu: firing a stage swap at %.1fs" % RunState.run_time)
	get_tree().call_group("run_root", "advance_stage")


## Cuenta los bonos con etiqueta SAIYAN en el líder. Lee la lista privada en
## vez de agregar un accesor al código del juego: el arnés ya lee estado
## privado por duck-typing en otros lados (_climbing, _state), y el número
## solo existe para probar un contrato de etiqueta que nada más puede observar.
func _watch_saiyan_boons() -> void:
	if not _saiyan_watch:
		return
	var lead := _lead_player()
	if lead == null:
		return
	var stats := PlayerStats.find_in(lead)
	if stats == null:
		return
	var raw: Variant = stats.get("_timed_boons")
	if not (raw is Array):
		return
	var tagged := 0
	for entry: Variant in (raw as Array):
		if entry is Dictionary and String((entry as Dictionary).get("tag", "")) == SAIYAN_TAG:
			tagged += 1
	_saiyan_max = maxi(_saiyan_max, tagged)


## --- grupo co-op ------------------------------------------------------------

## Todo lo que necesitan los slots extra, una vez por frame de física: la
## caída forzada, la caminata de los seguidores y la cuenta de caídas y
## revividas que el soak informa al final.
func _tick_party(delta: float) -> void:
	_watch_party_downs()
	if _players <= 1:
		return
	_tick_forced_down()
	_tick_followers(delta)


## BONK_DOWN_NOW: un golpe letal al slot 1, a un ritmo fijo. Al azar, una
## caída necesita que la horda elija al seguidor, algo que un soak no puede
## esperar, y sin caída no hay revivir que probar. El slot 1 es mortal justo
## porque _apply_godmode solo cubre el slot 0.
func _tick_forced_down() -> void:
	if _down_now_at < 0.0 or RunState.run_time < _down_next:
		return
	_down_next = RunState.run_time + DOWN_NOW_PERIOD
	var body := _body_in_slot(1)
	if body == null or body.is_in_group(&"downed_players"):
		return
	var health := Health.find_in(body)
	if health == null or health.is_dead:
		return
	# Invulnerabilidad apagada para el golpe, igual que en la prueba zenkai: un
	# golpe rechazado nunca llega a Player._on_health_died.
	health.invulnerable = false
	health.take_damage(health.max_hp * 2.0)
	print("ArenaProbe: forced down p1 at %.1fs" % RunState.run_time)


## Los slots 1+ SIGUEN y nunca interactúan. Dos raiders recorriendo
## duplicarían las cuentas de interacción con que se calibró cada gate de
## verificar.sh, y el soak co-op existe para las REGLAS co-op (aparición del
## grupo, pantalla dividida, XP compartida, caídas, revividas), no para un
## segundo recorrido.
func _tick_followers(delta: float) -> void:
	var lead := _lead_raider()
	for slot: int in range(1, _players):
		var body := _body_in_slot(slot) as CharacterBody3D
		if body == null or not body.is_inside_tree() \
				or body.is_in_group(&"downed_players"):
			_release_move(slot)
			continue
		if lead != null and _flat(body.global_position) \
				.distance_to(_flat(lead.global_position)) > FOLLOW_DISTANCE:
			_follow_left[slot] = 0.0
			_hold_move_toward(body, lead.global_position, slot)
			continue
		# Lo bastante cerca: tramos cortos al azar, para que el seguidor no sea una
		# estatua sobre la cabeza del líder. Su código de movimiento, el interés de
		# la horda en él y la vista de pantalla dividida siguen corriendo.
		var left := float(_follow_left.get(slot, 0.0)) - delta
		if left <= 0.0:
			left = FOLLOW_LEG_TIME
			var angle := _rng.randf() * TAU
			_follow_to[slot] = body.global_position \
					+ Vector3(cos(angle), 0.0, sin(angle)) * FOLLOW_LEG_RANGE
		_follow_left[slot] = left
		_hold_move_toward(body,
				_follow_to.get(slot, body.global_position) as Vector3, slot)


## Cuenta las entradas y salidas de "downed_players". Una revivida solo
## cuenta cuando el cuerpo VOLVIÓ al grupo: un cuerpo que salió del grupo
## porque terminó la partida no es un rescate.
func _watch_party_downs() -> void:
	var live: Dictionary[int, bool] = {}
	for node: Node in get_tree().get_nodes_in_group(&"downed_players"):
		var id := node.get_instance_id()
		live[id] = true
		if not _down_seen.has(id):
			_down_seen[id] = true
			_party_downs += 1
	for id: int in _down_seen.keys():
		if live.has(id):
			continue
		_down_seen.erase(id)
		var body := instance_from_id(id) as Node
		if body != null and is_instance_valid(body) and body.is_in_group(&"player"):
			_party_revives += 1


## El cuerpo caído que el líder debe ir a levantar, o null. De corto alcance a
## propósito: un rescate que cruzara el mapa reemplazaría al recorrido.
func _nearest_downed(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := REVIVE_NOTICE_RANGE * REVIVE_NOTICE_RANGE
	var flat_from := _flat(from)
	for node: Node in get_tree().get_nodes_in_group(&"downed_players"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var gave_up: float = _rescue_given_up.get(body.get_instance_id(), -INF)
		if RunState.run_time - gave_up < RESCUE_COOLDOWN:
			continue
		var distance := flat_from.distance_squared_to(_flat(body.global_position))
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## LA regla que supera a todo, _exit_rush incluido: un grupo no abandona a
## su caído. Devuelve true mientras controla la caminata.
## Lo que importa es mantener: PlayerRevive.tick pide revive_time segundos de
## interactuar SIN PAUSA desde el set de acciones del RESCATADOR, algo que
## apretar y soltar al frame siguiente nunca logra.
func _drive_rescue(lead: CharacterBody3D, delta: float) -> bool:
	var body := _nearest_downed(lead.global_position)
	if body == null:
		if _rescue_target != null:
			_rescue_target = null
			_hold_action(0, &"interact", false)
			_pick_waypoint(lead.global_position)
		return false
	if body != _rescue_target:
		_rescue_target = body
		_rescue_time = 0.0
		# Deja lo que estuviera haciendo el recorrido, como la carrera a la salida.
		_target = null
		_linger_left = 0.0
		_leg_time_left = LEG_TIMEOUT
		if _debug:
			print("ArenaProbe: rescuing %s at %.1fm" % [body.name,
					_flat(lead.global_position).distance_to(_flat(body.global_position))])
	_rescue_time += delta
	if _rescue_time >= RESCUE_TIMEOUT:
		_rescue_given_up[body.get_instance_id()] = RunState.run_time
		_rescue_target = null
		_hold_action(0, &"interact", false)
		# Un PRINT y no un aviso: abandonar un cuerpo que ahora no se alcanza es una
		# decisión que este recorrido puede tomar (la horda empuja al líder, el
		# cuerpo está detrás de una roca), y el raider se levanta en una pasada
		# posterior. El gate que importa es "at least one Player revived:" de
		# verificar.sh, que un rescate que nunca funciona sigue haciendo fallar.
		print("ArenaProbe: gave up rescuing %s after %.0fs"
				% [body.name, _rescue_time])
		_pick_waypoint(lead.global_position)
		return false
	if _flat(lead.global_position).distance_to(_flat(body.global_position)) \
			> REVIVE_APPROACH:
		_hold_action(0, &"interact", false)
		_hold_move_toward(lead, body.global_position)
		_unstick(lead, delta)
		return true
	_release_move()
	_hold_action(0, &"interact", true)
	return true


## Tramos que el recorrido puede pasar dentro de una burbuja antes de que se
## le obligue a pasear, y el tamaño (metros) de esa burbuja. Ocho tramos es
## más de lo que toma un grupo de cofres; 25 m es un poco más que el desvío
## por pickups, así que una racha de pickups cuenta como una burbuja.
const BUBBLE_LEGS: int = 8
const BUBBLE_RADIUS: float = 25.0
var _bubble_origin: Vector3 = Vector3.ZERO
var _bubble_legs: int = 0
var _bubble_started: bool = false


## True cuando este tramo debe ser un PASEO porque los últimos BUBBLE_LEGS
## quedaron dentro de BUBBLE_RADIUS desde donde empezó la racha. Reinicia la
## racha al dispararse, así el recorrido vuelve a la normalidad después.
func _bubble_expired(from: Vector3) -> bool:
	if not _bubble_started or _flat(from).distance_to(_flat(_bubble_origin)) > BUBBLE_RADIUS:
		_bubble_started = true
		_bubble_origin = from
		_bubble_legs = 0
		return false
	_bubble_legs += 1
	if _bubble_legs < BUBBLE_LEGS:
		return false
	_bubble_legs = 0
	_bubble_origin = from
	if _debug:
		print("ArenaProbe: bubble expired, roaming")
	return true


## El pickup de power-up vivo más cercano dentro de PICKUP_DETOUR de `from`, o null.
func _nearest_pickup(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := PICKUP_DETOUR * PICKUP_DETOUR
	var flat_from := _flat(from)
	for node: Node in get_tree().get_nodes_in_group(&"powerup_pickups"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree() or body.is_queued_for_deletion():
			continue
		var distance := flat_from.distance_squared_to(_flat(body.global_position))
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## El interactuable disponible más cercano no probado dentro de
## REVISIT_COOLDOWN. Sin esa espera el recorrido rebota para siempre entre
## los dos puntos más cercanos (un altar gastado pero aún `available` sigue
## siendo lo más cercano del mapa).
func _nearest_interactable(from: Vector3) -> Interactable:
	# Con la etapa completada (y la espera terminada) el portal de salida supera
	# a todo: un recorrido que sigue comprando cofres nunca cruza una etapa, y
	# cruzar es lo que este arnés tiene que probar. La distancia y la espera de
	# revisita se ignoran a propósito.
	if RunState.stage_cleared and _dwell_left <= 0.0:
		for node: Node in _all_interactables(get_tree().current_scene):
			var way_out := node as ExitPortal
			if way_out != null and way_out.available and way_out.is_inside_tree():
				return way_out
	var nearest: Interactable = null
	var nearest_dist := INF
	for node: Node in _all_interactables(get_tree().current_scene):
		var spot := node as Interactable
		if spot == null or not spot.available or not spot.is_inside_tree():
			continue
		var tried_at: float = _visited.get(spot.get_instance_id(), -INF)
		if RunState.run_time - tried_at < REVISIT_COOLDOWN:
			continue
		var dist := from.distance_to(spot.global_position)
		if dist <= WAYPOINT_REACHED or dist >= nearest_dist:
			continue
		nearest_dist = dist
		nearest = spot
	return nearest


func _all_interactables(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child: Node in root.get_children():
		if child is Interactable:
			found.append(child)
		found.append_array(_all_interactables(child))
	return found
