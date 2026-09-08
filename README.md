# Bonkraiders

Roguelite de supervivencia "bullet-heaven" en 3D hecho en Godot 4.7 (GDScript): incursiones sin límite de tiempo que recorren **un mapa tras otro**: superas una etapa sobreviviendo 15 minutos y matando a su jefe, se abre un portal de salida, te quedas cuanto quieras en modo **pseudo-infinito** (la dificultad sube rápido) y cruzas al mapa siguiente con todo lo que llevas donde las armas disparan solas, los enemigos llegan en hordas crecientes y cada subida de nivel ofrece 3 cartas de mejora. Arenas de **240×240 con relieve** (colinas, hondonadas y mesetas), con **minimapa** en la esquina de cada vista y **mapa completo con Tab** sobre una niebla de guerra que el equipo destapa caminando. Incluye tres biomas (Bosque Hueco, Dunas de Ceniza y Ciénaga Lóbrega) con jefes propios y minijefes secretos, 13 raiders con arma inicial y pasiva propia, 14 armas **que evolucionan por nivel**, 15 tomos, 16 objetos con rareza fija y 4 mascotas, dificultad por **vueltas** al circuito de mapas y meta-progresión entre incursiones (esquirlas, 40 misiones, desbloqueo de raiders, 6 reliquias permanentes de la Armería, pantalla de Colección, Cacería diaria con semilla por fecha). El diseño completo está en `GDD.md` y la historia de desarrollo en `CHANGELOG.md`.

**Idioma:** el juego está íntegramente en **español latinoamericano**. La terminología canónica vive en `docs/GLOSARIO.md` y es obligatoria para cualquier cadena nueva; los identificadores (ids de catálogo, `node_name`, grupos, `StringName`, claves de guardado y los `print()` de depuración) se quedan en inglés a propósito.

## Requisitos y ejecución

- **Godot 4.7.2** (el proyecto declara features `4.7` + Forward Plus). Sin plugins ni dependencias externas; todo el arte y audio es procedural/incluido.
- Ejecutar desde la raíz del proyecto:

```sh
godot --path .          # lanza el juego (escena principal: selector de raider)
godot -e --path .       # abre el editor
```

- Escena principal: `scenes/ui/CharacterSelect.tscn` (selector de raider y de party; los botones son **Iniciar incursión**, **Misiones**, **Ajustes**, **Colección**, **Armería** y **Cacería diaria**). Ya no hay selector de mapa ni de grado: toda partida empieza en el Bosque Hueco.
- La partida entera vive en **una** escena, `scenes/world/Run.tscn`, que instancia la arena de la etapa actual bajo `ArenaHost`. **Arrancar una arena directamente (F6 sobre `HollowWoods.tscn`) ya no funciona**: una arena es solo el mundo, sin jugador ni HUD.

### Controles

| Entrada | Acción | Acción de `project.godot` |
|---|---|---|
| WASD | Movimiento (relativo a la cámara) | `move_forward` / `move_back` / `move_left` / `move_right` |
| Mouse | Cámara en tercera persona (clic recaptura el cursor si se libera) | — (movimiento de mouse) |
| Espacio | Salto | `jump` |
| Shift (moviéndose) | Derrape (impulso de velocidad, colisión baja) | `sprint` |
| E | Interactuar (altares, cofres, portales, secretos) | `interact` |
| C | Cambiar cámara: tercera persona → primera persona → órbita libre | `camera_mode` |
| Rueda del mouse | Zoom (solo en cámara de órbita libre) | `camera_zoom_in` / `camera_zoom_out` |
| Tab | Abre el **mapa** de tu vista a pantalla completa (etapa, reloj, leyenda, estadísticas, party y objetos). No pausa la partida | `map_overlay` |
| Esc | Menú de pausa: **Continuar** / **Ajustes** / **Extraerse (terminar incursión)** — cierra la incursión y guarda / **Salir al menú** — abandona sin guardar nada | — (`ui_cancel`) |

