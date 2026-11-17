class_name ReliefSettings
extends Resource
## Relieve por zonas de una arena: una montaña escalonada (un macizo ancho
## donde aparece el equipo, un segundo nivel y una cumbre), un cañón que pasa
## a su pie, cerros sueltos, las rampas que entran a cada zona y los puentes
## que cruzan el cañón. Hay un .tres por arena en assets/world/
## (relief_<mapa>.tres), asignado en el export `relief` de su nodo Terrain:
## para cambiar el relieve de un mapa, edita su .tres. Una arena sin este
## recurso tiene el suelo suave de siempre.
##
## Los valores de este script son los del Bosque Hueco. Lo que arma el
## trazado con ellos es ReliefPlanner (relief_planner.gd).
##
## Tres límites que el resto del juego da por ciertos; si los pasas, la
## horda deja de alcanzar al raider o el mapa deja de cerrar:
## - Ningún corte mide más de 8 m (los enemigos trepan 10 m de una vez). La
##   montaña es alta porque APILA cortes, no porque alguno sea más alto.
## - El fondo del cañón (ravine_depth_max + ravine_valley + lo que deja
##   ravine_floor_detail) no puede bajar de -7 m: el rescate del vacío del
##   raider está en -10.
## - Las rampas van bajo 30 grados: sobre 45 nadie camina.

@export_group("Macizo")
## Radio medio mínimo del macizo (el nivel ancho donde aparece el equipo), en metros.
@export var massif_radius_min: float = 52.0
## Radio medio máximo del macizo, en metros.
@export var massif_radius_max: float = 56.0
## Cuánto se alarga el macizo hacia la montaña, como mínimo: razón entre su
## eje largo y el corto. Alargado, le queda lugar al segundo nivel en un
## extremo y al punto de aparición en el otro.
@export var massif_stretch_min: float = 1.15
## Razón máxima entre el eje largo del macizo y el corto.
@export var massif_stretch_max: float = 1.3
## Fuerza de los lóbulos de su contorno (0 = óvalo liso).
@export_range(0.0, 0.1) var massif_lobes: float = 0.055
## Altura mínima del acantilado del macizo sobre el llano, en metros.
@export var massif_height_min: float = 5.8
## Altura máxima del acantilado del macizo sobre el llano, en metros.
@export var massif_height_max: float = 6.4
## Distancia mínima del punto de aparición al centro del macizo, en metros:
## el equipo aparece corrido hacia un costado, con la montaña por delante.
@export var massif_offset_min: float = 26.0
## Distancia máxima del punto de aparición al centro del macizo, en metros.
@export var massif_offset_max: float = 30.0
## Altura mínima de la loma ancha sobre la que se apoya toda la montaña, en metros.
@export var massif_swell_min: float = 2.0
## Altura máxima de la loma ancha sobre la que se apoya toda la montaña, en metros.
@export var massif_swell_max: float = 3.0
## Rampas del macizo al llano, como mínimo.
@export var massif_ways_min: int = 3
## Rampas del macizo al llano, como máximo.
@export var massif_ways_max: int = 6

