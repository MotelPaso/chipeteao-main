class_name EventAltar
extends Interactable
## Storm glass on a pedestal (iteration 55): free, one use, and it summons
## a random WEATHER through the same forced entry the probe and
## BONK_WEATHER_NOW use — so an altar can interrupt whatever is running and
## does not care about the cadence gap.
##
## It refuses the two REWARD rows (golden rain, full moon). Those are what
## surviving a bad one pays out; an altar that could hand one over directly
## would make the rains and dark moons that earn them pointless.
##
## Free on purpose: the price is that you do not get to choose, and a
## disaster is one of the possible answers.

@export var sink_time: float = 0.55
@export var glass_color: Color = Color(0.7, 0.78, 1.0)

## Shown while something is already running: the summon still works and
## REPLACES it, which is what the forced entry does.
const BUSY_PROMPT: String = "[E] Invocar (reemplaza el evento actual)"
const READY_PROMPT: String = "[E] Invocar un evento"
## Two detuned frequencies so the glass never pulses on a metronome.
const SWIRL_X_HZ: float = 1.3
const SWIRL_Z_HZ: float = 1.7

var _glass: MeshInstance3D = null
var _time: float = 0.0
var _spent: bool = false


func _init() -> void:
	prompt_text = READY_PROMPT
	marker_kind = &"event_altar"
	prompt_height = 3.0
	meta_stat_id = "shrines_used"
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# Detection ring BEFORE super(), which wires body_entered on this Area3D.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.2
	cylinder.height = 3.5
	shape.shape = cylinder
	shape.position.y = 1.75
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	var pedestal := MeshInstance3D.new()
	var stone := BoxMesh.new()
	stone.size = Vector3(1.1, 1.0, 1.1)
	pedestal.mesh = stone
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.28, 0.29, 0.34)
	rock.roughness = 0.9
	pedestal.material_override = rock
	pedestal.position.y = 0.5
	add_child(pedestal)
	_glass = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.45
	orb.height = 0.9
	_glass.mesh = orb
	# Per-instance material: the swirl writes emission energy, and a shared
	# resource would pulse every other altar on the map with it.
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(glass_color, 0.75)
	glass.emission_enabled = true
	glass.emission = glass_color
	glass.emission_energy_multiplier = 1.8
	_glass.material_override = glass
	_glass.position.y = 1.45
	add_child(_glass)
	var light := OmniLight3D.new()
	light.light_color = glass_color
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position.y = 1.45
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _glass != null and available:
		_glass.scale = Vector3(
				1.0 + sin(_time * SWIRL_X_HZ) * 0.07, 1.0,
				1.0 + cos(_time * SWIRL_Z_HZ) * 0.07)
	if available and player_in_range:
		# Re-rendered every frame while somebody stands here, the way the
		# chest and the spring re-render their prices: the answer changes
		# on its own as weather starts and ends.
		set_prompt(READY_PROMPT if _director_idle() else BUSY_PROMPT)


## True when no weather is running. Only the PROMPT reads this: the altar
## always works. Refusing while busy made it a POI that never resolved —
## it stayed `available`, so the tour kept walking back to it every
## REVISIT_COOLDOWN and the soak measured half the map coverage it used to.
## Summoning over a running row is also what the forced entry is FOR, and
## the player opted in by pressing the button; the busy prompt is there so
## they know what they are trading away.
func _director_idle() -> bool:
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null:
		return true
	var live: Variant = director.get("active_weather")
	return live == null or (live is Dictionary and (live as Dictionary).is_empty())


func _interact(_player: Node) -> void:
	if _spent or not available:
		return
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null or not director.has_method("random_altar_weather"):
		return
	var summoned := String(director.call("random_altar_weather"))
	if summoned.is_empty():
		return
	_spent = true
	_emit_started()
	consume()
	# Through start_sky_event, the ONE forced entry: it stops what is
	# running and ignores the cadence gap, which is exactly what a summon
	# has to do.
	director.call("start_sky_event", summoned)
	print("Event altar used: %s" % summoned)
	Juice.sparkle(global_position + Vector3.UP * 1.5)
	_emit_completed()
	_sink()


func _sink() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
