class_name FallingLeaves
extends GPUParticles3D
## Hojas que caen del bosque alrededor de la cámara: unas pocas, lentas, para
## que el aire no esté quieto. No tienen colisión ni afectan la partida.
##
## Va como hija de la arena. Sigue a la cámara activa (las hojas ya
## soltadas se quedan donde están) y deja de soltar hojas cuando empieza una
## transformación de etapa (el infierno de Mythos): ahí ya no hay bosque.

## Grupo en el que entra la transformación de la etapa mientras dura.
const TRANSFORMATION_GROUP: StringName = &"stage_transformation"
## Cada cuántos segundos mira si empezó una transformación.
const CHECK_SECONDS: float = 0.5

@export_group("Hojas")
## Hojas en el aire a la vez.
@export var leaf_count: int = 220
## Segundos que vive cada hoja.
@export var leaf_lifetime: float = 9.0
## Medio lado del cuadrado alrededor de la cámara donde nacen, en metros.
@export var area_half_extent: float = 32.0
## Metros sobre la cámara a los que nacen.
@export var spawn_height: float = 13.0
## Tamaño mínimo de una hoja, en metros.
@export var leaf_size_min: float = 0.16
## Tamaño máximo de una hoja, en metros.
@export var leaf_size_max: float = 0.34
## Velocidad de caída, en metros por segundo.
@export var fall_speed: float = 1.9
## Viento: hacia dónde y cuánto las arrastra, en metros por segundo.
@export var wind: Vector3 = Vector3(0.9, 0.0, 0.5)
## Colores de las hojas, del más común al más raro.
@export var leaf_colors: Array[Color] = [Color(0.5, 0.74, 0.38), Color(0.78, 0.8, 0.36),
		Color(0.93, 0.68, 0.26), Color(0.88, 0.42, 0.2)]

var _clock: float = 0.0


func _ready() -> void:
	amount = maxi(leaf_count, 1)
	lifetime = leaf_lifetime
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Las hojas se sueltan lejos del nodo: sin esta caja el motor las recorta.
	var reach := area_half_extent + 30.0
	visibility_aabb = AABB(Vector3(-reach, -spawn_height - 30.0, -reach),
			Vector3(reach * 2.0, spawn_height + 40.0, reach * 2.0))
	process_material = _flight()
	draw_pass_1 = _leaf()
	emitting = true


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * spawn_height
	_clock += delta
	if _clock >= CHECK_SECONDS:
		_clock = 0.0
		emitting = get_tree().get_first_node_in_group(TRANSFORMATION_GROUP) == null


## Cómo vuela cada hoja: nace en una caja ancha y chata, cae despacio con
## el viento y gira sobre sí misma.
func _flight() -> ParticleProcessMaterial:
	var flight := ParticleProcessMaterial.new()
	flight.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	flight.emission_box_extents = Vector3(area_half_extent, 2.0, area_half_extent)
	flight.direction = Vector3(wind.x, -fall_speed, wind.z).normalized()
	flight.spread = 18.0
	var speed := Vector3(wind.x, -fall_speed, wind.z).length()
	flight.initial_velocity_min = speed * 0.7
	flight.initial_velocity_max = speed * 1.3
	flight.gravity = Vector3(0.0, -0.25, 0.0)
	flight.angle_min = 0.0
	flight.angle_max = 360.0
	flight.angular_velocity_min = -90.0
	flight.angular_velocity_max = 90.0
	flight.scale_min = leaf_size_min
	flight.scale_max = leaf_size_max
	if not leaf_colors.is_empty():
		# Los primeros colores ocupan más de la rampa: salen más seguido.
		var weights := 0.0
		for index in leaf_colors.size():
			weights += 1.0 / float(index + 1)
		var offsets := PackedFloat32Array()
		var at := 0.0
		for index in leaf_colors.size():
			offsets.append(at)
			at += (1.0 / float(index + 1)) / weights
		var colors := Gradient.new()
		colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		colors.offsets = offsets
		colors.colors = PackedColorArray(leaf_colors)
		var ramp := GradientTexture1D.new()
		ramp.gradient = colors
		flight.color_initial_ramp = ramp
	return flight


## La hoja: un rombo que siempre mira a la cámara y gira con su partícula.
func _leaf() -> Mesh:
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.vertex_color_use_as_albedo = true
	paint.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	paint.billboard_keep_scale = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.62, 1.0, 0.01)
	leaf.material = paint
	return leaf