@export_group("Niveles altos")
## Radio medio mínimo del segundo nivel de la montaña, en metros.
@export var tier_radius_min: float = 24.0
## Radio medio máximo del segundo nivel de la montaña, en metros.
@export var tier_radius_max: float = 27.0
## Razón máxima entre el eje largo y el corto del segundo nivel.
@export var tier_stretch_max: float = 1.2
## Fuerza de los lóbulos del contorno del segundo nivel y de la cumbre.
@export_range(0.0, 0.1) var tier_lobes: float = 0.06
## Altura mínima del acantilado del segundo nivel sobre el macizo, en metros.
@export var tier_height_min: float = 5.6
## Altura máxima del acantilado del segundo nivel sobre el macizo, en metros.
@export var tier_height_max: float = 6.2
## Distancia mínima del punto de aparición al centro del segundo nivel, en metros.
@export var tier_distance_min: float = 48.0
## Distancia máxima del punto de aparición al centro del segundo nivel, en metros.
@export var tier_distance_max: float = 58.0
## Rampas del segundo nivel al macizo, como mínimo.
@export var tier_ways_min: int = 2
## Rampas del segundo nivel al macizo, como máximo.
@export var tier_ways_max: int = 3
## Radio medio mínimo de la cumbre, en metros.
@export var summit_radius_min: float = 8.5
## Radio medio máximo de la cumbre, en metros.
@export var summit_radius_max: float = 10.0
## Altura mínima del acantilado de la cumbre sobre el segundo nivel, en metros.
@export var summit_height_min: float = 5.2
## Altura máxima del acantilado de la cumbre sobre el segundo nivel, en metros.
@export var summit_height_max: float = 5.8
## Metros que la cumbre se corre del centro del segundo nivel, alejándose
## del punto de aparición: del lado de acá queda lugar para su rampa.
@export var summit_shift: float = 6.0
## Rampas de la cumbre, como mínimo (con una sola, es un último reducto).
@export var summit_ways_min: int = 1
## Rampas de la cumbre, como máximo.
@export var summit_ways_max: int = 2
## Metros de suelo que quedan entre el corte de un nivel y el del nivel que
## lo sostiene: la cornisa por la que camina la horda entre dos trepadas.
@export var tier_margin: float = 7.0
## Pendiente de las rampas de los niveles altos, en grados: más empinadas
## que las del llano para que quepan sobre el nivel de abajo.
@export_range(10.0, 30.0) var tier_ramp_slope_degrees: float = 27.0

@export_group("Cerros")
## Cerros sueltos del llano (mesetas chicas con su acantilado), como mínimo.
@export var butte_count_min: int = 2
## Cerros sueltos del llano, como máximo.
@export var butte_count_max: int = 3
## Radio medio mínimo de un cerro, en metros.
@export var butte_radius_min: float = 11.0
## Radio medio máximo de un cerro, en metros.
@export var butte_radius_max: float = 15.0
## Razón máxima entre el eje largo y el corto de un cerro.
@export var butte_stretch_max: float = 1.35
## Fuerza de los lóbulos del contorno de un cerro.
@export_range(0.0, 0.14) var butte_lobes: float = 0.09
## Altura mínima del acantilado de un cerro, en metros.
@export var butte_height_min: float = 4.4
## Altura máxima del acantilado de un cerro, en metros.
@export var butte_height_max: float = 5.6
## Altura mínima de la loma ancha bajo cada cerro, en metros.
@export var butte_swell_min: float = 0.8
## Altura máxima de la loma ancha bajo cada cerro, en metros.
@export var butte_swell_max: float = 1.8
## Rampas de cada cerro, como mínimo.
@export var butte_ways_min: int = 1
## Rampas de cada cerro, como máximo.
@export var butte_ways_max: int = 2

@export_group("Rampas")
## Metros de contorno por rampa: una zona recibe una rampa por cada tanto
## (entre el mínimo y el máximo de su grupo).
@export var way_every: float = 58.0
## Ancho de una rampa, en metros, hombros de roca incluidos.
@export var ramp_width: float = 12.0
## Pendiente de las rampas que bajan al llano, en grados.
@export_range(10.0, 30.0) var ramp_slope_degrees: float = 22.0
## Metros que tarda la loma de una zona en volver al nivel del llano: más
## grande = pendiente más larga y más suave.
@export var swell_reach: float = 42.0