**Modos de cámara** (por jugador, también en co-op; en control: click del stick derecho alterna, D-pad arriba/abajo hace zoom):
- **Tercera persona** — el modo clásico: mirar gira al raider.
- **Primera persona** — la cámara baja a los ojos y tu propia foca se oculta (solo en tu vista; tus compañeros te siguen viendo), con rango de pitch completo.
- **Órbita libre** — la cámara orbita alrededor del jugador con mouse/stick y zoom con rueda/D-pad; el raider camina hacia donde te mueves, independiente de hacia dónde mire la cámara (las armas apuntan solas, así que la orientación es cosmética).

Las armas disparan automáticamente al enemigo más cercano: no hay botón de ataque. Los mapeos viven en `project.godot`, sección `[input]`: `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `sprint`, `interact`, `camera_mode`, `camera_zoom_in`, `camera_zoom_out`, `map_overlay`. El menú de pausa usa `ui_cancel`, que es el mapeo por defecto de Godot (Esc). En co-op, el autoload `Coop` clona cada una de esas acciones por slot (`p1_*`, `p2_*`…) ligada solo al dispositivo de ese jugador.

**Control (también en solitario):** stick izquierdo = movimiento, stick derecho = cámara, A = salto, X o LB = derrape, Y = interactuar, click del stick derecho = cambiar cámara, D-pad arriba/abajo = zoom, BACK/Select = abrir el mapa, B/Start = navegación de menús (acciones `ui_*` por defecto de Godot). Cualquier control conectado sirve en solitario; el mouse y el control conviven.

## Co-op local (2-4 jugadores, pantalla dividida)

En la pantalla de selección hay una fila **Jugadores 1-4**: el jugador 1 usa teclado+mouse y cada jugador extra necesita su propio control conectado (la fila muestra cuántos hay y rechaza tamaños de grupo sin controles suficientes). Con 2+ jugadores aparece una fila de slots **J1..J4**: pulsar una carta de raider la asigna al slot resaltado y avanza al siguiente (se permiten raiders repetidos; las cartas muestran qué slots las eligieron). El botón de inicio pasa a decir **Iniciar incursión — N jugadores**.

En partida:

- **Pantalla dividida**: 2 jugadores = mitades arriba/abajo; 3-4 = rejilla 2x2 (`scripts/systems/split_screen.gd`, un `SubViewport` con cámara-espejo por jugador). Cada jugador conserva su cámara en tercera persona (mouse o stick derecho).
- **Entrada aislada por jugador**: el autoload `Coop` (`scripts/systems/coop.gd`) clona las acciones base como `p<slot>_*` ligadas solo al dispositivo de ese slot, así que dos controles nunca se pisan.
- **XP, nivel y muertes compartidos** (RunState no cambia); las gemas vuelan al jugador vivo más cercano. Las cartas de mejora se reparten **por turnos rotatorios** entre los jugadores en pie (el título indica a quién le toca) y se aplican a las armas/stats de ese jugador.
- **Caídos y reanimación**: al llegar a 0 HP un jugador queda **derribado** (no muerto): sus armas se apagan y los enemigos lo ignoran. Un compañero puede reanimarlo al 50% manteniendo su botón de interactuar a su lado ~3 s. La derrota solo llega cuando **todo** el equipo está derribado a la vez.
- **Enemigos y jefes** persiguen/aparecen alrededor de jugadores vivos aleatorios, repartiendo la presión; los interactuables responden al botón del jugador que realmente los pulsa.
- El HUD añade barras de vida compactas J2-J4 (con estado K.O.) junto a la barra principal del J1.

El modo solitario no cambia en nada: todo el sistema co-op se activa únicamente cuando `Coop.player_count > 1`.

## Mapa vivo y dificultad (iteración 33)

Cada partida es distinta y el mapa sigue dando cosas que hacer hasta el final:

- **Layout aleatorio por partida**: el scatter de props se re-siembra en cada run (`randomize_per_run` en `scripts/world/scatter.gd`) y el `WorldDirector` (`scripts/world/world_director.gd`, instanciado en `RunSystems.tscn`) recoloca los interactuables de suelo (altares, cofre de suelo, secretos enterrados) en posiciones aleatorias antes de que el scatter marque sus keepouts. Los cofres sobre plataformas no se mueven: escalar hasta ellos es el premio.
- **Eventos del mundo**: desde ~1:15 y cada 50-75 s el director lanza un evento anunciado en el banner del HUD: un **cofre de suministros** raro o mejor bajo un faro dorado (desaparece si nadie llega en 40 s), una **jauría shiny** que caza a un jugador aleatorio, una **fisura de esencia** (gemas de XP + orbe de vida bajo un faro verde), un **altar de carga** o **altar demoníaco** (ya no caducan: esperan a que llegues), o un **manantial**. Además, con cierta probabilidad (mayor tras usar altares demoníacos) llega un **evento de cielo**: Luna de Sangre (berserkers) o Eclipse (sombras), siempre seguido de una Luna Llena que da XP y suerte.

## Economía, objetos y altares (iteraciones 38-44)

- **Sin reloj**: la incursión sigue hasta morir o **extraerse** desde el menú de pausa; 15 minutos sobrevividos = victoria. Tras el Elder (min 11) vuelve un jefe cada 4 min, cada vez más fuerte; hay **hordas** en los minutos 3/7/10/13 y luego cada 3.
- **Puntos de partida** (por jugador, se reinician cada run): cada muerte paga puntos al raider más cercano (shiny x5, jefes 25). Sirven para abrir **cofres** (precio por rareza: 20/40/80/160, y cada cofre abierto encarece todos los demás x1.25), girar la **ruleta** (60) y beber del **manantial** (40).
- **Cofres gratis**: los que suelta un cuerpo (jefes y shiny), el del pacto demoníaco y ~15% de los del inicio no cuestan nada, **no encarecen** a los de pago y tiran su rareza **al abrirlos** con tu suerte, así que cualquier rareza es posible. Todo cofre se hunde después de entregar el premio.
- **Cofres** solo dan **objetos** (`scripts/systems/item_catalog.gd`): rareza fija por objeto, copias ilimitadas, independientes de armas y tomos. La suerte inclina la rareza del cofre. Ejemplos: Imán (aspira toda la XP periódicamente), Bolsa de pedos (veneno al golpear), Sangre de titán (creces y tus ataques cubren más área), Sangre de demonio, Llave maestra, Gusano cósmico, Máscara de superhéroe (arañas venenosas al matar) y huevos de **mascota** (Alienígena, Dinosaurio, Pájaro furioso, Capibara: te siguen, llevan un arma propia fuera del tope de 5 armas y dan un stat por nivel).
- **Altares**: el de **carga** se carga solo al estar dentro de un anillo **tres veces más grande**, que **se marca y late** cuando te acercas; salir solo **pausa** la carga (nada se pierde, nada caduca) y al completarlo eliges **1 de 3 bendiciones** que van a toda la party, independientes de las cartas; el **demoníaco** ofrece **pactos**: cada carta trae un **beneficio** (boon grande, puntos, o un cofre gratis ahí mismo) y su **costo** (dificultad permanente, más shiny, lunas más largas o más frecuentes, desastres). Todo altar se hunde después de pagar, y el director los siembra cada vez más seguido con un cupo que crece por minuto; el de **codicia** sigue apostando vida; la **ruleta** abre un menú con 11 resultados (objetos, +stats, +armas, jackpot, curación, maldiciones…) y **cada giro duplica el precio** del siguiente para el resto de la partida; los **portales** aparecen emparejados al inicio y teletransportan con recarga; el **manantial** cura y da un power-up de 30 s.
- **Cartas**: tope de 5 armas y 5 tomos distintos por jugador (**los stacks y los niveles de arma no tienen tope**); cada subida de nivel ofrece **un solo lado**: armas o tomos, nunca mezclado; cartas que suben dos stats de un arma; las armas **evolucionan al nivel 10 y ascienden cada 10 niveles** a partir de ahí; «Corazón recio» cura solo lo ganado; subir de nivel ya no aspira las gemas. Tomos nuevos: Tomo de Fortuna (suerte), de Multitud (+proyectiles), de Persistencia (duración de efectos), de Sabiduría (XP), del Azar (stats aleatorios según rareza) y del Peligro (dificultad).
- **Mapa irregular**: cada run bloquea manchas de celdas con **rocas de verdad** —una retícula que cubre la celda entera, con colisión por cada blob visible— en vez de los muros invisibles de 10x7x10 m que había antes: ya no chocas contra nada y los enemigos dejaron de caminar a 7 m de altura sobre ellos. Todo lo abierto sigue siendo alcanzable a pie, y los cofres/altares iniciales varían. Los enemigos **trepan** muros y props.
- **HUD**: puntos, dificultad acumulada, **toast de botín** abajo al centro cada vez que algo entra a una bolsa, un **badge de FPS** opcional (Ajustes → «Mostrar FPS») arriba a la derecha, y dos tiras inferiores: **abajo a la izquierda** armas (nivel o ★rango) y tomos (stacks), **abajo a la derecha** los objetos (copias). Cada casilla busca `res://assets/icons/<biblioteca>/<id>.png` (`weapons`, `tomes`, `items`) y cae a `assets/icons/placeholder.png` con la sigla encima; una fila de catálogo con `icon` propio gana sobre ambos. Para poner arte real basta soltar los PNG con el id como nombre.
- **Dificultad**: rampa de spawns más agresiva (`interval_shrink_per_minute` 0.32, `extra_count_per_minute` 0.45), más shiny (8% → 21%), y un **escalado tardío abierto** desde el minuto 6 (+8% HP y +5% daño por minuto en spawns nuevos) para que el late game no se pueda ignorar quieto. En co-op los enemigos escalan por jugador extra (+50% HP, +30% ritmo de spawn, jefes +50% HP por jugador).

