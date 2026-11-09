class_name EnemyOverlays
extends RefCounted
## Las capas de material_overlay de un enemigo, por prioridad: poseído >
## shiny > variante del cielo > veneno. Cada efecto escribe SOLO su capa y
## llama a refresh(), así uno temporal nunca borra uno permanente (un
## berserker shiny se lee como ambos, y al pasarse el veneno vuelve la
## variante en vez de la piel desnuda). Juice.flash pide current() por
## EnemyBase.current_overlay() al terminar cada destello de daño. Los colores
## y tiempos salen de EnemyBase.LOOK.

## Fases iniciales distintas del brillo shiny, repartidas por instance id:
## una horda que late al unísono se lee como un solo objeto parpadeando.
const SHINY_PHASE_BUCKETS: int = 997

## Mallas del rig visual, resueltas una vez en _ready del cuerpo.
var _meshes: Array[MeshInstance3D] = []
## La posesión manda sobre todo: de qué bando es un cuerpo es lo primero que
## hay que leer, y un siervo nunca es shiny.
var _possessed: Material = null
## StandardMaterial3D y no Material: el brillo shiny reescribe su albedo cada
## frame.
var _elite: StandardMaterial3D = null
var _variant: Material = null
var _status: Material = null
## Material de veneno: se crea la primera vez y se reusa.
var _poison: StandardMaterial3D = null
## Dónde está el cuerpo en el ciclo de matiz shiny (0-1).
var _shiny_phase: float = 0.0
## Valores del brillo copiados de EnemyBase.LOOK al encenderlo: tick_shiny
## corre cada frame por cada shiny y así no lee el Resource.
var _hue_speed: float = 0.0
var _saturation: float = 0.0
var _alpha: float = 0.0


func cache_meshes(visual: Node3D) -> void:
	_meshes.clear()
	if visual == null:
		return
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			_meshes.append(mesh_instance)


## El overlay que el cuerpo debería llevar ahora, o null si ninguno.
func current() -> Material:
	if _possessed != null:
		return _possessed
	if _elite != null:
		return _elite
	if _variant != null:
		return _variant
	return _status


func refresh() -> void:
	var overlay := current()
	for mesh: MeshInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay


## Capa de siervo poseído en `tint`. Un solo material para todo el rig: no
## guarda estado por malla.
func set_possessed(tint: Color) -> void:
	_possessed = build(Color(tint, EnemyBase.LOOK.possessed_alpha))
	refresh()


## Capa de una variante del cielo; el alfa de `albedo` es su opacidad.
func set_variant(albedo: Color) -> void:
	_variant = build(albedo)
	refresh()


## Capa de veneno, la de MENOR prioridad: los shiny y las variantes conservan
## su tinte y muestran el veneno solo en los números de daño.
func set_poisoned(on: bool) -> void:
	if on and _poison == null:
		_poison = StandardMaterial3D.new()
		_poison.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_poison.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_poison.albedo_color = EnemyBase.LOOK.poison_tint
	_status = _poison if on else null
	refresh()


## El aspecto SHINY: un overlay sin sombreado cuyo matiz cicla, para que un shiny se lea de un vistazo aun dentro de una horda
## entera de shiny. Solo material, a propósito: sin partículas ni FX del pool
## (un emisor por cuerpo vaciaría los pools). El material es propio de este
## cuerpo, así animarlo nunca toca a otro.
func apply_elite_glow(instance_id: int) -> void:
	var look := EnemyBase.LOOK
	_hue_speed = look.shiny_hue_speed
	_saturation = look.shiny_saturation
	_alpha = look.shiny_alpha
	_elite = build(Color(look.shiny_start_color, _alpha))
	_shiny_phase = float(instance_id % SHINY_PHASE_BUCKETS) / float(SHINY_PHASE_BUCKETS)
	refresh()


## Un frame del brillo shiny. Barato a propósito: una escritura en un
## material propio, sin reservar memoria ni recorrer grupos.
func tick_shiny(delta: float) -> void:
	if _elite == null:
		return
	_shiny_phase = fmod(_shiny_phase + delta * _hue_speed, 1.0)
	var tint := Color.from_hsv(_shiny_phase, _saturation, 1.0)
	_elite.albedo_color = Color(tint.r, tint.g, tint.b, _alpha)


## Color del estallido de muerte: el albedo de la primera malla visual, así
## las esquirlas se leen como pedazos del cuerpo. Los shiny conservan su piel
## base (el brillo es un overlay, que get_active_material ignora).
func death_burst_color() -> Color:
	for mesh_instance: MeshInstance3D in _meshes:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null \
				or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return EnemyBase.LOOK.death_burst_fallback


## Material de capa sin sombreado y transparente: se ve solo `albedo` (color y
## opacidad); un material sin sombreado no dibuja emisión.
static func build(albedo: Color) -> StandardMaterial3D:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = albedo
	return overlay