@export_group("Cañón")
## Largo mínimo del cañón, en metros (rampas de los extremos incluidas).
@export var ravine_length_min: float = 140.0
## Largo máximo del cañón, en metros.
@export var ravine_length_max: float = 170.0
## Ancho mínimo del cañón de borde a borde, en metros.
@export var ravine_width_min: float = 24.0
## Ancho máximo del cañón de borde a borde, en metros.
@export var ravine_width_max: float = 27.0
## Profundidad mínima del cañón bajo su borde, en metros.
@export var ravine_depth_min: float = 5.8
## Profundidad máxima del cañón bajo su borde, en metros.
@export var ravine_depth_max: float = 6.0
## Metros que baja la vaguada ancha por la que corre el cañón.
@export var ravine_valley: float = 0.4
## Metros de llano entre el pie del macizo y el borde del cañón, donde más se acercan.
@export var ravine_gap: float = 14.0
## Cuánto abraza el cañón a la montaña: metros que sus extremos se acercan
## a ella respecto de su punto medio, como mínimo.
@export var ravine_bend_min: float = 4.0
## Metros que los extremos del cañón se acercan a la montaña, como máximo.
@export var ravine_bend_max: float = 12.0
## Pendiente de las rampas de los dos extremos del cañón, en grados.
@export_range(10.0, 30.0) var ravine_ramp_slope_degrees: float = 20.0
## Fracción de la ondulación del suelo que conserva el fondo del cañón (0-1).
@export_range(0.0, 1.0) var ravine_floor_detail: float = 0.15

@export_group("Puentes")
## Escena del puente que cruza el cañón (scenes/world/props/Bridge.tscn).
## Vacío, el cañón se queda sin puentes.
@export var bridge_scene: PackedScene
## Puentes sobre el cañón, como mínimo. Entre dos puentes el cañón lleva un
## collado (el fondo sube hasta el borde).
@export var bridge_count_min: int = 1
## Puentes sobre el cañón, como máximo. Si el cañón sale corto para tantos
## tramos, lleva menos.
@export var bridge_count_max: int = 1
## Ancho de la obra de cada puente en sus estribos, en metros (el tablero
## mide algo más de un metro menos: ver Bridge.tscn).
@export var bridge_width: float = 9.0
## Metros a lo largo del cañón que ocupa cada escalera del puente desde el
## costado de su estribo. De aquí sale su pendiente: con el cañón a 6 m,
## bajo 8.5 m quedaría sobre 45 grados y no se caminaría.
@export var bridge_stair_reach: float = 12.5
## Radio del claro plano en cada cabecera de puente, en metros: cubre el
## tablero y los descansos de las dos escaleras.
@export var bridgehead_radius: float = 10.5

@export_group("Estructuras")
## Hito de la cumbre (scenes/world/props/HollowTree.tscn). Vacío, la cumbre queda pelada.
@export var landmark_scene: PackedScene
## Escena de las piedras antiguas (scenes/world/props/StandingStones.tscn):
## los portales de las rampas de los niveles altos, los menhires al pie de
## las rampas del llano, el círculo de piedras y las ruinas. Vacío, no hay piedras.
@export var stones_scene: PackedScene
## Ruinas en claros del llano, como máximo (las que quepan).
@export var ruin_count: int = 3
## Monolitos sueltos (piedras paradas de varios metros), como máximo.
@export var monolith_count: int = 9
## Altura mínima de un monolito, en metros.
@export var monolith_height_min: float = 6.5
## Altura máxima de un monolito, en metros (bajo 10: la horda trepa 10 de una vez).
@export var monolith_height_max: float = 9.5
## Material del agua que corre por el fondo del cañón. Vacío, el cañón queda seco.
@export var water_material: Material

@export_group("Lomas sueltas")
## Lomas anchas del llano, además de las que sostienen la montaña y los cerros.
@export var hill_count: int = 5
## Altura mínima de una loma suelta, en metros.
@export var hill_height_min: float = 1.8
## Altura máxima de una loma suelta, en metros.
@export var hill_height_max: float = 3.2
## Radio mínimo de una loma suelta, en metros.
@export var hill_radius_min: float = 24.0
## Radio máximo de una loma suelta, en metros.
@export var hill_radius_max: float = 38.0

@export_group("Reparto en el mapa")
## Metros alrededor del punto de aparición sin cortes ni pies de rampa: el
## claro plano del spawn más su franja de mezcla.
@export var spawn_clearance: float = 21.0
## Metros que cualquier zona, rampa o cañón guarda con el borde de la arena.
@export var edge_margin: float = 24.0
## Metros de suelo libre entre dos zonas sueltas, o entre un cerro y el cañón.
@export var feature_gap: float = 12.0