Los números viven como exports en `enemy_spawner.gd` y `world_director.gd` para ajustarlos sin tocar código.

## Fondo del mundo (iteración 34)

Las arenas ya no flotan en el vacío: cada mapa instancia un nodo **Backdrop** (`scripts/world/backdrop.gd`) que construye en código un disco de suelo gigante bajo el borde del mapa (tinte del bioma) y dos anillos de colinas-silueta low-poly fuera del perímetro (a ~190-250 m y ~310-410 m, derivadas del medio-extent de 120), que la niebla del `WorldEnvironment` ya existente funde con el horizonte. Los colores son exports por bioma en la escena de cada mapa; las colinas se re-generan aleatorias cada partida.

## Enganche y rejugabilidad (iteraciones 35-37)

- **Evoluciones y ascensos de armas** (`scripts/systems/evolution_catalog.gd`): cada carta invertida en un arma es un nivel de arma; cada 10 niveles hay un hito. El primero evoluciona el arma (cambia de nombre y multiplica sus stats, fila `mults`/`adds` aplicada genéricamente por `WeaponBase.evolve()`); los siguientes son **ascensos**, un escalón plano sin receta (`WeaponBase.ascend()`) que también reciben las armas sin evolución escrita, así ninguna deja de mejorar. Fanfarria, banner dorado y sparkle en ambos. Descubrimientos persistidos en contadores `evo_<arma>`.
- **Colección** (`scenes/ui/Collection.tscn`, botón en el selector): raiders, arsenal, evoluciones descubiertas (las no descubiertas muestran una pista vaga) y bestiario con kills por especie (`kills_<script>`, bump automático en `EnemyBase`), más un % de completitud global.
- **Armería** (`scenes/ui/RelicShop.tscn` + `relic_catalog.gd`): 6 reliquias de stats permanentes compradas con esquirlas en escalera de rangos/precios (persisten en `SaveData.relic_ranks`, se aplican en cada `PlayerStats.recompute()`). Amplía la regla del GDD "las esquirlas solo compran raiders": los montos son pequeños para que la maestría siga siendo la curva real.
- **Cacería diaria** (botón dorado del selector): reto diario con semilla derivada de la fecha — raider, mapa, layout del scatter, máscara de arena y tiradas de cartas deterministas para todos ese día; reintentos permitidos, se guarda el mejor puntaje por fecha (`daily_best_<fecha>`, fórmula en `GameConfig.daily_score`).
- **Sin reloj (iteración 38)**: la partida no termina al minuto 15. Sobrevivir 15 minutos es el hito que la califica como victoria (banner «15 minutos sobrevividos — extráete cuando quieras desde el menú de pausa», plantilla en `RunManager.survival_text`); desde el menú de pausa se puede **Extraerse** en cualquier momento, lo que cierra la incursión con fold de meta (victoria si se alcanzó el hito, derrota si no). Morir tras el hito también cuenta como victoria. La pantalla final titula MORISTE / INCURSIÓN COMPLETA / EXTRACCIÓN LOGRADA / INCURSIÓN ABANDONADA y ofrece **Reintentar**, **Cambiar raider** y **Salir**. `best_endless_minutes` guarda los minutos de la partida ganada más larga.

