class_name ReliefSettings
extends Resource
## Relieve por zonas de una arena: zonas elevadas con acantilados, un
## barranco, las rampas que entran a cada una y el puente que cruza el
## barranco. Hay un .tres por arena en assets/world/ (relief_<mapa>.tres),
## asignado en el export `relief` de su nodo Terrain: para cambiar el relieve
## de un mapa, edita su .tres. Una arena sin este recurso tiene el suelo
## suave de siempre.
##
## Los valores de este script son los del Bosque Hueco. Lo que arma el
## trazado con ellos es ReliefLayout (relief_layout.gd).
##
## Tres límites que el resto del juego da por ciertos; si los pasas, la
## horda deja de alcanzar al raider o el mapa deja de cerrar:
## - Ningún corte mide más de 8 m (los enemigos trepan 10 m de una vez).
## - zone_top_height + zone_top_swell_max es la cima del mapa y
##   ravine_depth_max + ravine_valley su fondo: el fondo no puede bajar de
##   -7 m (el rescate del vacío del raider está en -10).
## - Las rampas van bajo 30 grados: sobre 45 nadie camina.

@export_group("Zonas elevadas")
## Zonas elevadas por etapa, como mínimo.
@export var raised_min: int = 2
## Zonas elevadas por etapa, como máximo.
@export var raised_max: int = 3
## Radio medio mínimo de una zona elevada, en metros.
@export var zone_radius_min: float = 19.0
## Radio medio máximo de una zona elevada, en metros.
@export var zone_radius_max: float = 26.0
## Cuánto puede alargarse una zona: razón máxima entre su eje largo y el corto.
@export var zone_stretch_max: float = 1.4
## Fuerza de los lóbulos del contorno (0 = óvalo liso; 0.1 = contorno ondulado).
@export_range(0.0, 0.14) var zone_lobes: float = 0.09
## Altura mínima del acantilado de una zona elevada, en metros.
@export var zone_height_min: float = 4.6
## Altura máxima del acantilado de una zona elevada, en metros.
@export var zone_height_max: float = 5.6
## Altura del acantilado de LA zona alta (una por etapa), en metros.
@export var zone_top_height: float = 6.4
## Altura mínima de la loma ancha sobre la que se apoya cada zona, en metros.
@export var zone_swell_min: float = 0.8
## Altura máxima de la loma ancha sobre la que se apoya cada zona, en metros.
@export var zone_swell_max: float = 1.8
## Altura mínima de la loma de la zona alta, en metros.
@export var zone_top_swell_min: float = 2.2
## Altura máxima de la loma de la zona alta, en metros.
@export var zone_top_swell_max: float = 2.4
## Metros que tarda la loma de una zona en volver al nivel del bosque: más
## grande = pendiente más larga y más suave.
@export var swell_reach: float = 42.0

@export_group("Rampas")
## Rampas de entrada a cada zona elevada, como mínimo.
@export var ways_min: int = 2
## Rampas de entrada a cada zona elevada, como máximo.
@export var ways_max: int = 4
## Metros de contorno por rampa: una zona recibe una rampa por cada tanto.
@export var way_every: float = 62.0
## Ancho de una rampa, en metros, hombros de roca incluidos.
@export var ramp_width: float = 12.0
## Pendiente de las rampas, en grados.
@export_range(10.0, 30.0) var ramp_slope_degrees: float = 22.0

@export_group("Barranco")
## Largo mínimo del barranco, en metros (rampas de los extremos incluidas).
@export var ravine_length_min: float = 86.0
## Largo máximo del barranco, en metros.
@export var ravine_length_max: float = 106.0
## Ancho mínimo del barranco de borde a borde, en metros.
@export var ravine_width_min: float = 15.0
## Ancho máximo del barranco de borde a borde, en metros.
@export var ravine_width_max: float = 17.0
## Profundidad mínima del barranco bajo su borde, en metros.
@export var ravine_depth_min: float = 4.9
## Profundidad máxima del barranco bajo su borde, en metros.
@export var ravine_depth_max: float = 5.2
## Metros que baja la vaguada ancha por la que corre el barranco.
@export var ravine_valley: float = 0.8
## Cuánto se curva el barranco: desvío máximo de su punto medio, en metros.
@export var ravine_bend_max: float = 10.0
## Pendiente de las rampas de los dos extremos del barranco, en grados.
@export_range(10.0, 30.0) var ravine_ramp_slope_degrees: float = 20.0
## Fracción de la ondulación del suelo que conserva el fondo del barranco (0-1).
@export_range(0.0, 1.0) var ravine_floor_detail: float = 0.4

@export_group("Puente")
## Escena del puente que cruza el barranco (scenes/world/props/Bridge.tscn).
## Vacío, el barranco se queda sin puente.
@export var bridge_scene: PackedScene
## Ancho del tablero del puente, en metros.
@export var bridge_width: float = 5.0
## Radio del claro plano en cada cabecera del puente, en metros.
@export var bridgehead_radius: float = 6.0

@export_group("Lomas sueltas")
## Lomas anchas del nivel del bosque, además de las que sostienen cada zona.
@export var hill_count: int = 2
## Altura mínima de una loma suelta, en metros.
@export var hill_height_min: float = 1.2
## Altura máxima de una loma suelta, en metros.
@export var hill_height_max: float = 1.8
## Radio mínimo de una loma suelta, en metros.
@export var hill_radius_min: float = 28.0
## Radio máximo de una loma suelta, en metros.
@export var hill_radius_max: float = 36.0

@export_group("Reparto en el mapa")
## Metros libres de cortes alrededor del punto de aparición.
@export var spawn_clearance: float = 30.0
## Distancia mínima del spawn al borde de la zona elevada más cercana, en
## metros: el relieve tiene que verse desde donde aparece el equipo.
@export var view_distance_min: float = 30.0
## Distancia máxima del spawn al borde de la zona elevada más cercana, en metros.
@export var view_distance_max: float = 42.0
## Metros que cualquier zona, rampa o barranco guarda con el borde de la arena.
@export var edge_margin: float = 24.0
## Metros de suelo libre entre dos zonas, o entre una zona y el barranco.
@export var feature_gap: float = 20.0
