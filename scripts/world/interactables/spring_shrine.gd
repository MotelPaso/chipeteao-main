class_name SpringShrine
extends Interactable
## Manantial: un estanque de agua clara, gratis. Al activarlo abre una zona
## de curación a su alrededor durante heal_zone_seconds: cada raider en pie
## dentro recupera una parte de su vida máxima por segundo. Después se hunde
## y desaparece. StageFixtures reparte varios por el mapa al empezar la
## etapa; RunRoot los libera con el resto de la etapa.

@export_group("Zona de curación")
## Segundos que dura la zona de curación después de activar el manantial.
@export var heal_zone_seconds: float = 5.0
## Radio de la zona de curación, en metros.
@export var heal_zone_radius: float = 5.0
## Vida que cura por segundo a cada raider dentro, como fracción de su vida máxima (0.1 = 10% por segundo).
@export var heal_per_second_fraction: float = 0.1
## Color del disco de la zona en el suelo (el alfa es la opacidad).
@export var zone_color: Color = Color(0.4, 0.85, 1.0, 0.3)
## Cuánto late la opacidad del disco (0 = fija).
@export var zone_pulse: float = 0.12
## Velocidad de ese latido, en radianes por segundo.
@export var zone_pulse_speed: float = 6.0
@export_group("Agua")
## Velocidad de las ondas del agua en X, en radianes por segundo (desafinada con la de Z para que no lata como un metrónomo).
@export var ripple_x_speed: float = 1.7
## Velocidad de las ondas del agua en Z, en radianes por segundo.
@export var ripple_z_speed: float = 1.3
## Cuánto se estira el agua en las ondas, como fracción de su tamaño.
@export var ripple_amount: float = 0.03
@export_group("Textos")
## Aviso para activarlo.
@export var activate_prompt: String = "[E] Activar — zona de curación (gratis)"
## Anuncio al activarlo.
@export var used_announce: String = "El manantial cura a quien esté cerca"

var _time: float = 0.0
var _water: MeshInstance3D = null
## Segundos que le quedan a la zona; negativo = todavía no se activó.
var _zone_left: float = -1.0
var _zone: MeshInstance3D = null
var _zone_material: StandardMaterial3D = null


func _ready() -> void:
	super()
	add_to_group(&"springs")
	_water = get_node_or_null("Visual/Water") as MeshInstance3D
	set_prompt(activate_prompt)


func _physics_process(delta: float) -> void:
	_time += delta
	if _water != null:
		_water.scale = Vector3(
				1.0 + sin(_time * ripple_x_speed) * ripple_amount, 1.0,
				1.0 + cos(_time * ripple_z_speed) * ripple_amount)
	if _zone_left < 0.0:
		return
	_zone_left -= delta
	_heal_inside(delta)
	if _zone_material != null:
		_zone_material.albedo_color.a = zone_color.a \
				+ sin(_time * zone_pulse_speed) * zone_pulse
	if _zone_left <= 0.0:
		_zone_left = -1.0
		_emit_completed()
		sink_away()


func _interact(_player: Node) -> void:
	_emit_started()
	consume()
	_zone_left = heal_zone_seconds
	_spawn_zone()
	Sfx.play(&"heal")
	get_tree().call_group("hud", "announce", used_announce)
	print("Spring used: heal zone %.1fs" % heal_zone_seconds)


## Cura a cada raider en pie dentro del radio (distancia en el plano).
func _heal_inside(delta: float) -> void:
	var radius_sq := heal_zone_radius * heal_zone_radius
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		var offset := body.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() > radius_sq:
			continue
		var health := Health.find_in(body)
		if health != null and not health.is_dead:
			health.heal(health.max_hp * heal_per_second_fraction * delta)


## El disco translúcido que marca la zona en el suelo.
func _spawn_zone() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = heal_zone_radius
	mesh.bottom_radius = heal_zone_radius
	mesh.height = 0.06
	_zone_material = StandardMaterial3D.new()
	_zone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_material.albedo_color = zone_color
	mesh.material = _zone_material
	_zone = MeshInstance3D.new()
	_zone.mesh = mesh
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position = Vector3.UP * 0.05
	add_child(_zone)