## Compilar (export)

Hay tres presets en `export_presets.cfg`: **macOS** (`builds/Bonkraiders.app`), **Windows Desktop** (`builds/Bonkraiders.exe`) y **Linux/X11** (`builds/Bonkraiders.x86_64`). Desde la raíz:

```sh
mkdir -p builds
godot --headless --export-release "macOS" builds/Bonkraiders.app
```

Para Windows/Linux se usan los mismos comandos con `"Windows Desktop"` / `"Linux/X11"`, pero hay que **descargar antes las export templates 4.7.2** de la plataforma destino (Editor > Manage Export Templates, o `Godot_v4.7.2-stable_export_templates.tpz`). La carpeta `builds/` está en `.gitignore`. Versión actual: `0.1.0` (`config/version` en `project.godot`, mostrada en el selector).

## Estructura del proyecto

```
project.godot            # autoloads, input map, escena principal
export_presets.cfg       # presets macOS / Windows / Linux
GDD.md                   # documento de diseño
CHANGELOG.md             # una línea por iteración (45 hasta ahora)
docs/ARQUITECTURA.md     # mapa de sistemas: dónde tocar para extender cada cosa
docs/GLOSARIO.md         # terminología canónica es-419 (obligatoria)
tools/verificar.sh       # import + soak de las 3 arenas + soak de etapa + cobertura
assets/
  audio/sfx/             # 20 wav sintetizados (regenerables, ver ARQUITECTURA)
  audio/ambient/         # camas de viento por bioma (forest_wind, desert_wind)
  materials/             # StandardMaterial3D .tres de los props low-poly
scenes/
  ui/                    # CharacterSelect (main), HUD, UpgradeCardUI, PauseMenu,
                         #   RunEndScreen, QuestLog, SettingsPanel,
                         #   Collection, RelicShop
  player/Player.tscn     # CharacterBody3D + SpringArm3D + Weapons + Health +
                         #   Stats + ItemBag + SealRig
  weapons/               # 14 armas + proyectiles (Projectile, Arrow,
                         #   BoomerangProjectile)
  enemies/               # Grunt/Skirmisher/Tank/Sunspitter/Duneburrower, jefes
                         #   (Rotking, Sarcognath, Fenwraith), minijefes
                         #   (Grubthing, CofferMimic)
  world/                 # HollowWoods.tscn, AshDunes.tscn y Gloomfen.tscn (arenas),
                         #   RunSystems.tscn (bloque común de partida),
                         #   props/, shrines/, chests/, secrets/
  systems/               # XpGem, HealthOrb
  fx/                    # DamagePopup, DeathBurst, TelegraphDisc, SlashArc...
  tests/ArenaProbe.tscn  # harness headless de soak (ver Verificación)
scripts/                 # espejo de scenes/: systems/ (autoloads y catálogos),
                         #   player/, weapons/, enemies/, world/, ui/, fx/,
                         #   tools/generate_sfx.gd (generador de audio)
```

