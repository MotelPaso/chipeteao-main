class_name RockFormationStyle
extends Resource
## Aspecto de las formaciones de roca de un bioma. Hay un .tres por bioma en
## assets/world/ (rock_style_<mapa>.tres), asignado en el export
## formation_style del scatter de cada arena: para cambiar la roca de un
## mapa, edita su .tres. Los valores de este script son los del bosque y
## solo se usan donde un .tres no pone otro (o si el scatter no tiene estilo).
##
## Ojo con EL SELLO (rock_formation.gd): bajar margin_min, cliff_height o
## cliff_run, o subir crag_height o lift_variation, puede dejar bordes de
## celda con la roca bajo RockFormation.SEAL_MIN_HEIGHT. La construcción lo
## avisa con un WARNING y tools/verificar.sh falla.

@export_group("Color")
## Color de las caras de roca (sRGB).
@export var rock_color: Color = Color(0.31, 0.32, 0.35)
## Tinte de las cimas casi planas (sRGB).
@export var cap_color: Color = Color(0.25, 0.39, 0.2)
## Cuánto tinte de cima toma una cima plana (0 = roca desnuda en todas partes).
@export_range(0.0, 1.0) var cap_strength: float = 0.65
## Variación de brillo +- de las bandas horizontales de estratos (0 = sin bandas).
@export var strata_strength: float = 0.05
## Material de las caras. Vacío = assets/materials/rock_formation.tres, que
## pinta con los colores de vértice de arriba.
@export var surface_material: Material

@export_group("Forma")
## Tamaño de faceta deseado, en metros; se redondea para que divida el lado
## de celda de la máscara (mask_cell_size del scatter).
@export var mesh_step: float = 2.0
## Distancia mínima en metros que la huella llega más allá de las celdas bloqueadas.
@export var margin_min: float = 1.0
## Distancia máxima en metros que la huella llega más allá de las celdas
## bloqueadas. El scatter deja mask_formation_gap celdas entre formaciones por esto.
@export var margin_max: float = 2.0
## Altura del acantilado en metros, alcanzada a cliff_run metros hacia dentro
## del borde de la huella.
@export var cliff_height: float = 2.6
## Metros hacia dentro del borde en los que el acantilado llega a cliff_height.
@export var cliff_run: float = 2.0
## Altura extra hacia la cresta, en metros: crece con la distancia al contorno.
@export var peak_height: float = 4.0
## Metros de profundidad en que la cresta gana ~63% de peak_height.
@export var peak_run: float = 7.0
## Altura máxima de las cumbres de ruido sobre la cresta, en metros.
@export var spire_height: float = 2.4
## Techo sobre el suelo, en metros. Debe quedar bajo lo que un enemigo trepa
## de una vez (EnemyBase.max_climb_height, 10 m).
@export var max_height: float = 8.0
## Fracción +- en que todo el perfil se hincha o se hunde a lo largo de la formación.
@export var lift_variation: float = 0.35
## Amplitud en metros del ruido a escala de faceta que vuelve rugosa la superficie.
@export var crag_height: float = 0.6
## Altura de cada escalón, en metros (ver terrace_strength).
@export var terrace_step: float = 1.6
## Cuánto se ajustan las alturas a escalones (0 = riscos, 1 = mesetas escalonadas).
@export_range(0.0, 1.0) var terrace_strength: float = 0.0
