class_name EnemyLookPalette
extends Resource
## Aspecto compartido por todos los enemigos: el brillo shiny, las capas de
## veneno y de poseído, la caída del cadáver y el color de reserva del
## estallido de muerte. Los valores en uso están en
## assets/enemies/enemy_look.tres (ábrelo en el Inspector); EnemyBase.LOOK
## lo carga. Los colores de las variantes del cielo están en
## EnemyBase.VARIANTS. Las capas son materiales sin sombreado: solo cuentan
## su color y su opacidad, no tienen brillo propio.

@export_group("Shiny")
## Color de la capa shiny en su primer frame; desde el siguiente cicla el matiz.
@export var shiny_start_color: Color = Color(1.0, 0.62, 0.12)
## Vueltas de la rueda de matiz por segundo (lento se lee como reflejo, no estrobo).
@export var shiny_hue_speed: float = 0.28
## Saturación del matiz, 0-1.
@export_range(0.0, 1.0) var shiny_saturation: float = 0.85
## Opacidad de la capa shiny, 0-1.
@export_range(0.0, 1.0) var shiny_alpha: float = 0.3

@export_group("Veneno")
## Color de la capa de veneno; el alfa es su opacidad.
@export var poison_tint: Color = Color(0.35, 0.9, 0.3, 0.35)

@export_group("Poseído")
## Color de los siervos poseídos: su capa, el estallido al expirar y el rayo del Báculo de nigromante.
@export var possessed_color: Color = Color(0.65, 0.35, 0.95)
## Opacidad de la capa de poseído, 0-1.
@export_range(0.0, 1.0) var possessed_alpha: float = 0.35
## Esquirlas del estallido cuando un siervo expira.
@export var possessed_expire_burst: int = 12

@export_group("Muerte")
## Segundos que dura la caída del cadáver.
@export var death_time: float = 0.3
## Inclinación final del cadáver hacia atrás, en radianes (-TAU/4 = acostado).
@export var death_tilt: float = -TAU * 0.25
## Escala final del cadáver, como fracción de su tamaño.
@export var death_end_scale: float = 0.05
## Color del estallido de muerte cuando el cuerpo no tiene un material con albedo.
@export var death_burst_fallback: Color = Color(0.75, 0.75, 0.78)