Los archivos clave para tocar contenido son los **catálogos** en `scripts/systems/`: `upgrade_pool.gd` (armas y cartas), `character_catalog.gd`, `tome.gd`, `map_catalog.gd`, `quest_catalog.gd`, `evolution_catalog.gd` (recetas de evolución) y `relic_catalog.gd` (reliquias de la Armería). Ver `docs/ARQUITECTURA.md`, y `docs/GLOSARIO.md` para los nombres visibles.

## Verificación

**El comando por defecto tras cualquier cambio** es el script de verificación: hace el import, el **lint de catálogos**, el **harness de UI**, un soak de las **tres** arenas, un **cuarto soak de etapa** que cruza de mapa y un **quinto soak de co-op** con dos raiders, y falla si alguno ensucia el log, se cuelga, no ejercita nada, pierde progreso al cruzar o no reanima a nadie. Tarda entre ~16 y ~75 minutos según cuánto crezca la horda.

```sh
tools/verificar.sh            # 360 s de partida por arena (el modo estándar)
tools/verificar.sh 720        # corrida larga, para cambios de ritmo tardío
```

**Nunca con menos de 360 s**: por debajo, la puerta de cobertura de interactuables se salta en silencio y el script imprime OK sin haber exigido nada. La corrida completa (3 × 360 s + 1 × 720 s + 1 × 360 s de co-op + lint + harness de UI + import) tarda **entre ~16 y ~75 minutos**: el reloj lo manda el tamaño de la horda y no el número de frames — medido en dos corridas de la misma cabeza y las mismas semillas, 16 min y 75 min, con el soak de co-op moviéndose entre 78 s y 32 min. El script imprime los segundos de cada fase y el total.

Falla (exit 1) si el import, el lint, el harness de UI o un soak imprimen errores/warnings de Godot, si una arena no llega al final de su soak, si no alcanza la cobertura mínima (el raider tiene que pasar de nivel 3; en corridas de ≥240 s tiene que abrir un cofre, cargar un altar o usar un portal), si un soak **godmode** termina su partida sola, o si el soak de etapa no abre su portal, no cruza a las Dunas de Ceniza, deja algo vivo al cruzar, pierde progreso o no vuelve a producir un evento de cielo en el mapa nuevo. Los logs quedan en `$TMPDIR/bonkraiders-verify/` y cada arena imprime su resumen `nivel=… cofres=… altares=… portales=…`.

Las dos piezas nuevas de la iteración 57 y el quinto soak:

- **Lint de catálogos** (`scenes/tests/CatalogLint.tscn`): las referencias cruzadas que ningún soak puede comprobar, porque una rota no revienta — simplemente no hace nada. Nueve comprobaciones (`ids_unique`, `glyphs_unique`, `paths_exist`, `stat_ids`, `character_weapons`, `director_methods`, `weapon_properties`, `vendor_lucky_roulette_ids`, `marker_labels`), cada una con su línea `Catalog lint: check <nombre> ok rows=N`. `rows` es lo que se inspeccionó de verdad: **cero filas es un fallo**, porque una comprobación que recorre una lista vacía pasa por el motivo equivocado.
- **Harness de UI** (`scenes/tests/UiProbe.tscn`): siete de las nueve escenas de UI no las arrancaba nada. Trece pasos que pulsan los **controles reales** (Colección, Misiones, Armería, el rechazo de la fila de co-op, el desbloqueo de un raider con su carta de confirmación, todas las cartas, iniciar la incursión, abrir y cerrar la pausa, Ajustes con «Mostrar FPS», extraerse y reintentar), cada uno con su `UiProbe: step <nombre> ok`. Un control que falta, una precondición rechazada o una pausa que no se suelta es un `push_error`.
- **Soak de co-op**: dos raiders (`BONK_PLAYERS=2`), el slot 1 **mortal** a propósito (godmode cubre solo al slot 0) y derribado a los 45 s con `BONK_DOWN_NOW`, para que el ciclo derribo/reanimación —lo único que ningún soak en solitario puede alcanzar— se ejercite de verdad. Exige `ArenaProbe: players=2`, un cruce de etapa, barridos limpios y al menos un `Player revived:`.

**Guardado por corrida**: cada soak y cada harness recibe su propio `BONK_SAVE_PATH`, borrado con sus hermanos `.bak` y `.tmp` antes de arrancar. Antes todos compartían `user://soak_save.json`: los soaks godmode no doblan meta (nunca terminan la partida), pero sí acumulan los contadores que `SaveData.bump` acredita durante la corrida (bestiario `kills_<script>`, `used_weapon_<id>`), y cualquier corrida mortal o de UI le escribía encima esquirlas, misiones y desbloqueos. Borrar solo el `.json` no era un reset: `load_from_disk` cae al `.bak`.

Por debajo, los comandos sueltos siguen sirviendo:

```sh
# 1. Reimporta assets y compila todos los scripts; debe salir con exit 0
godot --headless --import

# 2. Boot de humo: la partida arranca sin errores (5 s simulados).
#    Es Run.tscn, no una arena suelta: una arena ya no arranca sola.
BONK_SAVE_PATH="$TMPDIR/smoke_save.json" \
  godot --headless --fixed-fps 60 --quit-after 300 res://scenes/world/Run.tscn

# 3. Soak con el harness (36000 frames = 10 min de juego). Los sistemas
#    imprimen una línea por evento ("Boss spawned: ...", "Chest opened: ...",
#    "Run ended: ...", "Meta saved: ..."): esa es la interfaz de verificación.
BONK_ARENA=res://scenes/world/Gloomfen.tscn BONK_GODMODE=1 \
  godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
```

`scenes/tests/ArenaProbe.tscn` arranca `Run.tscn` como hijo de un nodo siempre activo, imprime estado cada 2 s, elige sola la primera carta en cada subida de nivel y —desde la iteración 45— **camina e interactúa**: recorre los interactuables disponibles manejando las acciones de input reales, se queda quieto al llegar para que los altares de carga completen su canal, salta cuando se atasca y avisa por `push_warning` si una UI bloqueante deja la partida encallada. Un raider aparcado se salta en silencio todo sistema condicionado al movimiento, y un soak así reporta "sin errores" sobre código que nunca corrió. Nunca toca el guardado real: usa `BONK_SAVE_PATH` si está puesta y `user://soak_save.json` si no.

Desde la iteración 57 también sabe jugar **en co-op** (`BONK_PLAYERS`): el slot 0 lidera e interactúa, los demás **siguen** al líder y nunca interactúan por su cuenta (dos recorridos duplicarían las cuentas de interactuables con las que se calibró cada puerta), y una **regla de rescate** manda por encima de todo lo demás —el rush al portal incluido—: con un cuerpo derribado a menos de 6 m, el líder camina hasta él y **mantiene** interactuar hasta que se levanta. Sin godmode, el harness se entera del final de la partida por `RunManager.run_ended`, imprime `Probe: run ended victory=%s` y se va: una corrida mortal termina en la muerte por diseño, y la pantalla final no se juega sola en headless.

Variables de entorno del harness:

| Variable | Efecto |
|---|---|
| `BONK_ARENA=res://scenes/world/AshDunes.tscn` | **bioma de la etapa 1** (defecto: Bosque Hueco); el harness siempre arranca `Run.tscn` |
| `BONK_CHARACTER=<id>` | raider concreto del catálogo; un id desconocido ahora es un error, no un silencio |
| `BONK_PLAYERS=<1-4>` | tamaño de la party (iteración 57). `Coop.configure` corre **antes** de instanciar `Run.tscn`, que es lo que lee `RunSystems._spawn_party`; todos los slots van al teclado, porque un soak no tiene controles |
| `BONK_CHARACTER2=<id>` | raider del slot 1 (defecto: la fila del catálogo siguiente a la del slot 0, para que los dos difieran) |
| `BONK_DOWN_NOW=<seg>` | derriba al slot 1 a ese segundo de partida y cada 60 s después, para **forzar** el ciclo derribo/reanimación en vez de esperarlo |
| `BONK_GODMODE=1` | raider prácticamente inmortal, para llegar a los sistemas tardíos. **Solo el slot 0**: el slot 1 se queda mortal, que es lo que hace que `BONK_DOWN_NOW` pueda aterrizar |
| `BONK_WALK=0` | deja el raider quieto (defecto: camina) |
| `BONK_SEED=<int>` | recorrido determinista, para reproducir un soak |
| `BONK_PROBE_DEBUG=1` | narra el recorrido (waypoints, llegadas, pulsaciones) |
| `BONK_STAGE_FAST=1` | la etapa se supera a los 60 s y sin jefe; el harness espera 70 s y cruza el portal |
| `BONK_SAVE_PATH=<ruta>` | re-apunta el guardado. Lo honra `SaveData` en cualquier arranque headless **y** el propio harness, antes de que la partida arranque; `tools/verificar.sh` le da a cada soak el suyo |
| `BONK_GAME_SEED=<int>` | siembra el RNG del juego (cartas, spawns, scatter y relieve): hace reproducible un soak entero |
| `BONK_POWERUP_NOW=<id>` | concede ese power-up al jugador 1 a los 20 s y **se lo vuelve a dar en cada expiración**, para que un soak corto pase todo su reloj dentro del efecto |
| `BONK_STAR_NOW=1` | suelta una **estrella quieta** a los pies del raider a los 30 s (la que ronda el mapa es difícil de interceptar a propósito) |
| `BONK_POWERUP_BOOST=1` | multiplica ×50 la probabilidad de que una baja suelte un power-up, para que los drops salgan dentro de un soak |
| `BONK_POI_NOW=a,b,c` | siembra esos POIs junto al raider a los 20 s (`vendor_items`, `vendor_powerups`, `vendor_animals`, `pet_box`, `event_altar`, `lucky_block`). Las repeticiones se conservan: seis `lucky_block` siembran seis bloques |
| `BONK_LUCKY_REWARD=a,b` | cola de recompensas que pagan los bloques de la suerte siguientes en vez de tirar la tabla (la última entrada se repite). Seis bloques más los seis ids ejecutan todas las ramas de `LUCKY_REWARDS` en un solo soak |
| `BONK_WEATHER_NOW=<id>` | fuerza ese clima a los 30 s (`blood_moon`, `eclipse`, `full_moon`, `enemy_rain`, `radioactive_rain`, `golden_rain`, `enemy_tsunami`, `earthquake`, `meteor_shower`) |
| `BONK_WEAPON=<id>` | el raider arranca con esa arma en vez de la de su personaje |
| `BONK_ITEM_NOW=a,b:2` | concede esos objetos al jugador 1 a los 10 s y hace que derrape cada ~3 s |
| `BONK_ZENKAI_TEST=1` | escena de bajón y recuperación a los 60 s, para armar Zenkai |
| `BONK_POINTS=<n>` | le da esos puntos de partida al jugador 1, para que un soak de vendedor pueda comprar |
| `BONK_PERF=1` | overlay de rendimiento del HUD (FPS, conteos, pools) |

Para lógica aislada sigue sirviendo un harness desechable `extends SceneTree` con `godot --headless --path . -s <script>` (igual que `scripts/tools/generate_sfx.gd`). Ojo: en un script `-s` **no hay autoloads**, así que no vale para nada que toque `RunState`, `SaveData` o `Coop`.

## Guardado

Un único JSON en `user://save.json` (esquirlas, raiders desbloqueados, contadores de misiones, grados, rangos de reliquia, ajustes). En macOS:

```
~/Library/Application Support/Godot/app_userdata/Bonkraiders/save.json
```

(Windows: `%APPDATA%\Godot\app_userdata\Bonkraiders\`; Linux: `~/.local/share/godot/app_userdata/Bonkraiders/`.)

**Resetear el progreso** = borrar ese archivo con el juego cerrado; se regenera limpio al arrancar (Rook y Vex desbloqueados, 0 esquirlas). Un archivo corrupto no crashea: la escritura es atómica (`.tmp` + rename) y deja un `.bak`, así que `SaveData.load_from_disk()` recupera el respaldo y, si tampoco sirve, cae a valores por defecto. Los harness de prueba pueden apuntar `SaveData.save_path` a un archivo temporal antes de `load_from_disk()`.
